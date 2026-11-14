import importlib.util
from pathlib import Path
import tempfile
import unittest

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

if __name__ == '__main__':
    unittest.main()
