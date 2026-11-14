"""Exercise the app script's package-choice flow without installing anything."""
import os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class AppsTests(unittest.TestCase):
 def test_stremio_flatpak_fallback_and_no_real_privilege(self):
  with tempfile.TemporaryDirectory() as td:
   t=pathlib.Path(td); b=t/'bin'; b.mkdir(); log=t/'log'; home=t/'home'; home.mkdir()
   def stub(name,text):
    p=b/name;p.write_text('#!/bin/sh\n'+text+'\n');p.chmod(0o755)
   stub('sudo','echo "sudo $*" >> "$LOG"; case "$*" in *"apt-get -s install"*) exit 1;; esac; exit 0')
   stub('snap','echo "snap $*" >> "$LOG"; exit 1')
   stub('flatpak','echo "flatpak $*" >> "$LOG"; exit 0')
   stub('uv','exit 0');stub('omp','exit 0')
   stub('dpkg-query','exit 1')
   stub('curl',r'''case "$*" in *api.github.com/repos/storytold/artcraft/releases/latest*) echo '{"assets":[{"name":"artcraft-1-linux-x86_64.deb","browser_download_url":"https://example.invalid/art.deb"}]}' ;; *) while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then shift; : > "$1"; break; fi; shift; done ;; esac; exit 0''')
   release=t/'os-release';release.write_text('ID=ubuntu\nVERSION_ID=26.04\n')
   script=t/'script.sh';script.write_text((ROOT/'install-apps.sh').read_text().replace('. /etc/os-release','. "$TEST_OS_RELEASE"'))
   env=os.environ|{'HOME':str(home),'PATH':str(b)+os.pathsep+os.environ['PATH'],'LOG':str(log),'TEST_OS_RELEASE':str(release)}
   r=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True,timeout=15)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   recorded=log.read_text();self.assertIn('flatpak install --user -y flathub com.stremio.Stremio',recorded)
   self.assertIn('apt-get -s install',recorded); self.assertIn('/paseo.deb',recorded); self.assertIn('/artcraft.deb',recorded)
if __name__=='__main__': unittest.main()
