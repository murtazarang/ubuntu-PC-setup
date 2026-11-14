import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

P = Path(__file__).resolve().parents[1] / 'configure_local.py'
spec = importlib.util.spec_from_file_location('configure_local', P)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ConfigTests(unittest.TestCase):
    def test_preserves_unrelated_and_idempotent(self):
        data = {'mcpServers': {'existing': {'command': 'other'}}, 'other': 42}
        m.merge_mcp(data, 'C:/uvx.exe', 'D:/wiki')
        m.merge_mcp(data, 'C:/uvx.exe', 'D:/wiki')
        self.assertEqual(data['mcpServers']['existing']['command'], 'other')
        self.assertEqual(data['mcpServers']['openzim']['args'], ['--offline', 'openzim-mcp==3.4.0', 'D:/wiki'])
        self.assertEqual(data['other'], 42)

    def test_conflicting_entry_rejected(self):
        with self.assertRaises(ValueError):
            m.merge_mcp({'mcpServers': {'openzim': {'command': 'custom'}}}, 'uvx', 'wiki')

    def test_provider_preserves_other_settings(self):
        data = {'agents': {'providers': {'omp': {'custom': True},
                                        'other': {'enabled': True}}}}
        m.merge_paseo(data, 'C:/omp.exe')
        m.merge_paseo(data, 'C:/omp.exe')
        self.assertTrue(data['agents']['providers']['omp']['custom'])
        self.assertTrue(data['agents']['providers']['other']['enabled'])
        with self.assertRaises(ValueError):
            m.merge_paseo(data, 'C:/different.exe')

    def test_atomic_output(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'nested' / 'mcp.json'
            m.atomic_json(path, {'value': 'ok'})
            self.assertEqual(m.read_map(path), {'value': 'ok'})
            self.assertEqual(list(path.parent.glob('.setup-*')), [])


if __name__ == '__main__':
    unittest.main()
