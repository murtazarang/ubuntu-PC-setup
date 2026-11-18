import copy,json,pathlib,tempfile,unittest
import openwebui_connections as c
class API:
 def __init__(self):
  self.data={'/api/v1/configs/tool_servers':{'TOOL_SERVER_CONNECTIONS':[]},'/openai/config':{'ENABLE_OPENAI_API':False,'OPENAI_API_BASE_URLS':['http://old/v1'],'OPENAI_API_KEYS':['secret'],'OPENAI_API_CONFIGS':{'0':{'enable':True,'custom':1}}},'/api/v1/images/config':{'ENABLE_IMAGE_GENERATION':False,'ENABLE_IMAGE_PROMPT_GENERATION':True,'ENABLE_IMAGE_EDIT':True,'IMAGE_GENERATION_DEFAULT_MODEL':'','IMAGE_EDIT_DEFAULT_MODEL':'','IMAGE_CONNECTIONS':[]}}
  self.data['/api/v1/retrieval/embedding']={'RAG_EMBEDDING_ENGINE':'','RAG_EMBEDDING_MODEL':c.EMBEDDING_MODEL,'RAG_EMBEDDING_QUERY_PREFIX':c.QUERY_PREFIX}
  self.data['/api/v1/retrieval/config']={'RAG_RERANKING_ENGINE':'','RAG_RERANKING_MODEL':c.RERANKING_MODEL,'ENABLE_RAG_HYBRID_SEARCH':True,'TEXT_SPLITTER':'token_transformers','RAG_TOKENIZER_MODEL':c.EMBEDDING_MODEL,'CHUNK_SIZE':400,'CHUNK_OVERLAP':50}
  self.writes=0;self.verify=True
 def request(self,path,body=None):
  if path.endswith('/verify'):return {'paths':{'/search':{}}} if self.verify else {}
  path=path.removesuffix('/update')
  if body:self.data[path]=json.loads(body);self.writes+=1
  return copy.deepcopy(self.data[path])
class Tests(unittest.TestCase):
 def run_config(self,a):
  with tempfile.TemporaryDirectory() as td:
   key=pathlib.Path(td)/'key';key.write_text('x'*32);c.configure(a,key,'qwen-image-2.1-colibri')
 def test_custom_retrieval_preserved_before_any_writes(self):
  a=API();a.data['/api/v1/retrieval/embedding']['RAG_EMBEDDING_MODEL']='custom/model'
  with self.assertRaisesRegex(ValueError,'preserved'):self.run_config(a)
  self.assertEqual(a.writes,0);self.assertEqual(a.data['/api/v1/retrieval/embedding']['RAG_EMBEDDING_MODEL'],'custom/model')
 def test_query_only_prefix_verified_without_mutation(self):
  for key,value in (('RAG_EMBEDDING_QUERY_PREFIX','wrong'),('RAG_EMBEDDING_CONTENT_PREFIX','should-not-prefix-documents')):
   a=API();a.data['/api/v1/retrieval/embedding'][key]=value
   with self.assertRaises(ValueError):self.run_config(a)
   self.assertEqual(a.writes,0)
 def test_failed_reranker_disabling_hybrid_is_not_success(self):
  a=API();a.data['/api/v1/retrieval/config']['ENABLE_RAG_HYBRID_SEARCH']=False
  with self.assertRaises(ValueError):self.run_config(a)
  self.assertEqual(a.writes,0)
 def test_merge_rerun_and_unrelated_preserved(self):
  a=API();self.run_config(a);self.assertEqual(a.data['/openai/config']['OPENAI_API_KEYS'][0],'secret');self.assertEqual(a.data['/openai/config']['OPENAI_API_CONFIGS']['0'],{'enable':True,'custom':1});self.assertEqual(a.writes,3);self.assertTrue(a.data['/api/v1/configs/tool_servers']['TOOL_SERVER_CONNECTIONS'][0]['config']['enable']);self.run_config(a);self.assertEqual(a.writes,3)
  image=a.data['/api/v1/images/config'];self.assertFalse(image['ENABLE_IMAGE_EDIT']);self.assertFalse(image['ENABLE_IMAGE_PROMPT_GENERATION']);self.assertEqual(image['IMAGE_GENERATION_DEFAULT_MODEL'],'pc-setup-colibri-image:qwen-image-2.1-colibri')
 def test_only_exact_unconfigured_cloud_default_replaced(self):
  a=API();a.data['/openai/config'].update(OPENAI_API_BASE_URLS=['https://api.openai.com/v1'],OPENAI_API_KEYS=[''],OPENAI_API_CONFIGS={});self.run_config(a);self.assertEqual(a.data['/openai/config']['OPENAI_API_BASE_URLS'],['http://127.0.0.1:8000/v1'])
  a=API();a.data['/openai/config'].update(OPENAI_API_BASE_URLS=['https://api.openai.com/v1'],OPENAI_API_KEYS=['user-secret'],OPENAI_API_CONFIGS={});self.run_config(a);self.assertEqual(a.data['/openai/config']['OPENAI_API_KEYS'][0],'user-secret')
 def test_existing_image_defaults_preserved(self):
  a=API();image=a.data['/api/v1/images/config'];image['IMAGE_CONNECTIONS']=[{'id':'custom','url':'http://custom','config':{}}];image['IMAGE_GENERATION_DEFAULT_MODEL']='custom:model';self.run_config(a);self.assertEqual(a.data['/api/v1/images/config']['IMAGE_GENERATION_DEFAULT_MODEL'],'custom:model')
 def test_bridge_must_verify_before_writes(self):
  a=API();a.verify=False
  with self.assertRaisesRegex(ValueError,'usable OpenAPI'):self.run_config(a)
  self.assertEqual(a.writes,0)
 def test_conflicting_existing_image_not_overwritten(self):
  a=API();self.run_config(a);a.data['/api/v1/images/config']['IMAGE_CONNECTIONS'][0]['url']='http://custom'
  with self.assertRaisesRegex(ValueError,'preserved'):self.run_config(a)
  self.assertEqual(a.data['/api/v1/images/config']['IMAGE_CONNECTIONS'][0]['url'],'http://custom')
if __name__=='__main__':unittest.main()
