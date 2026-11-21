#!/usr/bin/env python3
"""Copy license/notice texts from the pinned local runtime into APK-visible assets."""
import hashlib
import json
from pathlib import Path
import tarfile

root = Path(__file__).resolve().parents[1]
archive = root / 'assets/runtime/pilot.tar.gz'
files = {}
with tarfile.open(archive) as bundle:
    for member in bundle:
        name = Path(member.name).name.upper()
        if member.isfile() and (
            '/share/licenses/' in member.name
            or '.dist-info/licenses/' in member.name
            or name.startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE', 'AUTHORS'))
        ):
            files[member.name] = bundle.extractfile(member).read().decode('utf-8')
assert 'opt/alpaca-pilot-2.2/LICENSE' in files, 'Missing upstream license'
assert files['opt/alpaca-pilot-2.2/LICENSE'] == (root / 'assets/legal/alpaca-UPSTREAM-LICENSE.txt').read_text(), 'Upstream notice differs from bundled runtime'
output = {'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'files': dict(sorted(files.items()))}
(root / 'assets/legal/runtime-licenses.json').write_text(json.dumps(output, indent=2, ensure_ascii=False) + '\n')
print(f'Collected {len(files)} runtime license and notice files')
