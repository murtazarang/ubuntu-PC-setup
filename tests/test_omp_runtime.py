import importlib.util,pathlib,tempfile,unittest,os,json,subprocess,sys,time
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('remove_omp',ROOT/'remove-omp-runtime.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class RuntimeTests(unittest.TestCase):
 def test_unknown_duplicate_blocks(self):
  with tempfile.TemporaryDirectory() as t,patch.object(mod.shutil,'which',return_value=None):
   p=pathlib.Path(t);(p/'custom').mkdir();(p/'custom/omp').write_text('other')
   with patch.dict(os.environ,{'PATH':str(p/'custom')}):
    with self.assertRaisesRegex(RuntimeError,'Unrecognized'):mod.discover(p)
   self.assertEqual((p/'custom/omp').read_text(),'other')
 def test_offpath_custom_standalone_override_is_discovered(self):
  with tempfile.TemporaryDirectory() as t,patch.object(mod.shutil,'which',return_value=None):
   p=pathlib.Path(t);custom=p/'custom';custom.mkdir();binary=custom/'omp';binary.write_text('standalone')
   with patch.dict(os.environ,{'PATH':'/nonexistent','PI_INSTALL_DIR':str(custom)}):
    records=mod.discover(p)
   self.assertEqual([r['path'] for r in records],[str(binary)])
 def test_decline_offpath_runtime_reports_incomplete(self):
  record={'kind':'standalone','path':'/off-path/omp'}
  with patch.object(mod,'discover',return_value=[record]),patch.object(mod,'ensure_stopped'):
   with self.assertRaisesRegex(RuntimeError,'incomplete'):mod.uninstall(lambda _:'no')
 def test_bun_global_discovery(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);binary=p/'.bun/bin/omp';binary.parent.mkdir(parents=True);binary.write_text('fixture')
   def query(args,**kw):return str(binary.parent) if args[1:]==['pm','bin','-g'] else '/global node_modules\n└── '+mod.PACKAGE+'@1.0.0'
   with patch.object(mod.shutil,'which',side_effect=lambda name:'/bin/bun' if name=='bun' else None),patch.object(mod,'run',side_effect=query),patch.dict(os.environ,{'PATH':str(binary.parent)}):
    records=mod.discover(p)
   self.assertEqual(records[0]['kind'],'bun');self.assertEqual(records[0]['bin'],str(binary))
 def test_only_named_package_uninstalled_and_final_absence_checked(self):
  record={'kind':'bun','manager':'/bin/bun','package':mod.PACKAGE,'bin':'/bin/omp'}
  with patch.object(mod,'discover',side_effect=[[record],[record],[]]),patch.object(mod,'ensure_stopped'),patch.object(mod,'run') as run,patch.object(mod.shutil,'which',return_value=None):
   mod.uninstall(lambda _: 'REMOVE OMP')
   run.assert_called_once_with(['/bin/bun','remove','--global',mod.PACKAGE])
 def test_source_package_process_is_not_deleted(self):
  proc=subprocess.Popen([sys.executable,'-c','import time; time.sleep(10)',mod.PACKAGE])
  try:
   time.sleep(.1)
   with self.assertRaisesRegex(RuntimeError,'running'):mod.ensure_stopped([])
  finally:
   proc.terminate();proc.wait(timeout=5)
 def test_remaining_package_prevents_success(self):
  record={'kind':'npm','manager':'/bin/npm','package':mod.PACKAGE,'bin':'/bin/omp'}
  with patch.object(mod,'discover',side_effect=[[record],[record],[record]]),patch.object(mod,'ensure_stopped'),patch.object(mod,'run'),patch.object(mod.shutil,'which',return_value=None):
   with self.assertRaisesRegex(RuntimeError,'remains'):mod.uninstall(lambda _:'REMOVE OMP')
if __name__=='__main__':unittest.main()
