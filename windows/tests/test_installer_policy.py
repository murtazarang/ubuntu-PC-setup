import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class InstallerPolicyTests(unittest.TestCase):
    def test_winget_install_does_not_upgrade_existing_apps(self):
        for name in ('Install-Apps.ps1', 'Bootstrap.ps1'):
            text = (ROOT / name).read_text(encoding='utf-8')
            self.assertIn('--no-upgrade', text)
            self.assertIn('0x8A150061', text)
            self.assertIn('0x8A15010D', text)

    def test_requested_installers_and_no_pinned_driver(self):
        apps = (ROOT / 'Install-Apps.ps1').read_text(encoding='utf-8')
        drivers = (ROOT / 'Install-Drivers.ps1').read_text(encoding='utf-8')
        self.assertNotIn('FanControl_285_net_4_8_Installer.exe', apps)
        self.assertIn('https://release.signalrgb.com/Install_SignalRgb.exe', apps)
        self.assertIn('NVIDIA App', drivers)
        self.assertIn('Intel Driver & Support Assistant', drivers)
        self.assertNotIn('621.24-desktop', drivers)
        self.assertNotIn('gfx_win_101.9175.exe', drivers)

if __name__ == '__main__':
    unittest.main()

class LauncherTests(unittest.TestCase):
    def test_launcher_fetches_archive_without_needing_git(self):
        text = (ROOT / 'run.ps1').read_text(encoding='utf-8')
        self.assertIn('archive/refs/heads/main.zip', text)
        self.assertIn('NvidiaSingle', text)
        self.assertIn('NvidiaDual', text)
        self.assertIn('Intel', text)
        self.assertIn("'Drivers'", text)
        self.assertIn("'Desktop'", text)
        self.assertNotIn('git clone', text)
