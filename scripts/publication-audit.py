#!/usr/bin/env python3
"""Read-only heuristic audit of reachable Git blobs and non-ignored working files.

Usage: python3 scripts/publication-audit.py REPOSITORY [REPOSITORY ...]
Reports paths, rule names and line numbers only, never matching secret values.
Detailed reports go to /tmp/<repository-name>-publication-scan.json.
Not a guarantee of absence of secrets; generated/ignored files need separate review.
"""
import subprocess,re,json,sys
from pathlib import Path
patterns={
 'private_key':rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
 'github_token':rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b',
 'cloud_access_key':rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
 'google_api_key':rb'\bAIza[0-9A-Za-z_-]{30,}\b',
 'credential_url':rb'https?://[^\s/@:]+:[^\s/@]+@',
 'literal_credential':rb'''(?i)(?:password|passwd|client_secret|api_key|access_token|refresh_token)\s*[:=]\s*["'][^"'\r\n]{4,}["']''',
 'local_details':rb'(?i)(?:192\.168\.[0-9]+\.[0-9]+|/home/[A-Za-z0-9_-]+|polaris_[0-9a-f]{6}|site_latitude|site_longitude|zerotier)',
}
for directory in sys.argv[1:]:
 root=Path(directory)
 def git(*args): return subprocess.check_output(['git',*args],cwd=root)
 objects=git('rev-list','--objects','--all').decode().splitlines()
 hits={};blobs=0;large=[];suspect_paths=[]
 proc=subprocess.Popen(['git','cat-file','--batch'],cwd=root,stdin=subprocess.PIPE,stdout=subprocess.PIPE)
 for row in objects:
  oid,_,path=row.partition(' ')
  proc.stdin.write((oid+'\n').encode());proc.stdin.flush()
  header=proc.stdout.readline().decode().split();size=int(header[2]);data=proc.stdout.read(size);proc.stdout.read(1)
  if header[1]!='blob':continue
  blobs+=1
  if size>1024*1024:large.append({'path':path,'bytes':size})
  if re.search(r'(^|/)(?:id_rsa|id_ed25519|\.env(?:\..*)?|key.properties)$|\.(?:qcow2|img|pem|jks|keystore|tar|tar.gz|whl)$',path):suspect_paths.append(path)
  if b'\0' in data[:8192]:continue
  for rule,pattern in patterns.items():
   found=list(re.finditer(pattern,data))
   if found:
    item=hits.setdefault((path,rule),{'path':path,'rule':rule,'historical_versions':0,'lines':set()})
    item['historical_versions']+=1
    item['lines'].update(data[:m.start()].count(b'\n')+1 for m in found)
 proc.stdin.close();proc.wait()
 current=[]
 for raw in git('ls-files','-z','--cached','--others','--exclude-standard').split(b'\0'):
  if not raw:continue
  path=raw.decode();p=root/path
  if not p.is_file():continue
  data=p.read_bytes()
  if b'\0' in data[:8192]:continue
  for rule,pattern in patterns.items():
   ms=list(re.finditer(pattern,data))
   if ms:current.append({'path':path,'rule':rule,'lines':sorted(set(data[:m.start()].count(b'\n')+1 for m in ms))})
 result={'repo':root.name,'commits':len(git('rev-list','--all').splitlines()),'reachable_blobs':blobs,'historical_matches':[dict(v,lines=sorted(v['lines'])) for v in hits.values()],'current_matches':current,'large_historical_blobs':large,'suspect_historical_paths':sorted(set(suspect_paths))}
 Path('/tmp/'+root.name+'-publication-scan.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:v for k,v in result.items() if k not in ['historical_matches','current_matches']}))
 print('Current candidates (no values):',json.dumps([r for r in current if r['rule']!='local_details']))
 print('Historical high-confidence candidates:',json.dumps([r for r in result['historical_matches'] if r['rule'] not in ['local_details','literal_credential']]))
 print('Local-detail files:',len([r for r in current if r['rule']=='local_details']))
