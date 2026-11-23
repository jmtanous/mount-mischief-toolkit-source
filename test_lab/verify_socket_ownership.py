"""Check real Linux /proc ownership using disposable localhost listeners only."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'assets/helper'))
from pilot_adapter import PilotAdapter, atomic


def main():
    with tempfile.TemporaryDirectory(prefix='mmt-socket-ownership-') as directory:
        pid = os.getpid()
        process = Path('/proc')/str(pid)
        args = [arg.decode() for arg in process.joinpath('cmdline').read_bytes().split(b'\0') if arg]
        ticks = process.joinpath('stat').read_text().rsplit(')', 1)[1].split()[19]
        adapter = PilotAdapter(Path(directory), lambda: None)
        atomic(adapter.state, {'pid': pid, 'start': ticks, 'main': args[0], 'app': args[-1]})
        with socket.socket() as owned:
            owned.bind(('127.0.0.1', 0)); owned.listen()
            own_port = owned.getsockname()[1]
            assert adapter.owns_api(port=own_port)
            child = subprocess.Popen([
                sys.executable, '-c',
                "import socket,sys; s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); print(s.getsockname()[1],flush=True); sys.stdin.read()",
            ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, close_fds=True)
            try:
                foreign_port = int(child.stdout.readline())
                assert not adapter.owns_api(port=foreign_port)
            finally:
                child.stdin.close()
                child.wait(timeout=5)
        assert not adapter.owns_api(port=own_port)
    print(json.dumps({'result': 'passed', 'checks': ['owned listener recognized', 'other-process listener rejected', 'closed listener rejected'], 'network': 'disposable localhost listeners only; no controller contacted'}))


if __name__ == '__main__':
    main()
