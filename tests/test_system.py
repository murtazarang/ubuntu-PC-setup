"""Simulate system stage with stubbed privileged tools and hardware."""
import os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class SystemTests(unittest.TestCase):
 def simulate(self,gpu):
  with tempfile.TemporaryDirectory() as td:
   t=pathlib.Path(td); b=t/'bin';b.mkdir();log=t/'log';home=t/'home';home.mkdir()
   def stub(name,text):
    p=b/name;p.write_text('#!/bin/sh\n'+text+'\n');p.chmod(0o755)
   stub('sudo','echo "sudo $*" >> "$LOG"; exit 0')
   stub('findmnt','echo btrfs')
   stub('lspci',f"echo '01:00.0 VGA compatible controller: {gpu}'")
   stub('ubuntu-drivers',"echo 'driver : nvidia-driver-580-open - distro non-free recommended'")
   release=t/'os-release';release.write_text('ID=ubuntu\nVERSION_ID=26.04\n')
   script=t/'install-system.sh';script.write_text((ROOT/'install-system.sh').read_text().replace('. /etc/os-release','. "$TEST_OS_RELEASE"'))
   (t/'configure-timeshift.sh').write_text('#!/bin/sh\necho timeshift >> "$LOG"\n');(t/'configure-timeshift.sh').chmod(0o755)
   env=os.environ|{'HOME':str(home),'PATH':str(b)+os.pathsep+os.environ['PATH'],'LOG':str(log),'TEST_OS_RELEASE':str(release)}
   r=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True,timeout=15)
   return r,log.read_text() if log.exists() else ''
 def test_nvidia_picks_closed_and_32bit(self):
  r,log=self.simulate('NVIDIA Corporation GeForce RTX');self.assertEqual(r.returncode,0,r.stderr)
  self.assertIn('nvidia-driver-580 libnvidia-gl-580:i386',log);self.assertNotIn('install -y nvidia-driver-580-open',log)
  self.assertLess(log.index('timeshift'),log.index('apt-get -y upgrade'))
 def test_intel_installs_mesa_media_without_nvidia(self):
  r,log=self.simulate('Intel Corporation Arc');self.assertEqual(r.returncode,0,r.stderr)
  self.assertIn('intel-media-va-driver vainfo',log); self.assertNotIn('install -y nvidia-driver-',log)
if __name__=='__main__':unittest.main()
