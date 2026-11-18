import importlib.util, pathlib, tempfile, unittest, subprocess, base64
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('skills',pathlib.Path(__file__).parents[1]/'openwebui_skills.py');s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
class FakeAPI:
 def __init__(self):self.saved={};self.fail=False
 def multipart(self,path,pkg,decisions=None):
  if path.endswith('preview'):return [{'id':pkg['id'],'id_taken':pkg['id'] in self.saved,'name_taken':False}]
  if self.fail:return [{'id':pkg['id'],'status':'error'}]
  self.saved[pkg['id']]=pkg
  return [{'id':pkg['id'],'status':'saved'}]
 def request(self,path):return self.saved[path.split('ids=')[1]]
class Tests(unittest.TestCase):
 def package(self):return {'id':'abc','name':'collection / example','meta':{'tags':['pc-setup'],'i18n':None},'is_active':True,'files':[{'path':'SKILL.md','content':'hello'},{'path':'binary.png','content':base64.b64encode(b'\x00\xff').decode(),'encoding':'base64'}]}
 def test_import_all_bytes_and_reuse(self):
  a=FakeAPI();p=self.package();s.import_all(a,[p]);s.import_all(a,[p]);self.assertEqual(s.hash_files(a.saved['abc']['files']),s.hash_files(p['files']))
 def test_http200_error_not_success(self):
  a=FakeAPI();a.fail=True
  with self.assertRaisesRegex(ValueError,'did not save'):s.import_all(a,[self.package()])
 def test_custom_existing_preserved(self):
  a=FakeAPI();p=self.package();a.saved['abc']={**p,'name':'custom'}
  with self.assertRaisesRegex(ValueError,'preserved'):s.import_all(a,[p])
  self.assertEqual(a.saved['abc']['name'],'custom')
 def test_reference_checksum_gate(self):
  import json,hashlib
  with tempfile.TemporaryDirectory() as td:
   archive=pathlib.Path(td)/'wiki.zim';archive.write_bytes(b'fixture')
   record=pathlib.Path(td)/'ref.json';record.write_text(json.dumps({'archive':str(archive),'sha256':hashlib.sha256(b'fixture').hexdigest()}))
   s.verify_reference(record);archive.write_bytes(b'changed')
   with self.assertRaisesRegex(ValueError,'changed'):s.verify_reference(record)
   self.assertEqual(archive.read_bytes(),b'changed')
 def test_windows_reparse_attribute_rejected(self):
  from types import SimpleNamespace
  with patch.object(pathlib.Path,'lstat',return_value=SimpleNamespace(st_mode=0o40755,st_file_attributes=0x400)):
   self.assertTrue(s.linked(pathlib.Path('junction')))
   with self.assertRaisesRegex(ValueError,'linked repository root'):s.inventory(pathlib.Path('junction'))
 def test_nonlocal_credential_transmission_refused(self):
  for url in ['https://example.com','http://127.0.0.1@evil.com','http://localhost/path','http://localhost?x=1']:
   with self.assertRaises(ValueError):s.API(url)
 def test_complete_subtree_binary_nested_and_distinct_id(self):
  with tempfile.TemporaryDirectory() as td:
   root=pathlib.Path(td);repos={'a':'https://example.com/a.git','b':'https://example.com/b.git'}
   for name,url in repos.items():
    repo=root/name;repo.mkdir();subprocess.run(['git','init',str(repo)],capture_output=True,check=True);subprocess.run(['git','-C',str(repo),'remote','add','origin',url],check=True)
    skill=repo/'skills'/'same';skill.mkdir(parents=True);(skill/'SKILL.md').write_text('---\nname: same\n---\nHello');(skill/'img.bin').write_bytes(b'\0\xff');(skill/'nested').mkdir();(skill/'nested'/'SKILL.md').write_text('nested')
    subprocess.run(['git','-C',str(repo),'add','.'],check=True);subprocess.run(['git','-C',str(repo),'-c','user.name=Test','-c','user.email=t@example.com','commit','-m','fixture'],capture_output=True,check=True)
   with patch.object(s,'REPOS',repos):p=s.inventory(root)
   self.assertEqual(set(p[0]['meta']),{'tags','i18n'});self.assertEqual(len(p),2);self.assertNotEqual(p[0]['id'],p[1]['id']);self.assertNotEqual(p[0]['name'],p[1]['name']);self.assertEqual(len(p[0]['files']),3)
   revisions={name:s.git('-C',root/name,'rev-parse','HEAD') for name in repos}
   with patch.object(s,'REPOS',repos),patch.object(s,'REVISIONS',revisions),self.assertRaisesRegex(ValueError,'422 definitions'):s.inventory(root)
   subprocess.run(['git','-C',str(root/'a'),'config','core.sparseCheckout','true'],check=True)
   with patch.object(s,'REPOS',repos),self.assertRaisesRegex(ValueError,'Sparse checkout'):s.inventory(root)
   subprocess.run(['git','-C',str(root/'a'),'config','core.sparseCheckout','false'],check=True)
   (root/'a'/'skills'/'same'/'outside').symlink_to('/tmp')
   with patch.object(s,'REPOS',repos),self.assertRaisesRegex(ValueError,'Locally changed'):s.inventory(root)
if __name__=='__main__':unittest.main()
