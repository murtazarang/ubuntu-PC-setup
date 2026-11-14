import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('configure_powertoys', Path(__file__).resolve().parents[1] / 'configure_powertoys.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class PowerToysTests(unittest.TestCase):
    def test_merge_preserves_unrelated_settings_and_plugins(self):
        general = {'enabled': {'FancyZones': False}, 'startup': False}
        launcher = {'plugins': [{'Name': 'Calculator'}], 'properties': {'maximum_number_of_results': 9}}
        g, l = module.merged(general, launcher)
        self.assertFalse(g['enabled']['FancyZones'])
        self.assertFalse(g['startup'])
        self.assertTrue(g['enabled']['PowerToys Run'])
        self.assertTrue(g['enabled']['Awake'])
        self.assertNotIn('PowerLauncher', g['enabled'])
        self.assertEqual(l['plugins'], launcher['plugins'])
        self.assertEqual(l['properties']['maximum_number_of_results'], 9)
        self.assertEqual(l['properties']['open_powerlauncher']['code'], 113)
        self.assertTrue(l['properties']['open_powerlauncher']['win'])
        self.assertEqual(module.merged(g, l), (g, l))
        self.assertNotIn('Awake', general['enabled'])

    def test_invalid_object_fails(self):
        for general, launcher in [([], {}), ({'enabled': []}, {}), ({}, {'properties': []})]:
            with self.assertRaises(ValueError): module.merged(general, launcher)

    def test_initialization_required_and_backup_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError): module.configure(root)
            original = '{"enabled": {"FancyZones": false}, "theme": "dark"}'
            (root / 'settings.json').write_text(original)
            module.configure(root)
            module.configure(root)
            self.assertEqual((root / 'settings.json.pc-setup.bak').read_text(), original)
            self.assertEqual(json.loads((root / 'settings.json').read_text())['theme'], 'dark')

if __name__ == '__main__': unittest.main()
