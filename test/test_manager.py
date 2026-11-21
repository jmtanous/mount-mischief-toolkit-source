import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'assets/helper'))
from manager import Manager, atomic, digest, safe_path, verify

class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
        self.manager=Manager(self.root)
        self.manager.adapter=lambda project:type('Adapter',(),{'process':lambda self:None})()
        (self.root/'inbox').mkdir()
        payload=b'original software'
        self.files={'opt/alpaca-pilot-2.2/driver/main.py':{'size':len(payload),'sha256':hashlib.sha256(payload).hexdigest()}}
        self.file_manifest=json.dumps({'files':self.files}).encode()
        self.contents={'BUNDLE-MANIFEST.json':self.file_manifest,'opt/alpaca-pilot-2.2/driver/main.py':payload}

    def tearDown(self):self.temp.cleanup()

    def package(self,operation='first',extra=None):
        contents={**self.contents,**(extra or {})}
        path=self.root/'inbox'/(operation+'.tar.gz')
        with tarfile.open(path,'w:gz') as tf:
            for name,data in contents.items():
                entry=tarfile.TarInfo(name);entry.size=len(data)
                tf.addfile(entry,io.BytesIO(data))
        return {'schema':1,'id':'pilot','version':'2.2-beta8','adapter':'alpaca-pilot-v1',
            'devices':['benro-polaris'],'sha256':digest(path),'manifest_sha256':hashlib.sha256(self.file_manifest).hexdigest(),
            'archive_bytes':path.stat().st_size,'unpacked_bytes':sum(map(len,contents.values())),
            'resources':['benro-controller','tcp:5555','tcp:5556','tcp:8081']}

    def install(self,operation='first',op='install',keep=True):
        return self.manager.dispatch({'op':op,'project':'pilot','operation':operation,'manifest':self.package(operation),'keep_settings':keep})

    def test_install_reports_ordered_stages_and_real_file_totals(self):
        events=[]
        self.manager.progress=lambda *args: events.append(args)
        self.install()
        stages=list(dict.fromkeys(e[0] for e in events))
        self.assertEqual(stages, ['checksum','scan','extract','verify','activate'])
        self.assertIn(('extract',2,2),events)
        self.assertIn(('verify',1,1),events)

    def test_bad_archive_never_reports_activation(self):
        events=[]
        self.manager.progress=lambda *args: events.append(args)
        m=self.package(extra={'../escape':b'bad'})
        with self.assertRaises(ValueError):
            self.manager.install('pilot','first',m,True)
        self.assertNotIn('activate',[e[0] for e in events])
        self.assertIsNone(self.manager.record('pilot'))

    def test_progress_is_opt_in_and_throttled(self):
        from manager import progress_reporter
        from contextlib import redirect_stderr
        output=io.StringIO()
        with redirect_stderr(output):
            progress_reporter(False)('checksum')
        self.assertEqual(output.getvalue(),'')
        with redirect_stderr(output), patch('manager.time.monotonic',return_value=1):
            report=progress_reporter(True)
            for n in range(10001): report('extract',n,10000)
        events=[json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(len(events),2)
        self.assertEqual(events[-1]['done'],10000)

    def test_install_does_not_start_and_is_idempotent(self):
        self.install()
        self.assertTrue(self.manager.record('pilot'))
        again=self.install()
        self.assertEqual(again['phase'],'complete')
        self.assertFalse((self.manager.project('pilot')/'process.json').exists())

    def test_reinstall_preserves_then_clears_settings(self):
        self.install()
        cfg=self.manager.release('pilot')/'opt/alpaca-pilot-2.2/data/config.pilot.json'
        atomic(cfg,{'location':'Saved site'})
        self.install('second','reinstall',True)
        self.assertEqual(json.loads((self.manager.release('pilot')/'opt/alpaca-pilot-2.2/data/config.pilot.json').read_text())['location'],'Saved site')
        previous=self.manager.release('pilot')/'opt/alpaca-pilot-2.2/data/config.pilot.json'
        self.install('third','reinstall',False)
        self.assertFalse(previous.exists())
        self.assertFalse((self.manager.release('pilot')/'opt/alpaca-pilot-2.2/data/config.pilot.json').exists())
        self.assertFalse((self.manager.project('pilot')/'settings.json').exists())

    def test_explicit_choice_required(self):
        self.install()
        with self.assertRaisesRegex(ValueError,'Choose'):
            self.manager.dispatch({'op':'uninstall','project':'pilot','operation':'remove'})
        self.assertIsNotNone(self.manager.record('pilot'))

    def test_corruption_preserves_active_release(self):
        self.install()
        m=self.package('bad');m['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'checksum'):
            self.manager.dispatch({'op':'reinstall','project':'pilot','operation':'bad','manifest':m,'keep_settings':True})
        self.assertEqual(self.manager.record('pilot')['release'],'first')

    def test_reject_unmanifested_file(self):
        m=self.package('bad',{'surprise':b'no'})
        with self.assertRaisesRegex(ValueError,'Unmanifested'):
            self.manager.dispatch({'op':'install','project':'pilot','operation':'bad','manifest':m})
        self.assertIsNone(self.manager.record('pilot'))

    def test_reject_traversal(self):
        m=self.package('bad',{'../../escape':b'no'})
        with self.assertRaisesRegex(ValueError,'Unsafe'):
            self.manager.dispatch({'op':'install','project':'pilot','operation':'bad','manifest':m})
        self.assertFalse((self.root/'escape').exists())

    def test_symlink_is_rejected_before_resolution(self):
        (self.root/'real').write_text('test')
        (self.root/'link').symlink_to('real')
        with self.assertRaisesRegex(ValueError,'Links'):safe_path(self.root,'link')

    def test_manifest_replacement_rejected(self):
        (self.root/'BUNDLE-MANIFEST.json').write_text('{"files":{}}')
        with self.assertRaisesRegex(ValueError,'checksum'):verify(self.root,'0'*64)
        with self.assertRaisesRegex(ValueError,'Empty'):verify(self.root,digest(self.root/'BUNDLE-MANIFEST.json'))

    def test_activation_recovery(self):
        self.install()
        self.manager.journal('first',phase='activating')
        self.assertEqual(self.manager.recover('first')['phase'],'complete')
        self.manager.journal('lost',project='pilot',action='install',phase='extracting')
        self.assertEqual(self.manager.recover('lost')['phase'],'interrupted')

    def test_uninstall_only_managed_project(self):
        self.install()
        unrelated=self.root/'unmanaged';unrelated.mkdir();(unrelated/'keep').write_text('yes')
        self.manager.dispatch({'op':'uninstall','project':'pilot','operation':'remove','keep_settings':True})
        self.assertIsNone(self.manager.record('pilot'))
        self.assertEqual((unrelated/'keep').read_text(),'yes')

    def test_uninstall_recovery_finishes_interrupted_file_removal(self):
        for keep in (True, False):
            with self.subTest(keep_settings=keep):
                self.install('install-'+str(keep).lower())
                atomic(self.manager.release('pilot')/'opt/alpaca-pilot-2.2/data/config.pilot.json',{'saved':True})
                operation='remove-'+str(keep).lower()
                with patch.object(self.manager,'remove_releases',side_effect=SystemExit('power loss')):
                    with self.assertRaises(SystemExit):
                        self.manager.dispatch({'op':'uninstall','project':'pilot','operation':operation,'keep_settings':keep})
                self.assertIsNone(self.manager.record('pilot'))
                self.assertTrue((self.manager.project('pilot')/'releases').exists())
                result=self.manager.recover(operation)
                self.assertEqual(result['phase'],'complete')
                self.assertEqual(result['result']['settings_retained'],keep)
                self.assertFalse((self.manager.project('pilot')/'releases').exists())
                self.assertEqual((self.manager.project('pilot')/'settings.json').exists(),keep)

    def test_uninstall_recovery_does_not_remove_a_running_release(self):
        self.install()
        self.manager.journal('remove',project='pilot',action='uninstall',phase='removing',keep_settings=True)
        (self.manager.project('pilot')/'installed.json').unlink()
        self.manager.adapter=lambda project:type('Adapter',(),{'process':lambda self:{'pid':1}})()
        self.assertEqual(self.manager.recover('remove')['phase'],'interrupted')
        self.assertTrue((self.manager.project('pilot')/'releases').exists())


    def test_activation_failure_preserves_previous(self):
        self.install()
        original=atomic
        def fail_activation(path,value):
            if path.name=='installed.json' and value['release']=='second':
                raise OSError('simulated power loss before activation')
            original(path,value)
        with patch('manager.atomic',side_effect=fail_activation):
            with self.assertRaises(OSError):self.install('second','reinstall',False)
        self.assertEqual(self.manager.record('pilot')['release'],'first')
        self.assertEqual(self.manager.recover('second')['phase'],'failed')

    def test_clean_activation_recovery_removes_old_settings(self):
        self.install()
        atomic(self.manager.project('pilot')/'settings.json',{'old':'settings'})
        self.manager.journal('first',phase='activating',keep_settings=False)
        self.manager.recover('first')
        self.assertFalse((self.manager.project('pilot')/'settings.json').exists())

    def test_failed_uninstall_does_not_touch_running_project(self):
        self.install()
        self.manager.adapter=lambda project:type('Adapter',(),{'process':lambda self:{'pid':1}})()
        with self.assertRaisesRegex(ValueError,'Stop'):
            self.manager.dispatch({'op':'uninstall','project':'pilot','operation':'remove','keep_settings':False})
        self.assertIsNotNone(self.manager.record('pilot'))

    def test_symlink_archive_member_rejected(self):
        m=self.package('bad')
        archive=self.root/'inbox/bad.tar.gz'
        with tarfile.open(archive,'w:gz') as tf:
            entry=tarfile.TarInfo('link');entry.type=tarfile.SYMTYPE;entry.linkname='/tmp/escape';tf.addfile(entry)
        m.update(sha256=digest(archive),archive_bytes=archive.stat().st_size)
        with self.assertRaisesRegex(ValueError,'regular files'):
            self.manager.dispatch({'op':'install','project':'pilot','operation':'bad','manifest':m})

    def test_resource_conflict_blocks_start(self):
        self.install()
        second=self.manager.project('another')/'installed.json'
        atomic(second,self.manager.record('pilot'))
        self.manager.adapter=lambda project:type('Adapter',(),{'process':lambda self:{'pid':1}})()
        with self.assertRaisesRegex(ValueError,'resources'):
            self.manager.dispatch({'op':'start','project':'pilot','operation':'start'})

    def test_insufficient_space_preserves_existing(self):
        self.install()
        with patch('manager.shutil.disk_usage',return_value=type('Usage',(),{'free':0})()):
            with self.assertRaisesRegex(ValueError,'space'):self.install('second','reinstall',True)
        self.assertEqual(self.manager.record('pilot')['release'],'first')


    def test_staged_upload_is_visible_and_install_can_complete(self):
        m=self.package('staged')
        request={'op':'stage','project':'pilot','operation':'staged','action':'install','manifest':m,'keep_settings':True}
        self.assertEqual(self.manager.dispatch(request)['phase'],'uploading')
        self.assertEqual(self.manager.recover('staged')['phase'],'interrupted')
        self.assertIsNone(self.manager.record('pilot'))
        result=self.manager.dispatch({**request,'op':'install'})
        self.assertEqual(result['release'],'staged')

    def test_staged_manifest_cannot_change_mid_upload(self):
        m=self.package('staged')
        request={'op':'stage','project':'pilot','operation':'staged','action':'install','manifest':m,'keep_settings':True}
        self.manager.dispatch(request)
        with self.assertRaisesRegex(ValueError,'changed'):
            self.manager.dispatch({**request,'op':'install','keep_settings':False})
        self.assertIsNone(self.manager.record('pilot'))

    def test_retry_of_failed_operation_is_not_success(self):
        m=self.package('broken');m['sha256']='0'*64
        request={'op':'install','project':'pilot','operation':'broken','manifest':m}
        with self.assertRaises(ValueError):self.manager.dispatch(request)
        with self.assertRaises(RuntimeError):self.manager.dispatch(request)

if __name__=='__main__':unittest.main()
