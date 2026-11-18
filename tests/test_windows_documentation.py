"""Guard the Windows user instructions against obsolete AI workflow claims."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

class WindowsDocumentationTests(unittest.TestCase):
    def test_repository_paths_do_not_collide_on_windows(self):
        paths = subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines()
        folded = {}
        for path in paths:
            key = path.casefold()
            self.assertNotIn(key, folded, f'Windows filename collision: {folded.get(key)} / {path}')
            folded[key] = path

    def test_every_installed_shortcut_is_documented(self):
        installer = (ROOT / 'windows/Install-OpenWebUI.ps1').read_text()
        names = re.findall(r"@\{name='([^']+)'", installer)
        self.assertEqual(len(names), 4)
        names.append('Finish Open WebUI Setup')
        for document in ('README.md', 'OPENWEBUI.md'):
            text = (ROOT / 'windows' / document).read_text()
            for name in names:
                self.assertIn(f'**{name}**', text)

    def test_current_stack_and_cleanup_boundary(self):
        readme = (ROOT / 'windows/README.md').read_text()
        self.assertIn('Colibri inference + Open WebUI', readme)
        self.assertIn('four daily-use shortcuts and one first-use setup shortcut', readme)
        self.assertIn('No model terminal needs to stay open', readme)
        for obsolete in ('Oh My Pi is configured', 'coli ui', 'coli web', 'exactly two', 'Connect-LocalModel.ps1'):
            self.assertNotIn(obsolete, readme)
        for name in ('README.md', 'OPENWEBUI.md'):
            text = (ROOT / 'windows' / name).read_text()
            self.assertIn('Finish Open WebUI Setup', text)
            self.assertIn('confirmation', text.lower())
            self.assertIn('migration', text.lower())
            self.assertIn('preserved', text)

    def test_direct_finish_command_matches_installer(self):
        command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\\OpenWebUI-PC-Setup\\Finish-OpenWebUI.ps1" -Root "$env:LOCALAPPDATA\\OpenWebUI-PC-Setup"'
        for name in ('README.md', 'OPENWEBUI.md'):
            self.assertIn(command, (ROOT / 'windows' / name).read_text())
        installer = (ROOT / 'windows/Install-OpenWebUI.ps1').read_text()
        self.assertIn('-NoProfile -ExecutionPolicy Bypass -File', installer)
        self.assertIn('Finish-OpenWebUI.ps1', installer)
        setup = (ROOT / 'windows/Setup.ps1').read_text()
        self.assertIn('-NoShortcut', setup)
        self.assertNotIn("'Install-OMP.ps1'", setup)
        finish = (ROOT / 'windows/Finish-OpenWebUI.ps1').read_text()
        self.assertNotIn('Remove-VerifiedOMP', finish)
        installer = (ROOT / 'windows/Install-OpenWebUI.ps1').read_text()
        self.assertNotIn("'Remove-VerifiedOMP.ps1'", installer)

if __name__ == '__main__':
    unittest.main()
