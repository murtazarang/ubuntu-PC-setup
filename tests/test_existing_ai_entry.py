import os,pathlib,shutil,subprocess,tempfile,unittest,json
ROOT=pathlib.Path(__file__).resolve().parents[1]
class EntryTests(unittest.TestCase):
 def test_existing_entry_runs_only_ai_stages_in_order(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);src=p/'src';src.mkdir();home=p/'home';home.mkdir();bin=p/'bin';bin.mkdir();log=p/'calls'
   shutil.copy(ROOT/'migrate-existing-ai.sh',src)
   (bin/'uv').write_text('#!/bin/sh\nexit 99\n'); (bin/'uv').chmod(0o755)
   for name in ['migrate-openwebui.sh','install-hermes-local-ai.sh']:
    (src/name).write_text('#!/bin/sh\nprintf "%s\\n" "'+name+' $*" >> "$CALLS"\n')
   (src/'retire-legacy-text.py').write_text('import os;open(os.environ["CALLS"],"a").write("retire-legacy-text\\n")')
   env=os.environ|{'HOME':str(home),'XDG_DATA_HOME':str(home/'data'),'PATH':str(bin)+':'+os.environ['PATH'],'CALLS':str(log)}
   result=subprocess.run(['bash',str(src/'migrate-existing-ai.sh'),'Intel'],env=env,input='\n',capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertEqual([s.strip() for s in log.read_text().splitlines()],['migrate-openwebui.sh --cleanup-only','install-hermes-local-ai.sh Intel','retire-legacy-text'])
   (src/'install-hermes-local-ai.sh').write_text('exit 7\n')
   log.write_text('')
   result=subprocess.run(['bash',str(src/'migrate-existing-ai.sh'),'Intel'],env=env,input='\n',capture_output=True,text=True)
   self.assertEqual(result.returncode,7,result.stderr)
   self.assertEqual(log.read_text().splitlines(),['migrate-openwebui.sh --cleanup-only'])
 def test_existing_custom_corpus_location_is_reused_and_conflict_refused(self):
  block=(ROOT/'migrate-existing-ai.sh').read_text().split("<<'PYARCHIVE'\n",1)[1].split('\nPYARCHIVE',1)[0]
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);archive=p/'external drive/wikipedia_en_all_nopic_2026-06.zim';manifest=p/'reference.json';manifest.write_text(json.dumps({'archive':str(archive)}))
   env=os.environ.copy();env.pop('KIWIX_ARCHIVE_DIR',None)
   r=subprocess.run(['python3','-c',block,str(manifest)],env=env,capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(r.stdout.strip(),str(archive.parent))
   env['KIWIX_ARCHIVE_DIR']=str(p/'different')
   r=subprocess.run(['python3','-c',block,str(manifest)],env=env,capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0);self.assertIn('no download started',r.stderr)
 def test_fresh_stack_has_no_cleanup_callgraph(self):
  fresh=(ROOT/'setup.sh').read_text()+(ROOT/'install-hermes-local-ai.sh').read_text()
  for old in ['remove-legacy-ai.sh','remove-omp-runtime.py','migrate-openwebui.sh','DELETE LEGACY AI','REMOVE OMP']:
   self.assertNotIn(old,fresh)
  self.assertIn('install-hermes-local-ai.sh',fresh)
  self.assertNotIn('configure-openwebui.sh',fresh)
 def test_finish_only_calls_shared_import(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);shutil.copy(ROOT/'finish-openwebui.sh',p)
   (p/'openwebui_skills.py').write_text('import sys;assert sys.argv[1]=="import";assert "--reference-manifest" in sys.argv')
   r=subprocess.run(['bash',str(p/'finish-openwebui.sh')],env=os.environ|{'HOME':t},capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
