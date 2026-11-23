#!/usr/bin/env python3
"""Verify the local two-version catalog against exact archives, without publishing."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--catalog', type=Path, default=root/'catalog-v2.json')
p.add_argument('--runtime', type=Path, required=True)
p.add_argument('--beta8', type=Path, required=True)
p.add_argument('--pilot220', type=Path, required=True)
p.add_argument('--require-assets', action='store_true')
a = p.parse_args()
catalog = json.loads(a.catalog.read_text())
assert catalog['schema'] == 2 and len(catalog['projects']) == 2
runtime = json.loads((root/'assets/toolkit-runtime.json').read_text())
assert all(catalog['runtime'][k] == v for k,v in runtime.items())
beta, release = catalog['projects']
assert beta['id'] == release['id'] == 'alpaca-pilot'
assert beta['sha256'] == '30d34031d479505ce3f05a9cdabc6264f231ed7a2aec029edb0fff11c4467f1d'
assert beta['recommended'] and not release['recommended']
rows=[]
for manifest,archive in [(catalog['runtime'],a.runtime),(beta,a.beta8),(release,a.pilot220)]:
    assert archive.stat().st_size == manifest['archive_bytes'], archive.name
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest['sha256'], archive.name
    with tarfile.open(archive) as tar:
        members=tar.getmembers()
        assert all(m.isfile() or m.isdir() for m in members)
        assert sum(m.size for m in members) == manifest['unpacked_bytes']
        if manifest['id'] != 'toolkit-runtime':
            data=tar.extractfile('BUNDLE-MANIFEST.json').read()
            assert hashlib.sha256(data).hexdigest() == manifest['manifest_sha256']
        else:
            assert not any('/site-packages/' in m.name or '/alpaca-pilot-' in m.name or '/share/pilot/' in m.name for m in members)
    if a.require_assets:
        assert type(manifest.get('asset_id')) is int and manifest['asset_id'] > 0, 'Release asset ID missing: '+manifest['id']
    rows.append({'id':manifest['id'],'version':manifest['version'],'sha256':manifest['sha256']})
print(json.dumps({'result':'passed','release_asset_ids_required':a.require_assets,'archives':rows},indent=2))
