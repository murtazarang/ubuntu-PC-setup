"""Check Windows documentation and fresh/migration boundaries."""
from pathlib import Path
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

    def test_fresh_windows_runs_only_new_text_stack(self):
        setup = (ROOT / 'windows/Setup.ps1').read_text()
        self.assertIn('Install-HermesLocalAI.ps1', setup)
        for old in ('Install-Colibri.ps1', 'Install-OpenWebUI.ps1', 'Install-OMP.ps1',
                    'Migrate-ExistingAI.ps1', 'Remove-LegacyAI.ps1'):
            self.assertNotIn(old, setup)

    def test_daily_shortcuts_are_documented(self):
        installer = (ROOT / 'windows/Install-HermesLocalAI.ps1').read_text()
        docs = (ROOT / 'windows/README.md').read_text()
        for name in ('Start Local AI', 'Stop Local AI'):
            self.assertIn(f"'{name}'", installer)
            self.assertIn(f'**{name}**', docs)
        self.assertIn('Hermes Agent + llama.cpp', docs)
        self.assertIn('-ArchiveDirectory', docs)
        self.assertNotIn('Finish Open WebUI Setup', docs)

    def test_migration_documents_separate_path(self):
        guide = (ROOT / 'windows/README.md').read_text()
        migration = (ROOT / 'windows/MIGRATE-AI.md').read_text()
        self.assertIn('(MIGRATE-AI.md)', guide)
        self.assertIn('Migrate-ExistingAI.ps1', migration)
        self.assertIn('migrate-ai.ps1', migration)
        self.assertIn('Wikipedia', migration)


if __name__ == '__main__':
    unittest.main()
