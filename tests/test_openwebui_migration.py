import os,pathlib,shutil,subprocess,tempfile,unittest,json
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Migration(unittest.TestCase):
 def test_runtime_process_preflight_precedes_any_deletion(self):
  script=(ROOT/'migrate-openwebui.sh').read_text()
  self.assertLess(script.index('remove-omp-runtime.py" --check'),script.index('remove-legacy-ai.sh" --apply'))
  self.assertLess(script.index('remove-omp-runtime.py" --check'),script.index('remove-old-omp-skills.py" --check'))
 def state(self,home,protected=False):
  data=home/'data';base=data/'pc-setup-openwebui';base.mkdir(parents=True)
  archive=data/'strata/models/wiki.zim' if protected is True else home/'wiki.zim'
  (base/'reference.json').write_text(json.dumps({'archive':str(archive),'sha256':'0'*64}))
  model=data/'pc-setup-colibri';model.mkdir();(model/'managed-models.json').write_text(json.dumps({'owner':'ubuntu-PC-setup','roots':{'text':str(home/'colibri-models/text')}}))
  if protected=='legacy_leftover':
   leftover=data/'strata/install';leftover.mkdir(parents=True);(leftover/'keep').write_text('runtime')
  if protected=='model_link':
   modeldir=home/'colibri-models/text/source';modeldir.mkdir(parents=True);(modeldir/'weights.gguf').symlink_to(data/'strata/models/weights.gguf')
  return data
 def fixture(self,code,answer,legacy=0,protected=False):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);src=p/'src';src.mkdir();shutil.copy(ROOT/'migrate-openwebui.sh',src);shutil.copy(ROOT/'finish-openwebui.sh',src);shutil.copy(ROOT/'remove-omp-runtime.py',src);shutil.copy(ROOT/'remove-old-omp-skills.py',src);(src/'remove-old-omp-skills.py').write_text((src/'remove-old-omp-skills.py').read_text().replace('remove(home, protected, roots=roots, process_guard=',"remove(home, protected, confirm=lambda _: 'DELETE OLD OMP SKILLS', roots=roots, process_guard="));(src/'remove-legacy-ai.sh').write_text('#!/bin/sh\nexit '+str(legacy)+'\n')
   (src/'openwebui_skills.py').write_text('import sys; assert \"--reference-manifest\" in sys.argv; raise SystemExit('+str(code)+')')
   home=p/'home';data=self.state(home,protected);target=home/'.local/bin/omp';target.parent.mkdir(parents=True);target.write_text('executable')
   custom=home/'.omp/skills/custom';custom.mkdir(parents=True);(custom/'SKILL.md').write_text('keep')
   bin=p/'bin';bin.mkdir();pgrep=bin/'pgrep';pgrep.write_text('#!/bin/sh\nexit 1\n');pgrep.chmod(0o755)
   r=subprocess.run(['bash',str(src/'migrate-openwebui.sh'),'--cleanup-only'],env=os.environ|{'HOME':str(home),'XDG_DATA_HOME':str(data),'PATH':str(bin)+':'+os.environ['PATH']},input=answer,text=True,capture_output=True)
   return r.returncode,target.exists(),(custom/'SKILL.md').read_text() if (custom/'SKILL.md').exists() else 'removed'
 def test_cleanup_precedes_replacement_verification(self):self.assertEqual(self.fixture(1,'REMOVE OMP\nDELETE OLD OMP SKILLS\n'),(0,False,'removed'))
 def test_decline_preserves_binary(self):self.assertEqual(self.fixture(0,'no\n'),(1,True,'keep'))
 def test_verified_explicit_removal_preserves_skills(self):self.assertEqual(self.fixture(0,'REMOVE OMP\nDELETE OLD OMP SKILLS\n'),(0,False,'removed'))
 def test_declined_legacy_cleanup_preserves_omp(self):self.assertEqual(self.fixture(0,'REMOVE OMP\n',legacy=1),(1,True,'keep'))
 def test_active_corpus_in_legacy_tree_blocks_cleanup(self):self.assertEqual(self.fixture(0,'REMOVE OMP\n',protected=True),(1,True,'keep'))
 def test_active_linked_model_in_legacy_tree_blocks_cleanup(self):self.assertEqual(self.fixture(0,'REMOVE OMP\n',protected='model_link'),(1,True,'keep'))
 def test_remaining_legacy_directory_prevents_omp_removal(self):self.assertEqual(self.fixture(0,'REMOVE OMP\n',protected='legacy_leftover'),(1,True,'keep'))
 def test_changed_executable_after_prompt_is_retained(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);src=p/'src';src.mkdir();shutil.copy(ROOT/'migrate-openwebui.sh',src);shutil.copy(ROOT/'finish-openwebui.sh',src);shutil.copy(ROOT/'remove-omp-runtime.py',src);shutil.copy(ROOT/'remove-old-omp-skills.py',src);(src/'remove-old-omp-skills.py').write_text((src/'remove-old-omp-skills.py').read_text().replace('remove(home, protected, roots=roots, process_guard=',"remove(home, protected, confirm=lambda _: 'DELETE OLD OMP SKILLS', roots=roots, process_guard="));(src/'remove-legacy-ai.sh').write_text('#!/bin/sh\nexit 0\n')
   (src/'openwebui_skills.py').write_text('raise SystemExit(0)')
   data=self.state(p/'home');target=p/'home/.local/bin/omp';target.parent.mkdir(parents=True);target.write_text('old')
   bindir=p/'bin';bindir.mkdir();pgrep=bindir/'pgrep';pgrep.write_text('#!/bin/sh\nexit 1\n');pgrep.chmod(0o755)
   proc=subprocess.Popen(['bash',str(src/'migrate-openwebui.sh'),'--cleanup-only'],env=os.environ|{'HOME':str(p/'home'),'XDG_DATA_HOME':str(data),'PATH':str(bindir)+':'+os.environ['PATH']},stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
   line=proc.stdout.readline()
   while line and 'OMP runtime inventory:' not in line:line=proc.stdout.readline()
   self.assertIn('OMP runtime inventory:',line)
   target.write_text('replacement')
   out,err=proc.communicate('REMOVE OMP\n',timeout=5)
   self.assertNotEqual(proc.returncode,0);self.assertEqual(target.read_text(),'replacement')
if __name__=='__main__':unittest.main()
