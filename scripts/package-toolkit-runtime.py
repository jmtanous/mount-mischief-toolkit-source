#!/usr/bin/env python3
"""Extract the manager's Python runtime from a verified existing runtime package.
No Pilot application, launcher, site-packages or project metadata is retained.
"""
import argparse,gzip,hashlib,io,json,tarfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
seed=json.loads((root/'assets/catalog.json').read_text())['projects'][0]
assert hashlib.sha256(a.source.read_bytes()).hexdigest()==seed['sha256'],'Source archive mismatch'
files={}
with tarfile.open(a.source) as src:
 for m in src:
  n=m.name
  if not m.isfile() or not n.startswith('opt/benro-python/'):continue
  if '/site-packages/' in n or '/share/pilot/' in n or n.endswith('/bin/pilot'):continue
  if '/share/build/' in n:continue
  data=src.extractfile(m).read();files[n]=(data,m.mode)
assert 'opt/benro-python/bin/python3.13' in files
assert not any('alpaca' in n.lower() or '/pilot/' in n.lower() for n in files)
a.output.parent.mkdir(parents=True,exist_ok=True)
with a.output.open('wb') as raw,gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0) as gz,tarfile.open(fileobj=gz,mode='w') as out:
 for name,(data,mode) in sorted(files.items()):
  m=tarfile.TarInfo(name);m.size=len(data);m.mode=mode;out.addfile(m,io.BytesIO(data))
manifest={k:seed[k] for k in ('schema','min_manager_schema','devices')}
manifest.update({'id':'toolkit-runtime','name':'Toolkit runtime','version':'1.0.0','adapter':'toolkit-runtime-v1','resources':[], 'sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),'archive_bytes':a.output.stat().st_size,'unpacked_bytes':sum(len(d) for d,_ in files.values()),'manifest_sha256':hashlib.sha256(json.dumps({n:hashlib.sha256(d).hexdigest() for n,(d,_) in sorted(files.items())}).encode()).hexdigest()})
(root/'assets/toolkit-runtime.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'archive':str(a.output),'files':len(files),'sha256':manifest['sha256']}))
