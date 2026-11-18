import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import os
import json
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('cleanup',Path(__file__).resolve().parents[1]/'remove-old-omp-skills.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Cleanup(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.home=Path(self.tmp.name)
  self.root=self.home/'.local/share/omp-skills';self.old=self.root/m.NAMES[0];self.old.mkdir(parents=True);(self.old/'custom.md').write_text('custom')
 def test_removes_custom_edits_but_preserves_sibling(self):
  sibling=self.root/'my-own-skills';sibling.mkdir();m.remove(self.home,[],lambda _: 'DELETE OLD OMP SKILLS');self.assertFalse(self.old.exists());self.assertTrue(sibling.exists())
 def test_owned_history_and_custom_skill_deletion(self):
  omp=self.home/'.omp';(omp/'agent/skills/custom').mkdir(parents=True);(omp/'history.json').write_text('old')
  unrelated=self.home/'documents';unrelated.mkdir()
  m.remove(self.home,[],lambda _: 'DELETE OLD OMP SKILLS',roots=[omp])
  self.assertFalse(omp.exists());self.assertTrue(unrelated.exists())
 def test_mounted_descendant_preserved(self):
  with patch.object(m,'mountpoints',return_value=[self.old/'external']):
   with self.assertRaisesRegex(RuntimeError,'mounted'):
    m.remove(self.home,[],lambda _: 'DELETE OLD OMP SKILLS')
  self.assertTrue((self.old/'custom.md').exists())
 def test_mounted_root_preserved(self):
  with patch.object(m,'mountpoints',return_value=[self.old]):
   with self.assertRaisesRegex(RuntimeError,'mounted'):
    m.remove(self.home,[],lambda _: 'DELETE OLD OMP SKILLS')
  self.assertTrue(self.old.exists())
 def test_offline_profile_registration_outside_owned_scope_blocks(self):
  config=self.home/'.omp/profiles/other/agent/settings.json';config.parent.mkdir(parents=True)
  outside=self.home/'shared-skills';outside.mkdir();config.write_text(json.dumps({'skills':{'customDirectories':[str(outside)]}}))
  env={k:v for k,v in os.environ.items() if not k.startswith(('PI_','XDG_','PASEO_','STRATA_'))};env.update(HOME=str(self.home),PATH='/usr/bin:/bin')
  r=subprocess.run([sys.executable,str(Path(m.__file__)),'--check'],env=env,capture_output=True,text=True)
  self.assertNotEqual(r.returncode,0);self.assertIn('ownership review',r.stderr);self.assertTrue(outside.exists())
 def test_offline_owned_registration_without_runtime_is_supported(self):
  config=self.home/'.omp/agent/settings.json';config.parent.mkdir(parents=True)
  config.write_text(json.dumps({'skills':{'customDirectories':[str(self.old)]}}))
  env={k:v for k,v in os.environ.items() if not k.startswith(('PI_','XDG_','PASEO_','STRATA_'))};env.update(HOME=str(self.home),PATH='/usr/bin:/bin')
  r=subprocess.run([sys.executable,str(Path(m.__file__)),'--check'],env=env,capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr);self.assertTrue(config.exists())
 def test_exact_inventory_file_removed_with_sibling_retained(self):
  metadata=self.root/'installed-skills.json';metadata.write_text('{}');sibling=self.root/'notes.txt';sibling.write_text('keep')
  m.remove(self.home,[],lambda _: 'DELETE OLD OMP SKILLS',roots=[metadata])
  self.assertFalse(metadata.exists());self.assertTrue(sibling.exists())
 def test_plugin_payload_settings_are_not_treated_as_omp_config(self):
  payload=self.home/'.omp/plugins/example/settings.json';payload.parent.mkdir(parents=True);payload.write_text('not an OMP config')
  env={k:v for k,v in os.environ.items() if not k.startswith(('PI_','XDG_','PASEO_','STRATA_'))};env.update(HOME=str(self.home),PATH='/usr/bin:/bin')
  r=subprocess.run([sys.executable,str(Path(m.__file__)),'--check'],env=env,capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
 def test_process_starts_during_prompt_preserves_all_data(self):
  active=[]
  def confirm(_): active.append(True);return 'DELETE OLD OMP SKILLS'
  def guard():
   if active: raise RuntimeError('OMP process started while confirming')
  with self.assertRaisesRegex(RuntimeError,'process started'):
   m.remove(self.home,[],confirm,process_guard=guard)
  self.assertTrue((self.old/'custom.md').exists())
 def test_unregistered_corpus_and_partial_block_before_confirmation(self):
  for suffix in ('.zim','.zim.part'):
   with self.subTest(suffix=suffix):
    nested=self.old/'downloads';nested.mkdir(exist_ok=True)
    archive=nested/('wikipedia_en_all_nopic_2026-06'+suffix);archive.write_text('irreplaceable')
    with self.assertRaisesRegex(RuntimeError,'archive download retained'):
     m.remove(self.home,[],lambda _: self.fail('Must not ask to delete an undiscovered archive'))
    self.assertEqual(archive.read_text(),'irreplaceable');archive.unlink()
 def test_archive_appearing_during_confirmation_blocks_deletion(self):
  archive=self.old/'wiki.zim.part'
  def confirm(_):archive.write_text('partial');return 'DELETE OLD OMP SKILLS'
  with self.assertRaisesRegex(RuntimeError,'archive download retained'):m.remove(self.home,[],confirm)
  self.assertTrue(archive.exists());self.assertTrue((self.old/'custom.md').exists())
 def test_decline(self):
  with self.assertRaises(RuntimeError):m.remove(self.home,[],lambda _: 'no')
  self.assertTrue(self.old.exists())
 def test_protected_corpus(self):
  corpus=self.old/'wiki.zim';corpus.write_text('keep')
  with self.assertRaises(RuntimeError):m.remove(self.home,[corpus],lambda _: 'DELETE OLD OMP SKILLS')
  self.assertTrue(corpus.exists())
 def test_linked_root(self):
  target=self.home/'external';target.mkdir();self.old.rename(target/'old');self.old.symlink_to(target/'old')
  with self.assertRaises(RuntimeError):m.remove(self.home,[],lambda _: 'DELETE OLD OMP SKILLS')
 def test_linked_child_does_not_delete_target(self):
  target=self.home/'keep';target.write_text('safe');(self.old/'link').symlink_to(target);m.remove(self.home,[],lambda _: 'DELETE OLD OMP SKILLS');self.assertTrue(target.exists())
if __name__=='__main__':unittest.main()
