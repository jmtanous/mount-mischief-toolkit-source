#!/usr/bin/env python3
"""Add the standalone runtime recipe to the verified local source companion."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('companion', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
entries = {}
with tarfile.open(a.companion) as source:
    for member in source:
        path = Path(member.name)
        if not member.isfile() or path.is_absolute() or '..' in path.parts:
            raise ValueError('Invalid source companion member')
        entries[member.name] = source.extractfile(member).read()
manifest = json.loads(entries['SOURCE-MANIFEST.json'])
assert manifest['release'] == 'beta8', 'Toolkit runtime derives from Beta 8 rc.2'
assert set(entries) == set(manifest['sha256']) | {'SOURCE-MANIFEST.json'}
for name, expected in manifest['sha256'].items():
    assert hashlib.sha256(entries[name]).hexdigest() == expected, name
for name in ['scripts/package-toolkit-runtime.py', 'scripts/package-runtime-sources.py',
             'assets/toolkit-runtime.json', 'assets/catalog.json', 'LICENSE']:
    entries['toolkit/'+name] = (root/name).read_bytes()
entries['TOOLKIT-SOURCE-MANIFEST.json'] = (json.dumps({
    'runtime': json.loads((root/'assets/toolkit-runtime.json').read_text()),
    'base_archive_sha256': '30d34031d479505ce3f05a9cdabc6264f231ed7a2aec029edb0fff11c4467f1d',
    'scope': 'Pinned native sources and recipes inherited from the port, plus standalone extraction recipe. Python package sources are a conservative superset; no site-packages are distributed in Toolkit runtime.',
    'sha256': {n: hashlib.sha256(d).hexdigest() for n,d in sorted(entries.items())},
}, indent=2)+'\n').encode()
a.output.parent.mkdir(parents=True, exist_ok=True)
with a.output.open('wb') as raw, gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as gz:
    with tarfile.open(fileobj=gz, mode='w') as archive:
        for name,data in sorted(entries.items()):
            info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o644
            archive.addfile(info,io.BytesIO(data))
print(json.dumps({'archive':a.output.name,'sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),'bytes':a.output.stat().st_size,'files':len(entries)}))
