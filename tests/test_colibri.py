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

class DesktopGioTests(unittest.TestCase):
 def test_gio_launch_preserves_special_arguments(self):
  import importlib.util, shutil,sys,time
  if not shutil.which('gio'): self.skipTest('GIO is unavailable')
  spec=importlib.util.spec_from_file_location('shortcuts',ROOT/'create-colibri-shortcuts.py')
  m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);out=p/'args.json';desktop=p/'test.desktop'
   values=['a\\b $d `x` "quote" % percent',"exec('print(\\\"safe\\\")\\n')",'/a path/model']
   code='import json,sys;open('+repr(str(out))+',"w").write(json.dumps(sys.argv[1:]))'
   desktop.write_text('[Desktop Entry]\nType=Application\nName=Test\nTerminal=false\nExec='+ ' '.join(m.quote(x) for x in [sys.executable,'-c',code,*values])+'\n')
   r=subprocess.run(['gio','launch',str(desktop)],capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr)
   for _ in range(100):
    if out.exists():break
    time.sleep(.02)
   self.assertTrue(out.exists(),r.stderr);self.assertEqual(json.loads(out.read_text()),values)
 def test_generated_text_entry_executes_both_native_commands(self):
  import importlib.util,shutil,sys,time,unittest.mock,socket
  if not shutil.which('gio'): self.skipTest('GIO is unavailable')
  for port in (8000,8790):
   s=socket.socket()
   try:s.bind(('127.0.0.1',port))
   except OSError:self.skipTest('Fixture port occupied')
   finally:s.close()
  spec=importlib.util.spec_from_file_location('shortcuts',ROOT/'create-colibri-shortcuts.py')
  m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);cli=p/'coli $quoted';calls=p/'calls'
   cli.write_text("import json,pathlib,sys,time\np=pathlib.Path("+repr(str(calls))+");f=p.open('a');f.write(json.dumps(sys.argv[1:])+'\\n');f.close();time.sleep(2 if sys.argv[1]=='serve' else 0.1)")
   with unittest.mock.patch.dict(os.environ,{'XDG_DATA_HOME':str(p/'data')}),unittest.mock.patch.object(m.subprocess,'run',side_effect=FileNotFoundError):
    m.install(str(cli),str(p/'model $x'),'/icon.svg',False,p,python=sys.executable)
   desktop=p/'Desktop/Colibri Serve.desktop'
   desktop.write_text(desktop.read_text().replace('Terminal=true','Terminal=false'))
   r=subprocess.run(['gio','launch',str(desktop)],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stderr)
   for _ in range(200):
    if calls.exists() and len(calls.read_text().splitlines())==2:break
    time.sleep(.02)
   commands=[json.loads(x) for x in calls.read_text().splitlines()]
   self.assertEqual([c[0] for c in commands],['serve','ui']);self.assertIn(str(p/'model $x'),commands[0])

