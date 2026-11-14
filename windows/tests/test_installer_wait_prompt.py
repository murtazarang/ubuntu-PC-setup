import pathlib
import unittest

class InstallerWaitPrompt(unittest.TestCase):
    def test_guidance_precedes_process_tree_wait(self):
        source = (pathlib.Path(__file__).resolve().parents[1] / 'Install-Apps.ps1').read_text()
        launch = source.index('$p = Start-Process -FilePath $file -Wait -PassThru')
        self.assertLess(source.index('Uncheck Launch at the end if offered.'), launch)
        self.assertLess(source.index('close that app to continue.'), launch)

if __name__ == '__main__':
    unittest.main()
