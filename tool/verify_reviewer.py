"""Use the private Keychain reviewer credential for real Dart app verification."""
import json,os,socket,subprocess,tempfile
from pathlib import Path
from secure_keychain import get_password
root=Path(__file__).resolve().parents[1]
setup=json.loads((root/'docs/reviewer_setup.json').read_text())
if setup.get('status')!='passed':raise SystemExit('Complete the reviewer setup first; no verification attempted.')
login=setup['reviewer_login'];password=get_password('2S Sales Hub Odoo Reviewer',login)
if not password:raise SystemExit('Reviewer password not found in local Keychain.')
with tempfile.TemporaryDirectory(prefix='2s-reviewer-input-') as folder:
 os.chmod(folder,0o700);path=str(Path(folder)/'input.sock')
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as server:
  server.bind(path);os.chmod(path,0o600);server.listen(1);server.settimeout(180)
  env=dict(os.environ,TWO_S_CREDENTIAL_SOCKET=path)
  child=subprocess.Popen(['flutter','test','tool/reviewer_live_check.dart'],cwd=root,env=env)
  try:
   conn,_=server.accept()
   with conn:conn.sendall(json.dumps({'login':login,'password':password}).encode())
   login=password=None;code=child.wait(timeout=390)
  except Exception:
   child.terminate();child.wait();code=1;print('Verification interrupted; no raw details or credentials logged.')
raise SystemExit(code)
