import os,pathlib,shutil,subprocess,tempfile,unittest,json
ROOT=pathlib.Path(__file__).resolve().parents[1]
class EntryTests(unittest.TestCase):
 def test_existing_entry_runs_only_ai_stages_in_order(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);src=p/'src';src.mkdir();home=p/'home';home.mkdir();bin=p/'bin';bin.mkdir();log=p/'calls'
   shutil.copy(ROOT/'migrate-existing-ai.sh',src)
   for name in ['uv','lspci','systemctl']:
    f=bin/name;f.write_text('#!/bin/sh\nexit 0\n');f.chmod(0o755)
   for name in ['configure-skills.sh','download-wikipedia.sh','configure-ai.sh','migrate-openwebui.sh']:
    (src/name).write_text('#!/bin/sh\nprintf "%s\\n" "'+name+' $*" >> "$CALLS"\n')
   for name in ['remove-omp-runtime.py','remove-legacy-ai.sh','remove-old-omp-skills.py']:(src/name).write_text('fixture')
   (src/'configure-openwebui.sh').write_text('''#!/bin/sh
printf '%s\n' configure-openwebui.sh >> "$CALLS"
base="$XDG_DATA_HOME/pc-setup-openwebui"
mkdir -p "$base"
printf '#!/bin/sh\nprintf "launch\\n" >> "$CALLS"\n' > "$base/launch-webui.sh"
printf '#!/bin/sh\nprintf "finish\\n" >> "$CALLS"\n' > "$base/finish-openwebui.sh"
''')
   env=os.environ|{'HOME':str(home),'XDG_DATA_HOME':str(home/'data'),'PATH':str(bin)+':'+os.environ['PATH'],'CALLS':str(log)}
   result=subprocess.run(['bash',str(src/'migrate-existing-ai.sh'),'Intel'],env=env,input='\n',capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertEqual([s.strip() for s in log.read_text().splitlines()],['migrate-openwebui.sh --cleanup-only','configure-skills.sh','download-wikipedia.sh','configure-ai.sh Intel','configure-openwebui.sh','launch','finish'])
 def test_only_known_prior_migration_helper_is_upgraded(self):
  block=(ROOT/'migrate-existing-ai.sh').read_text().split("<<'PYMIGRATE'\n",1)[1].split('\nPYMIGRATE',1)[0]
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);src=p/'src';src.mkdir();dest=p/'dest';dest.mkdir()
   for name in ('migrate-openwebui.sh','remove-omp-runtime.py','remove-legacy-ai.sh','remove-old-omp-skills.py'):(src/name).write_text('new '+name)
   old=ROOT/'tests/fixtures/migrate-openwebui-7efa03d.sh';shutil.copyfile(old,dest/'migrate-openwebui.sh')
   r=subprocess.run(['python3','-c',block,str(src),str(dest)],capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertEqual((dest/'migrate-openwebui.sh').read_text(),'new migrate-openwebui.sh')
   (dest/'migrate-openwebui.sh').write_text('custom user edit')
   r=subprocess.run(['python3','-c',block,str(src),str(dest)],capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0);self.assertEqual((dest/'migrate-openwebui.sh').read_text(),'custom user edit')
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
  fresh=(ROOT/'configure-openwebui.sh').read_text()+(ROOT/'configure-skills.sh').read_text()+(ROOT/'finish-openwebui.sh').read_text()
  for old in ['remove-legacy-ai.sh','remove-omp-runtime.py','migrate-openwebui.sh','DELETE LEGACY AI','REMOVE OMP']:
   self.assertNotIn(old,fresh)
  self.assertIn('finish-openwebui.sh',fresh)
 def test_finish_only_calls_shared_import(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);shutil.copy(ROOT/'finish-openwebui.sh',p)
   (p/'openwebui_skills.py').write_text('import sys;assert sys.argv[1]=="import";assert "--reference-manifest" in sys.argv')
   r=subprocess.run(['bash',str(p/'finish-openwebui.sh')],env=os.environ|{'HOME':t},capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
