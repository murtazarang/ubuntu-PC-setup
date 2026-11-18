import os,pathlib,subprocess,tempfile,unittest,json
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ColibriTests(unittest.TestCase):
 def test_no_model_download_or_old_install(self):
  s=(ROOT/'configure-ai.sh').read_text()
  for bad in ['strata launch','--family','--setup','coli setup']: self.assertNotIn(bad,s)
  self.assertIn('SHA256SUMS.txt',s)
 def test_cleanup_preview_does_not_move_data(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td); (p/'.paseo').mkdir(); (p/'.paseo/keep').write_text('data')
   r=subprocess.run(['bash',str(ROOT/'remove-legacy-ai.sh')],env=os.environ|{'HOME':td},capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((p/'.paseo/keep').exists());self.assertIn('Preview only',r.stdout)
if __name__=='__main__': unittest.main()

class ColibriInstallTests(unittest.TestCase):
 def test_real_release_install_and_rerun(self):
  archive=pathlib.Path('/tmp/colibri-linux-release.tar.gz')
  if not archive.exists(): self.skipTest('Optional real release fixture not downloaded')
  import shutil,hashlib
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);src=p/'source';src.mkdir();home=p/'home';home.mkdir();bin=p/'bin';bin.mkdir()
   shutil.copy(ROOT/'configure-ai.sh',src/'configure-ai.sh')
   skills=src/'configure-skills.sh';skills.write_text('#!/bin/sh\nexit 0\n');skills.chmod(0o755)
   sums=p/'sums';sums.write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  colibri-v2.1.0-linux-x86_64.tar.gz\n')
   curl=bin/'curl';curl.write_text('#!/bin/bash\ncase "$4" in *SHA256SUMS*) cp "$SUMS" "$6";; *) cp "$ARCHIVE" "$6";; esac\n');curl.chmod(0o755)
   # Arguments are -fL --retry 3 URL -o PATH.
   env=os.environ|{'HOME':str(home),'XDG_DATA_HOME':str(home/'data'),'PATH':str(bin)+':'+os.environ['PATH'],'SUMS':str(sums),'ARCHIVE':str(archive)}
   for _ in range(2):
    r=subprocess.run(['bash',str(src/'configure-ai.sh')],env=env,capture_output=True,text=True)
    self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   cli=home/'.local/bin/coli';self.assertTrue(cli.is_symlink())
   r=subprocess.run([str(cli),'ui','--help'],env=env,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
