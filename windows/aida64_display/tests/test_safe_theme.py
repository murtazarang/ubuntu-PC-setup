import tempfile
from pathlib import Path
import sys
import unittest
import yaml
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from safe_theme import validate_theme

class ThemeTests(unittest.TestCase):
    def test_default(self):
        validate_theme(Path(__file__).resolve().parents[1] / 'portrait.yaml')
    def test_reject_external_features(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'theme.yaml'
            for widget in ({'type':'image','path':r'\\server\secret'},
                           {'type':'slideshow','folder':'C:\\'},
                           {'type':'agenda'},
                           {'type':'text','font':r'\\server\font.ttf'},
                           {'type':'text','size':999999}):
                path.write_text(yaml.safe_dump({'size':[320,480],'widgets':[widget]}))
                with self.assertRaises(ValueError): validate_theme(path)

if __name__=='__main__': unittest.main()
