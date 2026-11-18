import importlib.util, os, tempfile, unittest, shutil, subprocess
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
def load(name,file):
 s=importlib.util.spec_from_file_location(name,ROOT/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
web=load('web','create-openwebui-services.py');col=load('col','create-colibri-shortcuts.py')
class Tests(unittest.TestCase):
 def test_services_preserve_state_and_ports(self):
  with tempfile.TemporaryDirectory() as t, patch.dict(os.environ,{},clear=True), patch('subprocess.check_output',side_effect=OSError()):
   home=Path(t);base=home/'app space';units=web.configure(base,home/'archives',home)
   secret=(base/'webui-secret').read_text();(base/'webui.env').write_text('CUSTOM=unchanged\n')
   web.configure(base,home/'archives',home)
   self.assertEqual((base/'webui-secret').read_text(),secret)
   self.assertEqual((base/'webui.env').read_text(),'CUSTOM=unchanged\n')
   self.assertIn('127.0.0.1',(units/'pc-setup-openwebui.service').read_text())
   self.assertIn('EnvironmentFile='+str(base/'webui.env'),(units/'pc-setup-openwebui.service').read_text())
   self.assertIn('USE_CUDA_DOCKER=true',(units/'pc-setup-openwebui.service').read_text())
   self.assertIn('USE_SLIM_DOCKER=false',(units/'pc-setup-openwebui.service').read_text())
   self.assertIn("DEVICE_TYPE == 'cuda'",(units/'pc-setup-openwebui.service').read_text())
   self.assertIn('torch.cuda.is_available',(units/'pc-setup-openwebui.service').read_text())
   self.assertIn('--api-key',(units/'pc-setup-wikipedia.service').read_text())
   self.assertEqual((base/'webui-secret').stat().st_mode & 0o777,0o600)
 @unittest.skipUnless(shutil.which('systemd-analyze'),'systemd parser unavailable')
 def test_actual_systemd_parser(self):
  with tempfile.TemporaryDirectory() as t, patch.dict(os.environ,{},clear=True), patch('subprocess.check_output',side_effect=OSError()):
   home=Path(t);base=home/'app space';units=web.configure(base,home/'archive',home)
   for name in ('open-webui','mcpo','openzim-mcp'):
    binary=base/'bin'/name;binary.parent.mkdir(exist_ok=True);binary.write_text('#!/bin/sh\nexit 0\n');binary.chmod(0o755)
   py=base/'tools/open-webui/bin/python';py.parent.mkdir(parents=True);py.write_text('#!/bin/sh\nexit 0\n');py.chmod(0o755)
   runtime=home/'runtime';runtime.mkdir()
   result=subprocess.run(['/usr/bin/systemd-analyze','--user','verify',*[str(p) for p in units.glob('*.service')]],env={'XDG_RUNTIME_DIR':str(runtime),'PATH':'/usr/bin:/bin'},capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertNotIn('ignoring',result.stderr.lower())
 def test_modified_owned_unit_and_linked_secret_are_preserved(self):
  with tempfile.TemporaryDirectory() as t, patch.dict(os.environ,{},clear=True), patch('subprocess.check_output',side_effect=OSError()):
   home=Path(t);base=home/'app';units=web.configure(base,home/'archive',home)
   unit=units/'pc-setup-openwebui.service';unit.write_text(unit.read_text()+'# personal change\n')
   with self.assertRaises(SystemExit): web.configure(base,home/'archive',home)
   self.assertIn('personal change',unit.read_text())
   other=home/'other';other.write_text('keep');(base/'mcpo-key').unlink();(base/'mcpo-key').symlink_to(other)
   with self.assertRaises(SystemExit): web.configure(base,home/'archive',home)
   self.assertEqual(other.read_text(),'keep')
 def test_service_collision(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'unit';p.write_text('unrelated')
   with self.assertRaises(SystemExit):web.owned(p,'new')
   self.assertEqual(p.read_text(),'unrelated')
 def test_model_control_owned_units_no_ui(self):
  with tempfile.TemporaryDirectory() as t,patch.dict(os.environ,{},clear=True),patch('subprocess.run',side_effect=OSError()):
   home=Path(t)
   col.install('/native/coli','/model','/icon',True,home=home)
   col.install('/native/coli','/image','/icon',True,home=home,image=True)
   units=home/'.config/systemd/user'
   text=(units/'pc-setup-colibri-serve.service').read_text();image=(units/'pc-setup-colibri-serve-image.service').read_text()
   self.assertIn('COLI_VULKAN=1',text);self.assertIn('COLI_VULKAN=1',image);self.assertIn('COLI_VK_DEV2=auto',text);self.assertNotIn('COLI_VK_DEV2=auto',image)
   self.assertNotIn('After=',text);self.assertIn('After=',image)
   self.assertNotIn("'ui'",text);self.assertIn('"serve"',image)
   self.assertTrue((home/'Desktop/Stop Colibri Serve.desktop').exists())
if __name__=='__main__':unittest.main()
