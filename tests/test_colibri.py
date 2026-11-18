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
   model_setup=src/'configure-colibri-model.sh';model_setup.write_text('#!/bin/sh\nexit 0\n');model_setup.chmod(0o755)
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

class DesktopShortcutTests(unittest.TestCase):
 def test_native_cli_dual_and_preserves_foreign_entry(self):
  import importlib.util, unittest.mock
  spec=importlib.util.spec_from_file_location('shortcuts',ROOT/'create-colibri-shortcuts.py')
  m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  with tempfile.TemporaryDirectory() as td:
   home=pathlib.Path(td)
   with unittest.mock.patch.dict(os.environ,{'XDG_DATA_HOME':str(home/'data')}), unittest.mock.patch.object(m.subprocess,'run',side_effect=FileNotFoundError):
    m.install('/some path/coli','/models/model 27B','/icons/serve.svg',True,home)
    desktop=home/'Desktop/Colibri Serve.desktop'; text=desktop.read_text()
    self.assertIn('COLI_VK_DEV2=auto',text); self.assertIn("'serve'",text); self.assertIn('/models/model 27B',text); self.assertIn("'ui'",text)
    self.assertIn('Terminal=true',text);self.assertNotIn('sh -c',text)
    desktop.write_text('user customization')
    with self.assertRaises(SystemExit): m.install('/coli','/model','/icon',False,home)
    self.assertEqual(desktop.read_text(),'user customization')

class ModelSetupTests(unittest.TestCase):
 def test_native_import_text_shortcut_and_customization_guard(self):
  import shutil
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);src=p/'src';src.mkdir();home=p/'home';home.mkdir();release=p/'release';release.mkdir()
   for name in ('configure-colibri-model.sh','create-colibri-shortcuts.py'):
    shutil.copy(ROOT/name,src/name)
   (src/'assets/colibri').mkdir(parents=True)
   (src/'assets/colibri/colibri-serve.svg').write_text('<svg/>')
   (src/'assets/colibri/colibri-serve-image.svg').write_text('<svg/>')
   venv=home/'data/pc-setup-colibri/image-python/bin';venv.mkdir(parents=True);(venv/'python').write_text('#!/bin/sh\nexit 0\n');(venv/'python').chmod(0o755)
   bin=p/'bin';bin.mkdir();uv=bin/'uv';uv.write_text('#!/bin/sh\nexit 0\n');uv.chmod(0o755)
   (src/'colibri-models.json').write_text(json.dumps({'dense27b':{'format':'gguf','first_shard':'weights.gguf'}}))
   (src/'download_colibri_model.py').write_text("import pathlib,sys;p=pathlib.Path(sys.argv[sys.argv.index('--destination')+1]);p.mkdir(parents=True,exist_ok=True);(p/'weights.gguf').write_text('fixture')")
   (release/'coli').write_text("import pathlib,sys,json;assert sys.argv[1]=='import';assert '--no-mtp' in sys.argv;assert sys.argv[-2:] == ['link','--no-mtp'];p=pathlib.Path(sys.argv[sys.argv.index('--out')+1]);[(p/f).write_text('{}') for f in ('config.json','tokenizer.json','gguf.json')]")
   env=os.environ|{'HOME':str(home),'XDG_DATA_HOME':str(home/'data'),'PATH':str(bin)+':'+os.environ['PATH']}
   command=['bash',str(src/'configure-colibri-model.sh'),str(release),'NvidiaSingle']
   for _ in range(2):
    r=subprocess.run(command,env=env,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   model=home/'colibri-models/dense27b/model';(model/'config.json').write_text('custom')
   r=subprocess.run(command,env=env,capture_output=True,text=True);self.assertNotEqual(r.returncode,0);self.assertEqual((model/'config.json').read_text(),'custom')

class ImageShortcutTests(unittest.TestCase):
 def test_image_has_distinct_port_and_no_dual_expert_flag(self):
  import importlib.util, unittest.mock
  spec=importlib.util.spec_from_file_location('shortcuts',ROOT/'create-colibri-shortcuts.py')
  m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  with tempfile.TemporaryDirectory() as td:
   home=pathlib.Path(td)
   with unittest.mock.patch.dict(os.environ,{'XDG_DATA_HOME':str(home/'data')}), unittest.mock.patch.object(m.subprocess,'run',side_effect=FileNotFoundError):
    m.install('/coli','/image','/image.svg',True,home,image=True)
    text=(home/'Desktop/Colibri Serve Image.desktop').read_text()
    self.assertIn('\"8001\"',text);self.assertIn('\"web\"',text);self.assertNotIn('COLI_VK_DEV2=auto',text)
    self.assertIn('-u COLI_VK_DEV2',text)

class NativeUILaunchTests(unittest.TestCase):
 def test_inline_starts_native_serve_then_ui(self):
  import ast,sys,socket
  tree=ast.parse((ROOT/'create-colibri-shortcuts.py').read_text())
  startup=next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='startup' for t in n.targets))
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);cli=p/'coli';calls=p/'calls'
   cli.write_text("import sys,time,json,pathlib\np=pathlib.Path("+repr(str(calls))+");f=p.open('a');f.write(json.dumps(sys.argv[1:])+'\\n');f.close();time.sleep(2 if sys.argv[1]=='serve' else 0.1)")
   sockets=[]
   for _ in range(2):
    s=socket.socket();s.bind(('127.0.0.1',0));sockets.append(s)
   ports=[str(s.getsockname()[1]) for s in sockets]
   for s in sockets:s.close()
   r=subprocess.run([sys.executable,'-c',startup,sys.executable,str(cli),str(p/'model'),*ports],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stderr)
   commands=[json.loads(x) for x in calls.read_text().splitlines()]
   self.assertEqual([c[0] for c in commands],['serve','ui']);self.assertIn('http://127.0.0.1:'+ports[0],commands[1])
