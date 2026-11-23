#!/usr/bin/env python3
"""Copy license/notice texts from the pinned local runtime into APK-visible assets."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--archive', type=Path, default=root.parent/'local/toolkit-runtime-1.0.0.tar.gz')
archive = p.parse_args().archive
expected = json.loads((root/'assets/toolkit-runtime.json').read_text())['sha256']
assert hashlib.sha256(archive.read_bytes()).hexdigest() == expected, 'Toolkit runtime hash mismatch'
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
assert files, 'Missing runtime notices'
output = {'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'files': dict(sorted(files.items()))}
(root / 'assets/legal/runtime-licenses.json').write_text(json.dumps(output, indent=2, ensure_ascii=False) + '\n')
print(f'Collected {len(files)} runtime license and notice files')
