"""Mount Mischief Toolkit SD package engine. One JSON request/response per call.

No firmware, boot hooks, arbitrary shell hooks, or unmanaged-process adoption.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parent
ADAPTERS = {'alpaca-pilot-v1'}
ID = re.compile(r'^[a-z0-9][a-z0-9-]{0,63}$')
DIGEST = re.compile(r'^[0-9a-f]{64}$')


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.new')
    with tmp.open('w') as f:
        json.dump(value, f, sort_keys=True); f.flush(); os.fsync(f.fileno())
    tmp.replace(path)


def read(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def identifier(value):
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise ValueError('Invalid project or operation identifier')
    return value


def safe_path(root, name):
    parts = PurePosixPath(name)
    if not name or parts.is_absolute() or '..' in parts.parts or '\\' in name:
        raise ValueError('Unsafe package path')
    p = root
    if p.is_symlink(): raise ValueError('Linked package root')
    for part in parts.parts:
        p = p / part
        if p.is_symlink(): raise ValueError('Links are not supported')
    if not p.resolve().is_relative_to(root.resolve()): raise ValueError('Path escaped root')
    return p


def manifest(value):
    if value.get('schema') != 1: raise ValueError('Unsupported manifest schema')
    identifier(value.get('id'))
    if value.get('adapter') not in ADAPTERS: raise ValueError('Update Toolkit for this adapter')
    for key in ('sha256', 'manifest_sha256'):
        if not DIGEST.fullmatch(value.get(key, '')): raise ValueError('Invalid '+key)
    for key in ('archive_bytes', 'unpacked_bytes'):
        if type(value.get(key)) is not int or value[key] <= 0: raise ValueError('Invalid '+key)
    if not isinstance(value.get('version'), str) or not value['version']: raise ValueError('Missing version')
    if value.get('min_manager_schema', 1) > 1: raise ValueError('Update Toolkit first')
    if value.get('devices') != ['benro-polaris']: raise ValueError('Unsupported device family')
    if not isinstance(value.get('resources'), list) or not all(isinstance(r,str) for r in value['resources']):
        raise ValueError('Invalid resource declarations')
    required = {'benro-controller', 'tcp:5555', 'tcp:5556', 'tcp:8081'}
    if not required.issubset(value['resources']): raise ValueError('Missing Pilot resource declarations')
    return value


def verify(root, expected, progress=lambda *args: None):
    p = safe_path(root, 'BUNDLE-MANIFEST.json')
    if digest(p) != expected: raise ValueError('Manifest checksum mismatch')
    files = read(p)['files']
    if not isinstance(files, dict) or not files: raise ValueError('Empty file manifest')
    progress("verify", 0, len(files))
    for index, (name, record) in enumerate(files.items(), 1):
        p = safe_path(root, name)
        if not p.is_file() or p.stat().st_size != record['size'] or digest(p) != record['sha256']:
            raise ValueError('Corrupt package file: '+name)
        progress("verify", index, len(files))
    return files


class Manager:
    def __init__(self, root=ROOT, progress=lambda *args: None):
        self.progress = progress
        self.root = root
        self.projects = root / 'projects'
        self.operations = root / 'operations'

    def project(self, project):
        return safe_path(self.projects, identifier(project))

    def record(self, project):
        return read(self.project(project)/'installed.json')

    def release(self, project, record=None):
        record = record or self.record(project)
        if not record: raise ValueError('Project is not installed')
        return safe_path(self.project(project)/'releases', identifier(record['release']))

    def adapter(self, project):
        from pilot_adapter import PilotAdapter
        p = self.project(project)
        p.mkdir(parents=True, exist_ok=True)
        return PilotAdapter(p, lambda: self.release(project) if self.record(project) else None)

    def inspect(self, project):
        record = self.record(project)
        adapter = self.adapter(project)
        state = adapter.dispatch({'op':'status'})
        state.update(id=project, installation=record, managed=bool(adapter.process()))
        cfg = self.release(project)/'opt/alpaca-pilot-2.2/data/config.pilot.json' if record else self.project(project)/'settings.json'
        state['retained_settings'] = (self.project(project)/'settings.json').exists()
        try:
            state['settings'] = read(cfg if cfg.exists() else self.project(project)/'settings.json', {})
            if not isinstance(state['settings'], dict): raise ValueError('Settings must be an object')
        except (ValueError, OSError) as exc:
            state['settings'] = {}
            state['settings_error'] = str(exc)
        if not state['running']:
            try:
                state['external_pilot'] = adapter.action('Polaris:StatusFetch')
            except Exception:
                pass
        return state

    def snapshot_settings(self, project):
        record = self.record(project)
        if record:
            cfg = self.release(project)/'opt/alpaca-pilot-2.2/data/config.pilot.json'
            if cfg.exists(): atomic(self.project(project)/'settings.json', read(cfg))

    def clear_settings(self, project, active_release=None):
        directory = self.project(project)
        for name in ('settings.json', 'config-before-start.json'):
            safe_path(directory, name).unlink(missing_ok=True)
        # Retained rollback releases must not resurrect settings the user deleted.
        for release in (directory/'releases').glob('*'):
            if release.name != active_release:
                safe_path(release, 'opt/alpaca-pilot-2.2/data/config.pilot.json').unlink(missing_ok=True)

    def journal(self, operation, **changes):
        path = self.operations/(identifier(operation)+'.json')
        current = read(path, {})
        current.update(changes, updated_at=int(time.time()))
        atomic(path, current)
        return current

    def conflicts(self, project, resources):
        result = []
        for p in self.projects.glob('*/installed.json'):
            other = p.parent.name
            if other != project and self.adapter(other).process():
                overlap = set(read(p)['manifest']['resources']) & set(resources)
                if overlap: result.append({'project':other,'resources':sorted(overlap)})
        return result

    def install(self, project, operation, m, keep):
        m = manifest(m)
        if m['id'] != project: raise ValueError('Project identity mismatch')
        old = self.record(project)
        if old and self.adapter(project).process(): raise ValueError('Stop project before reinstalling')
        archive = safe_path(self.root/'inbox', operation+'.tar.gz')
        self.progress('checksum')
        if archive.stat().st_size != m['archive_bytes'] or digest(archive) != m['sha256']:
            raise ValueError('Archive checksum mismatch')
        project_dir = self.project(project)
        stage = project_dir/'staging'/operation
        target = project_dir/'releases'/operation
        if stage.exists() or target.exists(): raise ValueError('Operation already has staged files; inspect recovery')
        project_dir.mkdir(parents=True,exist_ok=True)
        if shutil.disk_usage(project_dir).free < m['unpacked_bytes'] + 64*1024*1024:
            raise ValueError('Insufficient SD space')
        if keep: self.snapshot_settings(project)
        self.journal(operation, phase='extracting', previous=old, keep_settings=keep)
        stage.mkdir(parents=True)
        self.progress('scan')
        with tarfile.open(archive, 'r:gz') as tf:
            members = []
            names=set(); total=0
            for member in tf:
                safe_path(stage, member.name)
                if not (member.isfile() or member.isdir()): raise ValueError('Only regular files and directories allowed')
                canonical = str(PurePosixPath(member.name))
                if canonical in names: raise ValueError('Duplicate archive path')
                names.add(canonical); total += member.size
                if total > m['unpacked_bytes']: raise ValueError('Archive exceeds declared size')
                if len(names) > 100000: raise ValueError('Too many archive entries')
                members.append(member)
            self.progress('extract', 0, len(members))
            def tracked_members():
                for index, member in enumerate(members, 1):
                    yield member
                    self.progress('extract', index, len(members))
            tf.extractall(stage, members=tracked_members(), filter='data')
        files = verify(stage, m['manifest_sha256'], self.progress)
        actual={str(p.relative_to(stage)) for p in stage.rglob('*') if p.is_file()}
        if actual != set(files)|{'BUNDLE-MANIFEST.json'}: raise ValueError('Unmanifested package files')
        self.journal(operation, phase='verified')
        self.progress('activate')
        if keep:
            saved = read(project_dir/'settings.json')
            if saved is not None: atomic(stage/'opt/alpaca-pilot-2.2/data/config.pilot.json', saved)
        target.parent.mkdir(parents=True,exist_ok=True)
        stage.rename(target)
        new = {'release':operation, 'manifest':m, 'installed_at':int(time.time())}
        self.journal(operation, phase='activating', next=new)
        atomic(project_dir/'installed.json', new)
        if not keep: self.clear_settings(project, active_release=operation)
        self.journal(operation, phase='complete')
        return new

    def recover(self, operation):
        state=read(self.operations/(identifier(operation)+'.json'))
        if not state: raise ValueError('Unknown operation')
        project=state['project']; record=self.record(project)
        if state['phase'] not in ('complete','failed','interrupted'):
            if state['action'] in ('install','reinstall') and record and record['release']==operation:
                if state.get('keep_settings') is False:
                    self.clear_settings(project, active_release=operation)
                return self.journal(operation,phase='complete')
            if state['action']=='uninstall' and state['phase']=='removing' and record is None:
                if self.adapter(project).process():
                    return self.journal(operation,phase='interrupted',detail='Project is running; stop it before finishing removal')
                self.remove_releases(project)
                return self.journal(operation,phase='complete',result={'uninstalled':True,'settings_retained':state['keep_settings']})
            return self.journal(operation,phase='interrupted',resume_phase=state['phase'],detail='Inspect project state before retrying with a new operation ID')
        return state

    def remove_releases(self, project):
        # Only this project's validated managed directory may be removed.
        releases=safe_path(self.project(project),'releases')
        if releases.exists(): shutil.rmtree(releases)

    def dispatch(self, request):
        op=request['op']
        if op=='list':
            return {'projects':[self.inspect(p.parent.name) for p in self.projects.glob('*/installed.json')],
                    'operations':[self.recover(p.stem) for p in self.operations.glob('*.json')]}
        if op=='operation': return self.recover(request['operation'])
        project=identifier(request['project'])
        if op=='inspect': return self.inspect(project)
        if op=='logs': return self.adapter(project).dispatch({'op':'logs'})
        operation=identifier(request['operation'])
        if op=='stage':
            action=request['action']
            if action not in ('install','reinstall'): raise ValueError('Unsupported staged action')
            m=manifest(request['manifest'])
            if m['id']!=project: raise ValueError('Project identity mismatch')
            if type(request.get('keep_settings')) is not bool: raise ValueError('Choose whether to keep saved settings')
            if (self.operations/(operation+'.json')).exists(): raise ValueError('Operation already exists')
            return self.journal(operation,project=project,action=action,phase='uploading',manifest=m,keep_settings=request['keep_settings'])
        if (self.operations/(operation+'.json')).exists():
            previous=self.recover(operation)
            if previous['project'] != project or previous['action'] != op: raise ValueError('Operation identity conflict')
            resumable=previous['phase']=='interrupted' and previous.get('resume_phase')=='uploading'
            if op in ('install','reinstall') and resumable:
                if previous['manifest']!=request.get('manifest') or previous['keep_settings']!=request.get('keep_settings'):
                    raise ValueError('Staged request changed')
            elif previous['phase']=='complete':
                return previous
            else:
                raise RuntimeError(previous.get('error') or previous.get('detail') or 'Operation did not complete; inspect before retrying')
        if op not in ('install','reinstall','uninstall','start','connect','stop'): raise ValueError('Unknown operation')
        if op in ('reinstall','uninstall') and type(request.get('keep_settings')) is not bool:
            raise ValueError('Choose whether to keep saved settings')
        self.journal(operation,project=project,action=op,phase='started')
        try:
            if op in ('install','reinstall'):
                if op=='install' and self.record(project): raise ValueError('Already installed; use reinstall')
                if op=='reinstall' and not self.record(project): raise ValueError('Not installed')
                result=self.install(project,operation,request['manifest'],request.get('keep_settings',True))
            elif op=='uninstall':
                if self.adapter(project).process(): raise ValueError('Stop project before uninstalling')
                if request['keep_settings']: self.snapshot_settings(project)
                else: self.clear_settings(project)
                self.journal(operation,phase='removing',keep_settings=request['keep_settings'])
                (self.project(project)/'installed.json').unlink(missing_ok=True)
                self.remove_releases(project)
                result={'uninstalled':True,'settings_retained':request['keep_settings']}
            else:
                if op in ('start','connect'):
                    record=self.record(project)
                    if not record: raise ValueError('Not installed')
                    if self.conflicts(project,record['manifest']['resources']): raise ValueError('Another project owns required resources')
                result=self.adapter(project).dispatch({**request,'op':op})
                if op=='stop': self.snapshot_settings(project)
            self.journal(operation,phase='complete',result=result)
            return result
        except Exception as exc:
            self.journal(operation,phase='failed',error=str(exc))
            raise


def progress_reporter(enabled):
    last_stage = None
    last_time = 0.0
    def report(stage, done=None, total=None):
        nonlocal last_stage, last_time
        now = time.monotonic()
        if not enabled or (stage == last_stage and done != total and now - last_time < 0.5):
            return
        print(json.dumps({'type': 'installation_progress', 'stage': stage,
                          'done': done, 'total': total}), file=sys.stderr, flush=True)
        last_stage, last_time = stage, now
    return report


def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    with (ROOT/'manager.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        request=json.load(sys.stdin)
        result=Manager(progress=progress_reporter(request.get('progress') is True)).dispatch(request)
        print(json.dumps({'ok':True,'result':result}))


if __name__=='__main__':
    try: main()
    except Exception as exc:
        print(json.dumps({'ok':False,'error':str(exc)}))
        sys.exit(1)
