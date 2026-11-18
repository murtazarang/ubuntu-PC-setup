"""Reject tracked paths that cannot coexist on a case-insensitive Windows filesystem."""
from pathlib import Path, PurePosixPath
import subprocess
import unittest


def collisions(paths):
    seen = {}
    errors = set()
    for path in paths:
        # Check directory prefixes too: Foo/a and foo/b must not share an
        # accidentally differently-cased directory on Windows.
        parts = PurePosixPath(path).parts
        for length in range(1, len(parts) + 1):
            prefix = '/'.join(parts[:length])
            key = prefix.casefold()
            previous = seen.setdefault(key, prefix)
            if previous != prefix:
                errors.add(tuple(sorted((previous, prefix))))
    return sorted(errors)


class WindowsPathTests(unittest.TestCase):
    def test_tracked_repository_paths_are_case_unique(self):
        root = Path(__file__).resolve().parents[2]
        paths = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
        self.assertEqual(collisions(filter(None, paths)), [], 'Case-colliding files cannot safely check out on Windows')

    def test_launcher_and_worker_collision_is_detected(self):
        self.assertTrue(collisions(['windows/Migrate-AI.ps1', 'windows/migrate-ai.ps1']))
        self.assertFalse(collisions(['windows/Migrate-ExistingAI.ps1', 'windows/migrate-ai.ps1']))

    def test_directory_alias_is_detected(self):
        self.assertTrue(collisions(['windows/Helpers/a.py', 'windows/helpers/b.py']))


if __name__ == '__main__':
    unittest.main()
