"""Static regression checks for progress immediately before silent operations."""
from pathlib import Path
import unittest


class ReferenceProgressTests(unittest.TestCase):
    def test_progress_precedes_each_silent_operation(self):
        lines = (Path(__file__).resolve().parents[1] / 'Install-Reference.ps1').read_text().splitlines()
        expected = {
            '& $bridge --help | Out-Null': 'Checking OpenZIM MCP startup',
            '$agentDir = (& $omp config path | Out-String).Trim()': 'Locating Oh My Pi configuration',
            '& curl.exe --fail --location --retry 3 --output $checksum': 'Fetching the official Wikipedia SHA-256',
            'if ((Get-FileHash -LiteralPath $part -Algorithm SHA256)': 'Verifying the downloaded Wikipedia archive',
            'if ((Get-FileHash -LiteralPath $final -Algorithm SHA256)': 'Verifying the existing Wikipedia archive',
        }
        for operation, message in expected.items():
            with self.subTest(operation=operation):
                indexes = [i for i, line in enumerate(lines) if line.strip().startswith(operation)]
                self.assertEqual(len(indexes), 1)
                previous = lines[indexes[0] - 1].strip()
                self.assertTrue(previous.startswith('Write-Host '))
                self.assertIn(message, previous)


if __name__ == '__main__':
    unittest.main()
