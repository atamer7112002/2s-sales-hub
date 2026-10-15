"""One-shot local credential broker. No password in files, environment, logs or argv."""
import getpass,json,os,socket,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
login=getpass.getpass('Odoo login (hidden): ')
password=getpass.getpass('Local Odoo password (hidden): ')
with tempfile.TemporaryDirectory(prefix='2s-credential-') as folder:
 os.chmod(folder,0o700)
 path=str(Path(folder)/'input.sock')
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as broker:
  broker.bind(path);os.chmod(path,0o600);broker.listen(1);broker.settimeout(300)
  env=dict(os.environ,TWO_S_CREDENTIAL_SOCKET=path)
  child=subprocess.Popen(['flutter','test','tool/live_offline_check.dart'],cwd=root,env=env)
  try:
   conn,_=broker.accept()
   with conn:conn.sendall(json.dumps({'login':login,'password':password}).encode())
   login=password=None
   code=child.wait(timeout=330)
  except Exception:
   child.terminate();child.wait();code=1
   print('Local verification interrupted; no raw details logged.')
print('Verification finished. Sanitized results: docs/offline_live_verification.json')
input('Press Return to close.')
raise SystemExit(code)
