import importlib.util
from pathlib import Path
import tempfile
import unittest
import json

p = Path(__file__).resolve().parents[1] / "configure_model.py"
spec = importlib.util.spec_from_file_location("model", p)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Tests(unittest.TestCase):
    def test_preserves_and_is_idempotent(self):
        data = {'providers': {'other': {'baseUrl': 'example'}}}
        m.merge(data, 'model1', '8080')
        m.merge(data, 'model1', '8080')
        self.assertEqual(data['providers']['other']['baseUrl'], 'example')
        self.assertEqual(data['providers']['local-inference']['baseUrl'], 'http://127.0.0.1:8080/v1')
        with self.assertRaises(ValueError):
            m.merge(data, 'model2', '8080')

    def test_yaml_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'models.yml'
            m.save(p, m.merge({}, 'demo', '8095'))
            self.assertEqual(m.yaml.safe_load(p.read_text())['providers']['local-inference']['models'][0]['id'], 'demo')

    def test_legacy_json_preserved_when_creating_yaml(self):
        with tempfile.TemporaryDirectory() as d:
            directory = Path(d)
            original = {'providers': {'existing': {'baseUrl': 'http://example.test'}}}
            legacy = directory / 'models.json'
            legacy.write_text(json.dumps(original))
            path, data = m.load_config(directory)
            self.assertEqual(path.name, 'models.yml')
            m.save(path, m.merge(data, 'demo', '8080'))
            self.assertEqual(m.yaml.safe_load(path.read_text())['providers']['existing'],
                             original['providers']['existing'])
            self.assertEqual(json.loads(legacy.read_text()), original)

    def test_yaml_precedence_and_invalid_root(self):
        with tempfile.TemporaryDirectory() as d:
            directory = Path(d)
            (directory / 'models.yaml').write_text('providers: {}\n')
            self.assertEqual(m.load_config(directory)[0].name, 'models.yaml')
            (directory / 'models.yml').write_text('providers: {chosen: {}}\n')
            self.assertIn('chosen', m.load_config(directory)[1]['providers'])
            (directory / 'models.yml').write_text('[]\n')
            with self.assertRaises(ValueError):
                m.load_config(directory)

    def test_endpoint_response_validation(self):
        self.assertEqual(m.model_id_from_response({'data': [{'id': 'demo'}]}), 'demo')
        for body in ({}, {'data': []}, {'data': [{}]}, {'data': [{'id': 'x\ry'}]}, []):
            with self.assertRaises(ValueError):
                m.model_id_from_response(body)

if __name__ == '__main__':
    unittest.main()
