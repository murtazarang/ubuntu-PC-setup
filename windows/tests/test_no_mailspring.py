from pathlib import Path
import unittest

class WindowsAppsTest(unittest.TestCase):
    def test_mailspring_not_installed(self):
        installer = (Path(__file__).resolve().parent.parent / "Install-Apps.ps1").read_text(encoding="utf-8")
        self.assertNotIn("mailspring", installer.lower())

if __name__ == "__main__":
    unittest.main()
