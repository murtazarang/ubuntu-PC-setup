import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

spec=importlib.util.spec_from_file_location('download_colibri_model',Path(__file__).resolve().parents[1]/'download_colibri_model.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
DATA=b'model test data'
SHA=hashlib.sha256(DATA).hexdigest()
def entry(): return {'repository':'owner/repo','revision':'a'*40,'files':[{'path':'model.bin','size':len(DATA),'sha256':SHA}]}
class Response(io.BytesIO):
 def __init__(self,data,status=200,headers=None):super().__init__(data);self.status=status;self.headers=headers or {}
class DownloadTests(unittest.TestCase):
 def test_pinned_production_manifest(self):
  models=json.loads((Path(__file__).resolve().parents[1]/'colibri-models.json').read_text())
  self.assertEqual(set(models),{'dense27b','flash-next-iq2-xs','qwen-image-2.1'})
  for e in models.values():m.validate_manifest(e)
  self.assertEqual(sum(x['size'] for x in models['dense27b']['files']),16564259744)
  self.assertEqual(sum(x['size'] for x in models['flash-next-iq2-xs']['files']),68026093024)
  self.assertEqual(len(models['flash-next-iq2-xs']['files']),2)
  self.assertEqual(sum(x['size'] for x in models['qwen-image-2.1']['files']),33131609424)
  self.assertIn(models['flash-next-iq2-xs']['first_shard'],[f['path'] for f in models['flash-next-iq2-xs']['files']])
 def test_fresh_and_verified_reuse(self):
  with tempfile.TemporaryDirectory() as d:
   opener=Mock(return_value=Response(DATA));down=lambda u,p,n,h:m.download_file(u,p,n,h,opener=opener)
   m.install(entry(),d,down);m.install(entry(),d,Mock(side_effect=AssertionError('redownload')))
   self.assertEqual((Path(d)/'model.bin').read_bytes(),DATA)
 def test_resume(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'model.bin';p.with_name('model.bin.part').write_bytes(DATA[:5])
   op=Mock(return_value=Response(DATA[5:],206,{'Content-Range':f'bytes 5-{len(DATA)-1}/{len(DATA)}'}))
   m.download_file('https://example.invalid',p,len(DATA),SHA,op)
   self.assertEqual(op.call_args.args[0].headers['Range'],'bytes=5-')
   self.assertEqual(p.read_bytes(),DATA)
 def test_range_ignored_preserves(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'model.bin';part=p.with_name('model.bin.part');part.write_bytes(DATA[:5])
   with self.assertRaises(ValueError):m.download_file('https://example.invalid',p,len(DATA),SHA,Mock(return_value=Response(DATA)))
   self.assertEqual(part.read_bytes(),DATA[:5])
 def test_bad_hash_preserves(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'model.bin'
   with self.assertRaises(ValueError):m.download_file('https://example.invalid',p,len(DATA),'0'*64,Mock(return_value=Response(DATA)))
   self.assertFalse(p.exists());self.assertTrue(p.with_name('model.bin.part').exists())
 def test_low_space(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(OSError):m.install(entry(),d,Mock(side_effect=AssertionError('network')),lambda _:type('D',(),{'free':0})())
 def test_conversion_reserve(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(OSError):m.install(entry(),d,Mock(side_effect=AssertionError('network')),lambda _:type('D',(),{'free':m.RESERVE+len(DATA)+100})(),reserve_bytes=101)
 def test_wrong_range_total_preserved(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'model.bin';part=p.with_name('model.bin.part');part.write_bytes(DATA[:5])
   with self.assertRaises(ValueError):m.download_file('https://example.invalid',p,len(DATA),SHA,Mock(return_value=Response(DATA[5:],206,{'Content-Range':'bytes 5-14/99'})))
   self.assertEqual(part.read_bytes(),DATA[:5])
 def test_conflicting_existing_retained(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'model.bin';p.write_bytes(b'custom')
   with self.assertRaises(ValueError):m.install(entry(),d)
   self.assertEqual(p.read_bytes(),b'custom')
 def test_path_traversal(self):
  e=entry();e['files'][0]['path']='../model.bin'
  with self.assertRaises(ValueError):m.validate_manifest(e)
 def test_incomplete_retried(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'model.bin';op=Mock(side_effect=[Response(DATA[:5]),Response(DATA[5:],206,{'Content-Range':f'bytes 5-{len(DATA)-1}/{len(DATA)}'})])
   m.download_file('https://example.invalid',p,len(DATA),SHA,op,sleep=lambda _:None)
   self.assertEqual(p.read_bytes(),DATA)
if __name__=='__main__':unittest.main()
