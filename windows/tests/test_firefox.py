import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

p = Path(__file__).resolve().parents[1] / "apply_firefox_policy.py"
spec = importlib.util.spec_from_file_location("firefox", p)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Tests(unittest.TestCase):
    def test_preserve_install_and_release(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "distribution" / "policies.json"
            path.parent.mkdir()
            path.write_text(json.dumps({"policies": {"DisableTelemetry": True}}))
            m.merge(path)
            data = json.loads(path.read_text())
            self.assertTrue(data["policies"]["DisableTelemetry"])
            self.assertEqual(len(data["policies"]["ExtensionSettings"]), 3)
            m.merge(path, True)
            data = json.loads(path.read_text())
            u = data["policies"]["3rdparty"]["Extensions"]["uBlock0@raymondhill.net"]
            self.assertNotIn("toOverwrite", u)
            self.assertIn("advancedSettings", u)
            self.assertTrue(data["policies"]["DisableTelemetry"])

    def test_conflict_does_not_replace_file(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "policies.json"
            original = '{"policies":{"3rdparty":{"Extensions":{"uBlock0@raymondhill.net":{"custom":true}}}}}'
            path.write_text(original)
            with self.assertRaises(RuntimeError):
                m.merge(path)
            self.assertEqual(path.read_text(), original)


if __name__ == "__main__":
    unittest.main()
