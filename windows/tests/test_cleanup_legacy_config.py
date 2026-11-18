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
        self.assertEqual(m.clean_roles(roles, 'local-inference/qwen'),{'fast':'other/fast','nested':{'x':'local-inference/qwen'}})
    def test_other_legacy_named_selector_preserved(self):
        roles={'default':'local-inference/qwen','custom':'local-inference/another-model','near':'local-inference/qwen-extended'}
        self.assertEqual(m.clean_roles(roles, 'local-inference/qwen'), {'custom':'local-inference/another-model','near':'local-inference/qwen-extended'})
    def test_colibri_provider_preserved(self):
        data=old_config('8000'); before=copy.deepcopy(data)
        self.assertFalse(m.clean_models(data)); self.assertEqual(data,before)
    def test_empty(self):
        self.assertFalse(m.clean_models({}))

class MainTransactionTests(unittest.TestCase):
    """Exercise real parsing/backups/staging with only the OMP process mocked."""
    def exercise(self, failure=None, suffix='.yml', customized=False):
        import tempfile
        import json
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); backup=root/'backup'
            path=root/('models'+suffix)
            data=old_config()
            if customized: data['providers']['local-inference']['apiKey']='custom'
            data['providers']['keep']={'models':[]}
            original=json.dumps(data) if suffix=='.json' else m.yaml.safe_dump(data)
            path.write_text(original,encoding='utf-8')
            roles={'default':'local-inference/qwen','fast':'other/fast','custom':'local-inference/another-model'}
            saved=copy.deepcopy(roles); calls=[]
            def omp(_, *args):
                calls.append(args)
                if args==('path',): return str(root)
                if args==('list','--scope','global','--json'):
                    return json.dumps({'modelRoles':{'value':copy.deepcopy(saved)}})
                if args[:2]==('set','modelRoles'):
                    saved.clear(); saved.update(json.loads(args[2]))
                    if failure=='set' and saved!=roles: raise RuntimeError('partial CLI failure')
                    return ''
                raise AssertionError(args)
            with patch.object(m,'run',side_effect=omp), patch('sys.argv',['cleanup','--omp','omp','--backup',str(backup)]):
                if failure=='temp':
                    with patch.object(m.tempfile,'mkstemp',side_effect=PermissionError('denied')):
                        with self.assertRaises(PermissionError):m.main()
                elif failure=='replace':
                    with patch.object(m.os,'replace',side_effect=OSError('replace failed')):
                        with self.assertRaises(OSError):m.main()
                elif failure=='set':
                    with self.assertRaises(RuntimeError):m.main()
                else:m.main()
            if failure or customized:
                self.assertEqual(path.read_text(),original)
                self.assertEqual(saved,roles)
            else:
                cleaned=json.loads(path.read_text()) if suffix=='.json' else m.yaml.safe_load(path.read_text())
                self.assertEqual(cleaned,{'providers':{'keep':{'models':[]}}})
                self.assertEqual(saved,{'fast':'other/fast','custom':'local-inference/another-model'})
            if not customized:
                self.assertEqual((backup/path.name).read_text(),original)
                self.assertEqual(json.loads((backup/'modelRoles.json').read_text()),roles)
            if failure=='temp' or customized:
                self.assertFalse(any(c[0]=='set' for c in calls))
            self.assertFalse(list(root.glob('.models-cleanup-*')))
    def test_temp_creation_failure_does_not_change_roles(self):self.exercise('temp')
    def test_replace_failure_restores_roles(self):self.exercise('replace')
    def test_partial_cli_failure_restores_roles(self):self.exercise('set')
    def test_yaml_success(self):self.exercise()
    def test_json_success(self):self.exercise(suffix='.json')
    def test_custom_provider_untouched(self):self.exercise(customized=True)

if __name__=='__main__':unittest.main()
