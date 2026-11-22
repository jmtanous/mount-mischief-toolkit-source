#!/usr/bin/env python3
"""Collect cached Android artifact notices and full Flutter engine notices.

Supply the resolved Gradle runtime dependency report for the candidate variant.
No dependency code is executed. POM declarations are retained, not relicensed.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--graph', type=Path, required=True)
parser.add_argument('--gradle-cache', type=Path, required=True)
parser.add_argument('--flutter-sdk', type=Path, required=True)
args = parser.parse_args()
coordinates = set()
for line in args.graph.read_text().splitlines():
    match = re.search(r'(?:\+---|\\---) ([\w.-]+):([\w.-]+):([^\s]+)(?: -> ([^\s]+))?', line)
    if match:
        group, artifact, version, resolved = match.groups()
        coordinates.add((group, artifact, resolved or version))
if not coordinates:
    raise SystemExit('Empty dependency graph')
files = {}
artifacts = {}
declarations = {}

def collect(archive, label):
    with zipfile.ZipFile(archive) as bundle:
        for name in bundle.namelist():
            if name.endswith('/'):
                continue
            if re.search(r'(^|/)(license|notice|copying|third_party_licenses)', name, re.I):
                # Preserve the vendor's complete text, including copyrights.
                if not name.endswith('.json'):
                    files[label+'/'+name] = bundle.read(name).decode('utf-8')
            elif name.endswith('.jar'):
                collect(io.BytesIO(bundle.read(name)), label+'/'+name)

for group, artifact, version in sorted(coordinates):
    coordinate = f'{group}:{artifact}:{version}'
    folder = args.gradle_cache/group/artifact/version
    declarations[coordinate] = []
    for pom in folder.glob('**/*.pom'):
        xml = ET.fromstring(pom.read_bytes())
        declarations[coordinate] += [
            {child.tag.split('}')[-1]: child.text for child in item}
            for item in xml.findall('{*}licenses/{*}license')
        ]
    for path in sorted(list(folder.glob('**/*.aar'))+list(folder.glob('**/*.jar'))):
        label = coordinate+'/'+path.name
        artifacts[label] = hashlib.sha256(path.read_bytes()).hexdigest()
        collect(path, label)

apache = next((text for text in files.values()
               if 'Apache License' in text and 'END OF TERMS AND CONDITIONS' in text
               and 10000 < len(text) < 13000), None)
if not apache:
    raise SystemExit('No complete Apache license found in dependency notices')
files['Android Apache-2.0 license'] = apache
files['Android dependency license declarations'] = (
    'The following declarations come from the resolved dependency POMs. '
    'Google Play services retains its SDK terms; it is not relicensed by MMT. '
    'Its embedded third-party notices are included separately. '
    'Flutter engine notices and licenses are included in full below. '
    'Guava listenablefuture 1.0 is covered by the Guava Apache-2.0 notices.\n\n'
    +json.dumps(declarations, indent=2)+'\n')
for relative in ['LICENSE', 'bin/cache/pkg/sky_engine/LICENSE']:
    files['Flutter SDK/'+relative] = (args.flutter_sdk/relative).read_text()
output = {'scope': 'Conservative Android runtime graph plus complete Flutter SDK/engine notices',
          'artifact_sha256': artifacts, 'files': dict(sorted(files.items()))}
(root/'assets/legal/platform-licenses.json').write_text(json.dumps(output, indent=2, ensure_ascii=False)+'\n')
print(json.dumps({'coordinates': len(coordinates), 'artifacts': len(artifacts), 'notices': len(files)}))
