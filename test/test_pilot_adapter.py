import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch, MagicMock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'assets/helper'))
from pilot_adapter import PilotAdapter, atomic, validate_site

class PilotAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.proc=self.root/'proc';self.proc.mkdir()
        (self.proc/'net').mkdir();(self.proc/'net/tcp').write_text('header\n')
        self.release=self.root/'release';(self.release/'opt/alpaca-pilot-2.2/data').mkdir(parents=True)
        self.adapter=PilotAdapter(self.root,lambda:self.release,self.proc)

    def tearDown(self):self.temp.cleanup()

    def process(self,state='S',ticks='123',app=None):
        record={'pid':1234,'start':'123','main':'/helper/pilot_native.py','app':str(self.release/'opt/alpaca-pilot-2.2')}
        directory=self.proc/'1234';directory.mkdir(exist_ok=True)
        fields=[state]+['0']*18+[ticks]+['0']*5
        (directory/'stat').write_text('1234 (pilot) '+' '.join(fields))
        (directory/'cmdline').write_bytes(b'python\0'+record['main'].encode()+b'\0--app\0'+(app or record['app']).encode()+b'\0')
        atomic(self.adapter.state,record)
        return record

    def listener(self, inode='12345', owned=True):
        (self.proc/'net/tcp').write_text(f'header\n0: 00000000:15B3 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 {inode}\n')
        descriptors=self.proc/'1234/fd';descriptors.mkdir(exist_ok=True)
        link=descriptors/'5';link.unlink(missing_ok=True)
        link.symlink_to(f'socket:[{inode if owned else "other"}]')

    def test_pid_reuse_and_other_project_are_not_owned(self):
        self.process(ticks='999');self.assertIsNone(self.adapter.process())
        self.process(app='/other/project');self.assertIsNone(self.adapter.process())
        expected=self.process();self.assertEqual(self.adapter.process(),expected)

    def test_zombie_is_not_running(self):
        self.process(state='Z');self.assertIsNone(self.adapter.process())

    def test_stop_rechecks_identity_after_api(self):
        self.process();self.listener()
        def changed(*args):self.process(ticks='999')
        with patch.object(self.adapter,'action',side_effect=changed),patch('pilot_adapter.os.kill') as kill:
            with self.assertRaisesRegex(RuntimeError,'identity changed'):self.adapter.dispatch({'op':'stop'})
            kill.assert_not_called()

    def test_stop_without_owned_process_does_not_disconnect_external(self):
        with patch.object(self.adapter,'action') as api,patch('pilot_adapter.os.kill') as kill:
            self.assertTrue(self.adapter.dispatch({'op':'stop'})['stopped'])
            api.assert_not_called();kill.assert_not_called()

    def test_controller_counts_only_local_server_endpoints(self):
        (self.proc/'net/tcp').write_text('header\n0: 0100007F:2382 0100007F:ABCD 01\n1: 0100007F:ABCD 0100007F:2382 01\n2: 00000000:2382 00000000:0000 0A\n')
        self.assertEqual(len(self.adapter.clients()),1)

    def test_logs_read_bounded_tail(self):
        (self.root/'pilot.log').write_bytes(b'a'*100000+b'tail')
        result=self.adapter.dispatch({'op':'logs'})['text']
        self.assertEqual(len(result),40000);self.assertTrue(result.endswith('tail'))

    def test_invalid_site_and_clock_do_not_change_device(self):
        for value in (True,float('nan'),91):
            with self.assertRaises(ValueError):validate_site({'name':'site','latitude':value,'longitude':0,'elevation':0})
        with patch('pilot_adapter.subprocess.run') as run:
            with self.assertRaises(ValueError):self.adapter.start({'site':{'name':'site','latitude':1,'longitude':2,'elevation':3},'epoch':True})
            run.assert_not_called()

    def test_start_preserves_other_settings_and_isolates_controller(self):
        config=self.release/'opt/alpaca-pilot-2.2/data/config.pilot.json'
        atomic(config,{'custom_setting':42,'polaris_port':9090,'restore_tracking_on_restart':True})
        process=MagicMock();process.pid=1234;process.poll.return_value=None
        directory=self.proc/'1234';directory.mkdir()
        (directory/'stat').write_text('1234 (pilot) '+' '.join(['S']+['0']*18+['123']))
        with patch('pilot_adapter.subprocess.run') as date,patch('pilot_adapter.subprocess.Popen',return_value=process) as spawn,patch('pilot_adapter.socket.socket'):
            result=self.adapter.start({'site':{'name':'Confirmed','latitude':1,'longitude':2,'elevation':3},'epoch':int(time.time()),'operation':'start-1'})
        self.assertTrue(result['started'])
        saved=json.loads(config.read_text());self.assertEqual(saved['custom_setting'],42)
        self.assertEqual(saved['polaris_port'],19090);self.assertFalse(saved['restore_tracking_on_restart']);self.assertFalse(saved['polaris_auto_retry'])
        self.assertEqual(saved['location'],'Confirmed')
        self.assertIn('pilot_native.py',spawn.call_args.args[0][2])
        self.assertTrue(spawn.call_args.kwargs['start_new_session'])
        self.assertEqual(date.call_args.kwargs['timeout'],10)

    def test_existing_process_start_is_read_only(self):
        self.process()
        with patch.object(self.adapter,'start') as start:
            self.assertTrue(self.adapter.dispatch({'op':'start'})['already_running'])
            start.assert_not_called()

    def test_api_requires_listening_socket_owned_by_exact_process(self):
        self.process();self.listener(owned=False)
        self.assertFalse(self.adapter.owns_api())
        self.listener();self.assertTrue(self.adapter.owns_api())
        self.process(ticks='999');self.assertFalse(self.adapter.owns_api())

    def test_external_api_is_not_used_as_managed_readiness(self):
        self.process();self.listener(owned=False)
        with patch.object(self.adapter,'action') as action:
            state=self.adapter.dispatch({'op':'status'})
            self.assertTrue(state['running']);self.assertTrue(state['starting'])
            self.assertNotIn('pilot',state);action.assert_not_called()

    def test_connect_and_direct_mutation_refuse_external_api(self):
        self.process();self.listener(owned=False)
        with patch('pilot_adapter.build_opener') as http:
            for request in ({'op':'connect'},):
                with self.assertRaisesRegex(RuntimeError,'not owned'):self.adapter.dispatch(request)
            for name in ('Polaris:ConnectPolaris','Polaris:DisconnectPolaris','Polaris:ConfigUpdate'):
                with self.assertRaisesRegex(RuntimeError,'not owned'):self.adapter.action(name)
            http.assert_not_called()

    def test_stop_signals_owned_process_without_disconnecting_external_api(self):
        self.process();self.listener(owned=False)
        with patch.object(self.adapter,'action') as action,patch('pilot_adapter.os.kill',side_effect=lambda *args:self.process(state='Z')) as kill:
            self.assertTrue(self.adapter.dispatch({'op':'stop'})['stopped'])
            action.assert_not_called();kill.assert_called_once()

if __name__=='__main__':unittest.main()
