#!/usr/bin/env python3
"""Verify the decoupled APK and its pinned runtime metadata, without publishing."""
import argparse,json,re,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--apk',type=Path);a=p.parse_args()
runtime=json.loads((root/'assets/toolkit-runtime.json').read_text())
pin=re.search(r"const bundleHash\s*=\s*'([0-9a-f]{64})'",(root/'lib/benro.dart').read_text())
assert pin and pin[1]==runtime['sha256'],'Runtime pin mismatch'
assert runtime['id']=='toolkit-runtime'
assert 'assets/runtime/pilot.tar.gz' not in (root/'pubspec.yaml').read_text()
if a.apk:
 with zipfile.ZipFile(a.apk) as z:
  names=z.namelist()
  assert not any(n.startswith('assets/flutter_assets/assets/runtime/') or n.endswith('pilot.tar.gz') for n in names),'Bundled project payload'
  assert 'assets/flutter_assets/assets/catalog.json' not in names,'Bundled project catalog'
  assert json.loads(z.read('assets/flutter_assets/assets/toolkit-runtime.json'))==runtime
print(json.dumps({'result':'passed','apk':str(a.apk) if a.apk else None,'runtime_sha256':runtime['sha256'],'bundled_projects':0}))
