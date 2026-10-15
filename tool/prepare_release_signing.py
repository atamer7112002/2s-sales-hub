"""Generate a private assessment signing key outside the project. Never prints secrets."""
from pathlib import Path
import os,secrets,subprocess,shutil
project=Path(__file__).resolve().parents[1]
root=Path.home()/'.local/share/2s-sales-hub/signing'
root.mkdir(parents=True,exist_ok=True,mode=0o700)
os.chmod(root,0o700)
password_file=root/'password'
if not password_file.exists():
 password_file.write_text(secrets.token_urlsafe(32)+'\n');os.chmod(password_file,0o600)
keystore=root/'assessment-release.jks'
if not keystore.exists():
 candidates=[Path(os.environ.get('JAVA_HOME','/nonexistent'))/'bin/keytool',Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool')]
 keytool=next((str(p) for p in candidates if p.is_file()),None) or shutil.which('keytool')
 if not keytool: raise SystemExit('Install a JDK and put keytool on PATH or configure JAVA_HOME.')
 subprocess.run([keytool,'-genkeypair','-keystore',str(keystore),'-alias','sales-hub','-keyalg','RSA','-keysize','3072','-validity','3650','-storetype','JKS','-storepass:file',str(password_file),'-keypass:file',str(password_file),'-dname','CN=2S Sales Hub Assessment'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 os.chmod(keystore,0o600)
password=password_file.read_text().strip()
properties=project/'android/key.properties'
properties.write_text(f'storeFile={keystore}\nstorePassword={password}\nkeyPassword={password}\nkeyAlias=sales-hub\n')
os.chmod(properties,0o600)
print('Assessment release signing configured. Key and passwords remain private, outside source control.')
