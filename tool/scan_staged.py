"""Scan staged snapshot; reports only filenames/categories, never matched values."""
import json,re,subprocess,sys
from pathlib import Path
repo=Path(sys.argv[1] if len(sys.argv)>1 else '.')
paths=subprocess.check_output(['git','ls-files','--cached','-z'],cwd=repo).decode().split('\0')
patterns={
 'private key':rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
 'GitHub token':rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',
 'AWS access key':rb'AKIA[0-9A-Z]{16}',
}
private_names={'key.properties','local.properties','.env','.git-credentials'}
findings=[];count=0
for name in filter(None,paths):
 count+=1;p=Path(name)
 if p.name in private_names or p.name.startswith('.env.') or p.suffix in {'.jks','.keystore','.db','.sqlite','.sqlite3','.dump','.pem','.p12','.key'}:
  findings.append({'file':name,'category':'private/generated file'})
 blob=subprocess.check_output(['git','show',':'+name],cwd=repo)
 for label,pattern in patterns.items():
  if re.search(pattern,blob):findings.append({'file':name,'category':label})
 # Check the actual local release-signing password without displaying it.
 source=Path(__file__).resolve().parents[1]/'android/key.properties'
 if source.exists():
  for line in source.read_text().splitlines():
   if line.startswith('storePassword='):
    secret=line.split('=',1)[1].encode()
    if secret and secret in blob:findings.append({'file':name,'category':'local signing password'})
print(json.dumps({'files_scanned':count,'passed':not findings,'findings':findings},indent=2))
raise SystemExit(1 if findings else 0)