class DirectCleanupTests(unittest.TestCase):
 def run_cleanup(self,home,answer='DELETE LEGACY AI\n',systemctl=None):
  bin=home/'bin';bin.mkdir(exist_ok=True)
  if systemctl is not None:
   ctl=bin/'systemctl';ctl.write_text(systemctl);ctl.chmod(0o755)
  dpkg=bin/'dpkg-query';dpkg.write_text('#!/bin/sh\nexit 1\n');dpkg.chmod(0o755)
  return subprocess.run(['bash',str(ROOT/'remove-legacy-ai.sh'),'--apply'],input=answer,text=True,capture_output=True,env=os.environ|{'HOME':str(home),'XDG_DATA_HOME':str(home/'data'),'XDG_CONFIG_HOME':str(home/'config'),'PATH':str(bin)+':'+os.environ['PATH']})
 def test_direct_removal_preserves_chats_unrelated_and_no_quarantine(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);model=p/'data/strata/models';model.mkdir(parents=True);(model/'weight').write_text('model')
   chat=p/'data/strata/chats';chat.mkdir();(chat/'history').write_text('keep')
   (p/'.paseo').mkdir();(p/'.paseo/chat').write_text('keep')
   r=self.run_cleanup(p);self.assertEqual(r.returncode,0,r.stderr)
   self.assertFalse(model.exists());self.assertEqual((chat/'history').read_text(),'keep');self.assertTrue((p/'.paseo/chat').exists())
   self.assertFalse((p/'data/pc-setup-legacy-ai-backup').exists())
 def test_decline_keeps_model(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);model=p/'data/strata/models';model.mkdir(parents=True)
   r=self.run_cleanup(p,'no\n');self.assertNotEqual(r.returncode,0);self.assertTrue(model.exists())
 def test_symlinked_model_refused(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);outside=p/'unrelated';outside.mkdir();(outside/'keep').write_text('keep')
   (p/'data/strata').mkdir(parents=True);(p/'data/strata/models').symlink_to(outside,target_is_directory=True)
   r=self.run_cleanup(p);self.assertNotEqual(r.returncode,0);self.assertIn('symlinked',r.stderr);self.assertTrue((outside/'keep').exists())
 def test_upstream_launcher_symlink_unlinked_after_native_stop(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);terminal=p/'data/strata/terminal';bin=terminal/'v1/bin';bin.mkdir(parents=True)
   engine=bin/'strata';engine.write_text('#!/bin/sh\n[ "$1 $2" = "launch --stop" ] || exit 9\nprintf stopped > "$HOME/stopped"\n');engine.chmod(0o755)
   (terminal/'current').symlink_to(terminal/'v1',target_is_directory=True)
   local=p/'.local/bin';local.mkdir(parents=True);shim=local/'strata';shim.symlink_to(terminal/'current/bin/strata')
   r=self.run_cleanup(p);self.assertEqual(r.returncode,0,r.stderr);self.assertFalse(shim.is_symlink());self.assertFalse(terminal.exists());self.assertEqual((p/'stopped').read_text(),'stopped')

 def test_unknown_unit_preserved_when_systemctl_read_fails(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);unit=p/'config/systemd/user/xestrata.service';unit.parent.mkdir(parents=True);unit.write_text('[Service]\nExecStart=/other/app\n')
   r=self.run_cleanup(p,systemctl='#!/bin/sh\nexit 1\n')
   self.assertNotEqual(r.returncode,0);self.assertIn('Cannot validate',r.stderr);self.assertTrue(unit.exists())
 def test_unknown_unit_preserved_when_read_succeeds(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);unit=p/'config/systemd/user/xestrata.service';unit.parent.mkdir(parents=True);unit.write_text('[Service]\nExecStart=/other/app\n')
   r=self.run_cleanup(p,systemctl="#!/bin/sh\nprintf '%s\\n' '[Service]' 'ExecStart=/other/app'\n")
   self.assertNotEqual(r.returncode,0);self.assertIn('Unrecognized',r.stderr);self.assertTrue(unit.exists())

 def test_unit_parent_symlink_preserved(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);outside=p/'outside';outside.mkdir();unit=outside/'xestrata.service';unit.write_text('ExecStart=/usr/bin/xestrata --no-browser\n')
   parent=p/'config/systemd';parent.mkdir(parents=True);(parent/'user').symlink_to(outside,target_is_directory=True)
   r=self.run_cleanup(p,systemctl="#!/bin/sh\nprintf '%s\\n' '[Service]' 'ExecStart=/usr/bin/xestrata --no-browser'\n")
   self.assertNotEqual(r.returncode,0);self.assertIn('Symlinked user service',r.stderr);self.assertTrue(unit.exists())

 def test_running_runtime_executable_detected_despite_custom_argv0(self):
  import shutil
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td);runtime=p/'data/strata/components';runtime.mkdir(parents=True);binary=runtime/'running';shutil.copy('/bin/sleep',binary)
   proc=subprocess.Popen(['innocent-name','30'],executable=str(binary))
   try:
    r=self.run_cleanup(p);self.assertNotEqual(r.returncode,0);self.assertIn('still running',r.stderr);self.assertTrue(binary.exists())
   finally:proc.terminate();proc.wait()
 def test_multiple_execstart_unit_refused(self):
  with tempfile.TemporaryDirectory() as td:
   p=pathlib.Path(td)
   r=self.run_cleanup(p,systemctl="#!/bin/sh\nprintf '%s\\n' '[Service]' 'ExecStart=/usr/bin/xestrata --no-browser' 'ExecStart=/other/app'\n")
   self.assertNotEqual(r.returncode,0);self.assertIn('Unrecognized',r.stderr)
