import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('retire_legacy_text', ROOT/'retire-legacy-text.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LegacyTextRetireTests(unittest.TestCase):
    def test_decline_keeps_shortcut_and_never_stops(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            desktop = home/'Desktop'
            desktop.mkdir()
            old = desktop/'Colibri Serve.desktop'
            old.write_text('[Desktop Entry]\nName=Colibri Serve\nExec=/usr/bin/systemctl --user start pc-setup-colibri-serve.service\nX-PC-Setup-Colibri=true\n')
            with patch.object(MODULE.Path, 'home', return_value=home), patch.dict(MODULE.os.environ, {}, clear=True), patch('builtins.input', return_value=''), patch.object(MODULE.subprocess,'check_output',return_value=str(desktop)), patch.object(MODULE.subprocess,'run') as run:
                MODULE.main()
                run.assert_not_called()
            self.assertTrue(old.is_file())

    def test_preserves_image_and_custom_launcher(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            desktop = home/'Desktop'
            desktop.mkdir()
            text = desktop/'Colibri Serve.desktop'
            image = desktop/'Colibri Serve Image.desktop'
            custom = desktop/'Open WebUI.desktop'
            planted='[Desktop Entry]\nName=Colibri Serve\nExec=/usr/bin/systemctl --user start pc-setup-colibri-serve.service\nX-PC-Setup-Colibri=true\n'
            text.write_text(planted)
            image.write_text('image remains')
            custom.write_text('custom remains')
            with patch.object(MODULE.Path,'home',return_value=home), patch.dict(MODULE.os.environ,{},clear=True), patch('builtins.input',return_value='RETIRE TEXT'), patch.object(MODULE.subprocess,'check_output',return_value=str(desktop)), patch.object(MODULE.subprocess,'run') as run:
                MODULE.main()
                run.assert_not_called()
            self.assertFalse(text.exists())
            backup=next((home/'.local/share/pc-setup-openwebui/retired-shortcuts').glob('*/0/*.desktop'))
            self.assertEqual(backup.read_text(),planted)
            self.assertEqual(image.read_text(),'image remains')
            self.assertEqual(custom.read_text(),'custom remains')

    def test_rejects_live_override(self):
        path=Path('/home/test/.config/systemd/user/pc-setup-openwebui.service')
        with patch.object(MODULE.subprocess,'run') as run:
            run.return_value.stdout='FragmentPath='+str(path)+'\nDropInPaths=/home/test/custom.conf\n'
            with self.assertRaisesRegex(ValueError,'custom drop-ins'):
                MODULE.loaded_unit(path)


if __name__=='__main__':
    unittest.main()
