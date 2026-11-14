import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location('configure_everything', ROOT / 'configure_everything.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EverythingTests(unittest.TestCase):
    def test_existing_plugin_enabled_without_replacing_preferences(self):
        original = {'properties': {'theme': 2}, 'plugins': [
            {'Id': 'other', 'Disabled': True},
            {'Id': module.PLUGIN_ID, 'Disabled': True, 'ActionKeyword': 'ev', 'IsGlobal': False,
             'AdditionalOptions': [{'Key': 'custom', 'Value': 1}]},
        ]}
        result = module.enabled(original)
        self.assertFalse(result['plugins'][1]['Disabled'])
        self.assertEqual(result['plugins'][1]['ActionKeyword'], 'ev')
        self.assertFalse(result['plugins'][1]['IsGlobal'])
        self.assertEqual(result['plugins'][0], original['plugins'][0])
        self.assertTrue(original['plugins'][1]['Disabled'])
        self.assertEqual(module.enabled(result), result)

    def test_new_plugin_keeps_upstream_defaults(self):
        data = {'plugins': []}
        self.assertEqual(module.enabled(data), data)

    def test_installed_files_verified_before_settings_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / 'settings.json'
            manifest = root / 'plugin.json'
            original = json.dumps({'plugins': [{'Id': module.PLUGIN_ID, 'Disabled': True}]})
            settings.write_text(original)
            manifest.write_text(json.dumps({'ID': module.PLUGIN_ID, 'Name': 'Everything', 'ExecuteFileName': 'EPT.dll'}))
            with self.assertRaises(ValueError): module.configure(settings, manifest)
            self.assertEqual(settings.read_text(), original)
            (root / 'EPT.dll').write_bytes(b'fixture')
            module.configure(settings, manifest)
            self.assertFalse(json.loads(settings.read_text())['plugins'][0]['Disabled'])
            self.assertEqual((root / 'settings.json.pc-setup.bak').read_text(), original)

    def test_installer_uses_documented_packages_and_no_force_close(self):
        script = (ROOT / 'Install-Everything.ps1').read_text()
        self.assertIn('voidtools.Everything', script)
        self.assertIn('lin-ycv.EverythingPowerToys', script)
        self.assertIn('--no-upgrade', script)
        self.assertNotIn('Stop-Process', script)
        self.assertNotIn('taskkill', script)
        desktop = (ROOT / 'Configure-Desktop.ps1').read_text()
        self.assertLess(desktop.index("'Install-Everything.ps1'"), desktop.rindex('Start-Process -FilePath $runner'))


if __name__ == '__main__': unittest.main()
