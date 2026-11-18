import importlib.util
from pathlib import Path
import unittest
import copy
spec=importlib.util.spec_from_file_location('cleanup',Path(__file__).parents[1]/'cleanup_legacy_config.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def old_config(port='8080'):
    return {'providers': {'local-inference': {'baseUrl':f'http://127.0.0.1:{port}/v1','api':'openai-completions','auth':'none','compat':{'supportsDeveloperRole':False},'models':[{'id':'qwen','name':'Local qwen','reasoning':True,'input':['text'],'contextWindow':32768,'maxTokens':4096,'cost':{'input':0,'output':0,'cacheRead':0,'cacheWrite':0}}]}}}
class Tests(unittest.TestCase):
    def test_exact_old_shape(self):
        data=old_config();data['providers']['other']={'baseUrl':'https://example.com'}
        self.assertTrue(m.clean_models(data))
        self.assertEqual(data,{'providers':{'other':{'baseUrl':'https://example.com'}}})
    def test_custom_preserved(self):
        data=old_config('8095');data['providers']['local-inference']['apiKey']='custom'
        before=copy.deepcopy(data);self.assertFalse(m.clean_models(data));self.assertEqual(data,before)
    def test_roles(self):
        roles={'default':'local-inference/qwen','fast':'other/fast','nested':{'x':'local-inference/qwen'}}
        self.assertEqual(m.clean_roles(roles),{'fast':'other/fast','nested':{'x':'local-inference/qwen'}})
    def test_empty(self):
        self.assertFalse(m.clean_models({}))
if __name__=='__main__':unittest.main()
