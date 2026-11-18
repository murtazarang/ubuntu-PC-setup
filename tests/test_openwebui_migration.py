import os,pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Migration(unittest.TestCase):
 def fixture(self,code,answer):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);src=p/'src';src.mkdir();shutil.copy(ROOT/'migrate-openwebui.sh',src)
   (src/'openwebui_skills.py').write_text('import sys; assert \"--reference-manifest\" in sys.argv; raise SystemExit('+str(code)+')')
   home=p/'home';target=home/'.local/bin/omp';target.parent.mkdir(parents=True);target.write_text('executable')
   custom=home/'.omp/skills/custom';custom.mkdir(parents=True);(custom/'SKILL.md').write_text('keep')
   bin=p/'bin';bin.mkdir();pgrep=bin/'pgrep';pgrep.write_text('#!/bin/sh\nexit 1\n');pgrep.chmod(0o755)
   r=subprocess.run(['bash',str(src/'migrate-openwebui.sh')],env=os.environ|{'HOME':str(home),'PATH':str(bin)+':'+os.environ['PATH']},input=answer,text=True,capture_output=True)
   return r.returncode,target.exists(),(custom/'SKILL.md').read_text()
 def test_failed_verification_preserves_binary(self):self.assertEqual(self.fixture(1,'REMOVE OMP\n'),(1,True,'keep'))
 def test_decline_preserves_binary(self):self.assertEqual(self.fixture(0,'no\n'),(0,True,'keep'))
 def test_verified_explicit_removal_preserves_skills(self):self.assertEqual(self.fixture(0,'REMOVE OMP\n'),(0,False,'keep'))
 def test_changed_executable_after_prompt_is_retained(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);src=p/'src';src.mkdir();shutil.copy(ROOT/'migrate-openwebui.sh',src)
   (src/'openwebui_skills.py').write_text('raise SystemExit(0)')
   target=p/'home/.local/bin/omp';target.parent.mkdir(parents=True);target.write_text('old')
   bindir=p/'bin';bindir.mkdir();pgrep=bindir/'pgrep';pgrep.write_text('#!/bin/sh\nexit 1\n');pgrep.chmod(0o755)
   proc=subprocess.Popen(['bash',str(src/'migrate-openwebui.sh')],env=os.environ|{'HOME':str(p/'home'),'PATH':str(bindir)+':'+os.environ['PATH']},stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
   self.assertIn('Verified migration',proc.stdout.readline())
   target.write_text('replacement')
   out,err=proc.communicate('REMOVE OMP\n',timeout=5)
   self.assertNotEqual(proc.returncode,0);self.assertEqual(target.read_text(),'replacement')
if __name__=='__main__':unittest.main()
