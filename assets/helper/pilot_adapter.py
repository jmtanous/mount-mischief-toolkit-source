"""Pilot-specific lifecycle, isolated from package management and firmware."""
import contextlib
import json
import math
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.parse import urlencode
from urllib.request import ProxyHandler, Request, build_opener


def atomic(path, data):
    tmp = path.with_suffix(path.suffix + '.new')
    with tmp.open('w') as stream:
        json.dump(data, stream)
        stream.flush()
        os.fsync(stream.fileno())
    tmp.replace(path)


def validate_site(site):
    for key, low, high in [('latitude', -90, 90), ('longitude', -180, 180), ('elevation', -500, 10000)]:
        value = site[key]
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError('Invalid ' + key)
    if not isinstance(site['name'], str) or not site['name'].strip() or len(site['name']) > 120:
        raise ValueError('Invalid site name')


class PilotAdapter:
    def __init__(self, root, installed, proc=Path('/proc')):
        self.root = root
        self.state = root / 'process.json'
        self.installed = installed
        self.proc = proc

    def process(self):
        if not self.state.exists():
            return None
        record = json.loads(self.state.read_text())
        if type(record.get('pid')) is not int or record['pid'] <= 1:
            raise ValueError('Invalid process record; refusing to signal a process')
        process_dir = self.proc / str(record['pid'])
        try:
            stat = process_dir.joinpath('stat').read_text().rsplit(')', 1)[1].split()
            args = process_dir.joinpath('cmdline').read_bytes().split(b'\0')
            if stat[0] == 'Z':
                return None
            if stat[19] == record['start'] and record['main'].encode() in args and record['app'].encode() in args:
                return record
        except FileNotFoundError:
            pass
        return None

    def action(self, name, parameters=None):
        allowed = {'Polaris:StatusFetch', 'Polaris:ConnectPolaris', 'Polaris:DisconnectPolaris', 'Polaris:ConfigUpdate'}
        if name not in allowed:
            raise ValueError('Unsupported Pilot action')
        if name != 'Polaris:StatusFetch' and not self.owns_api():
            raise RuntimeError('Pilot API is not owned by this managed process')
        data = urlencode({'Action': name, 'Parameters': json.dumps(parameters or {}),
                          'ClientID': 81, 'ClientTransactionID': 1}).encode()
        request = Request('http://127.0.0.1:5555/api/v1/telescope/0/action', data=data, method='PUT')
        with build_opener(ProxyHandler({})).open(request, timeout=10) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise ValueError('Pilot response too large')
        result = json.loads(raw)
        if result.get('ErrorNumber', 0):
            raise RuntimeError(result)
        return result.get('Value')

    def owns_api(self, live=None, port=5555):
        live = live or self.process()
        if not live:
            return False
        try:
            listeners = set()
            for row in self.proc.joinpath('net/tcp').read_text().splitlines()[1:]:
                fields = row.split()
                if len(fields) > 9 and fields[1] in (f'00000000:{port:04X}', f'0100007F:{port:04X}') and fields[3] == '0A':
                    listeners.add('socket:[' + fields[9] + ']')
            for descriptor in (self.proc/str(live['pid'])/'fd').iterdir():
                try:
                    if str(descriptor.readlink()) in listeners:
                        return self.process() == live
                except FileNotFoundError:
                    continue  # A descriptor may close while inspecting it.
        except (FileNotFoundError, PermissionError):
            pass
        return False

    def clients(self):
        rows = self.proc.joinpath('net/tcp').read_text().splitlines()[1:]
        # Count server endpoints only; a native loopback socket appears twice.
        return [row for row in rows if row.split()[1].split(':')[1] == '2382' and row.split()[3] == '01']

    def start(self, request):
        site = request['site']
        validate_site(site)
        epoch = request['epoch']
        if type(epoch) is not int or not 1735689600 <= epoch <= 4102444800:
            raise ValueError('Phone clock is invalid')
        root = self.installed()
        if root is None:
            raise RuntimeError('Install runtime first')
        app, prefix = root / 'opt/alpaca-pilot-2.2', root / 'opt/benro-python'
        for port in (5555, 5556, 8081, 19090):
            with socket.socket() as probe:
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                probe.bind(('0.0.0.0', port))
        subprocess.run(['date', '-u', '-s', time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(epoch))],
                       check=True, stdout=subprocess.DEVNULL, timeout=10)
        if abs(time.time() - epoch) > 10:
            raise RuntimeError('Clock synchronization failed')
        overrides = {
            'polaris_ip_address': '127.0.0.1', 'polaris_port': 19090, 'polaris_auto_retry': False,
            'restore_tracking_on_restart': False, 'enable_remote_shutdown': False, 'enable_mdns': False,
            'enable_discovery': False, 'enable_synscan': False, 'enable_https': False, 'enable_rest_https': False,
            'alpaca_restapi_ip_address': '0.0.0.0', 'alpaca_pilot_http_port': 8081,
            'alpaca_restapi_port': 5555, 'alpaca_socket_port': 5556,
            'site_latitude': site['latitude'], 'site_longitude': site['longitude'],
            'site_elevation': site['elevation'], 'location': site['name'],
        }
        config = app / 'data/config.pilot.json'
        previous = json.loads(config.read_text()) if config.exists() else {}
        if not isinstance(previous, dict):
            raise ValueError('Invalid saved settings; reinstall with clean settings to repair')
        atomic(self.root / 'config-before-start.json', previous)
        atomic(config, {**previous, **overrides})
        environment = dict(os.environ, PYTHONNOUSERSITE='1', PYTHONDONTWRITEBYTECODE='1',
                           LD_LIBRARY_PATH=str(prefix / 'lib') + ':/lib:/usr/lib:/app/lib',
                           SSL_CERT_FILE=str(prefix / 'lib/python3.13/site-packages/certifi/cacert.pem'))
        environment.pop('PYTHONHOME', None)
        environment.pop('PYTHONPATH', None)
        main = str(Path(__file__).parent / 'pilot_native.py')
        child = None
        try:
            with (self.root / 'pilot.log').open('ab') as log:
                child = subprocess.Popen([str(prefix / 'bin/python3.13'), '-B', main, '--app', str(app), '--listen', '0.0.0.0'],
                                         cwd=app, env=environment, stdin=subprocess.DEVNULL,
                                         stdout=log, stderr=log, start_new_session=True, close_fds=True)
            if child.poll() is not None:
                raise RuntimeError('Pilot exited immediately; inspect diagnostics')
            ticks = self.proc.joinpath(str(child.pid), 'stat').read_text().rsplit(')', 1)[1].split()[19]
            atomic(self.state, {'pid': child.pid, 'start': ticks, 'main': main, 'app': str(app),
                                'operation': request.get('operation')})
        except Exception:
            if child is not None and child.poll() is None:
                child.terminate()
                with contextlib.suppress(subprocess.TimeoutExpired):
                    child.wait(timeout=10)
            raise
        return {'started': True, 'pid': child.pid}

    def dispatch(self, request):
        op = request['op']
        live = self.process()
        if op == 'status':
            status = {'running': bool(live), 'installed': self.installed() is not None,
                      'controller_clients': len(self.clients())}
            if live:
                try:
                    if not self.owns_api(live):
                        raise RuntimeError('Managed API is not ready')
                    status['pilot'] = self.action('Polaris:StatusFetch')
                except Exception:
                    status['starting'] = True
            return status
        if op == 'start':
            return {'already_running': True} if live else self.start(request)
        if op == 'connect':
            if not live:
                raise RuntimeError('Pilot is not running')
            if not self.owns_api(live):
                raise RuntimeError('Pilot API is not owned by this managed process')
            status = self.action('Polaris:StatusFetch')
            if status['connected']:
                return status
            if self.clients():
                raise RuntimeError('Another controller is connected')
            self.action('Polaris:ConfigUpdate', {'polaris_port': 9090})
            self.action('Polaris:ConnectPolaris')
            return {'connecting': True}
        if op == 'stop':
            if not live:
                return {'stopped': True}
            if self.owns_api(live):
                with contextlib.suppress(Exception):
                    self.action('Polaris:DisconnectPolaris')
            # The HTTP request may take time; re-check identity before signaling.
            if self.process() != live:
                raise RuntimeError('Process identity changed during stop; no signal sent')
            os.kill(live['pid'], signal.SIGINT)
            for _ in range(40):
                if not self.process():
                    return {'stopped': True}
                time.sleep(.5)
            raise RuntimeError('Pilot did not stop cleanly; inspect diagnostics before retrying')
        if op == 'logs':
            path = self.root / 'pilot.log'
            if not path.exists():
                return {'text': 'No startup log yet'}
            with path.open('rb') as stream:
                stream.seek(max(0, path.stat().st_size - 40000))
                return {'text': stream.read(40000).decode(errors='replace')}
        raise ValueError('Unknown Pilot operation')
