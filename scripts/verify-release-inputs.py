#!/usr/bin/env python3
"""Check bundled runtime, catalog, notices and optional built APK as one candidate."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import tarfile
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', type=Path)
args = parser.parse_args()
archive = root/'assets/runtime/pilot.tar.gz'
project = next(p for p in json.loads((root/'assets/catalog.json').read_text())['projects']
               if p['id'] == 'alpaca-pilot')
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
if sha != project['sha256'] or archive.stat().st_size != project['archive_bytes']:
    raise SystemExit('Runtime archive does not match catalog')
pin = re.search(r"const bundleHash\s*=\s*'([0-9a-f]{64})'", (root/'lib/benro.dart').read_text())
if not pin or pin[1] != sha:
    raise SystemExit('Bootstrap runtime pin does not match catalog')
licenses = json.loads((root/'assets/legal/runtime-licenses.json').read_text())
if licenses['archive_sha256'] != sha:
    raise SystemExit('License registry belongs to a different runtime')
with tarfile.open(archive) as tar:
    members = tar.getmembers()
    names = [m.name for m in members]
    if len(set(names)) != len(names):
        raise SystemExit('Duplicate archive member')
    for member in members:
        name = PurePosixPath(member.name)
        if name.is_absolute() or '..' in name.parts or not (member.isdir() or member.isfile()):
            raise SystemExit('Unsafe or non-FAT archive entry: '+member.name)
    total = sum(m.size for m in members if m.isfile())
    if total != project['unpacked_bytes']:
        raise SystemExit('Unpacked size differs from catalog')
    manifest_bytes = tar.extractfile('BUNDLE-MANIFEST.json').read()
    if hashlib.sha256(manifest_bytes).hexdigest() != project['manifest_sha256']:
        raise SystemExit('Manifest digest differs from catalog')
    manifest = json.loads(manifest_bytes)
    if project['version'] != '2.2-beta8-port.'+manifest['port_version']:
        raise SystemExit('Port version differs from catalog version')
    expected = set(manifest['files']) | {'BUNDLE-MANIFEST.json'}
    if expected != {m.name for m in members if m.isfile()}:
        raise SystemExit('Archive file set differs from manifest')
    for member in members:
        if not member.isfile() or member.name == 'BUNDLE-MANIFEST.json':
            continue
        data = tar.extractfile(member).read()
        spec = manifest['files'][member.name]
        if (hashlib.sha256(data).hexdigest() != spec['sha256']
                or len(data) != spec['size'] or oct(member.mode) != spec['mode']):
            raise SystemExit('Manifest entry mismatch: '+member.name)
        if member.name in licenses['files'] and data.decode('utf-8') != licenses['files'][member.name]:
            raise SystemExit('Bundled notice mismatch: '+member.name)
    for name in [manifest['entrypoint'], manifest['bootstrap']]:
        if name not in manifest['files']:
            raise SystemExit('Missing standalone launcher/bootstrap')
if args.apk:
    with zipfile.ZipFile(args.apk) as apk:
        for relative in ['assets/runtime/pilot.tar.gz', 'assets/catalog.json',
                         'assets/legal/runtime-licenses.json', 'assets/legal/platform-licenses.json',
                         'assets/branding/bandaged-mount.png']:
            if apk.read('assets/flutter_assets/'+relative) != (root/relative).read_bytes():
                raise SystemExit('APK contains stale asset: '+relative)
print(json.dumps({'result': 'passed', 'runtime_sha256': sha,
    'port_version': manifest['port_version'], 'project_version': project['version'],
    'manifest_files': len(manifest['files']), 'license_files': len(licenses['files']),
    'apk_assets_checked': args.apk is not None}, indent=2))
