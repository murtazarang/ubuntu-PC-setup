"""Exercise the embedded no-console helper without sensors or scheduled tasks."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / 'autostart.ps1'


class RunnerTests(unittest.TestCase):
    def test_logging_and_arguments(self):
        code = SOURCE.read_text().split("$runnerText = @'\n", 1)[1].split("\n'@", 1)[0]
        with tempfile.TemporaryDirectory(prefix='AX206 space ') as tmp:
            base = Path(tmp)
            runner = base / 'autostart_runner.py'
            runner.write_text(code)
            (base / 'panel.py').write_text(
                'import sys\nassert sys.argv[1:] == ["--rotation", "270"]\nprint("panel started")\n')
            result = subprocess.run([sys.executable, str(runner), '--rotation', '270'], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('panel started', (base / 'autostart.log').read_text())
            (base / 'panel.py').write_text('raise RuntimeError("sensor failure")\n')
            result = subprocess.run([sys.executable, str(runner)], capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('sensor failure', (base / 'autostart.log').read_text())
            (base / 'autostart.log').write_text('x' * 2_000_001)
            subprocess.run([sys.executable, str(runner)], check=False)
            self.assertEqual((base / 'autostart.previous.log').stat().st_size, 2_000_001)


if __name__ == '__main__':
    unittest.main()
