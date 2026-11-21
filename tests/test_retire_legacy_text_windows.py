import importlib.util
from pathlib import Path
import json
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch, Mock


ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('retire_legacy_text_windows',ROOT/'windows/retire_legacy_text_windows.py')
MODULE=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WindowsRetireTests(unittest.TestCase):
    def fixture(self,root,kind,command=None):
        config=dict(coli_python='C:/old/bin/python.exe',coli='C:/old/coli',text_model='C:/models/text')
        expectation=[config['coli_python'],config['coli'],'serve','--host','127.0.0.1',
                     '--port','8000','--model',config['text_model']]
        record=dict(model=dict(kind=kind,command=expectation if command is None else command),webui={'pid':3},wikipedia={'pid':4})
        (root/'desktop.json').write_text(json.dumps(config))
        (root/'processes.json').write_text(json.dumps(record))
        return record

    def run_with_fake_old_helpers(self,root,expected_error=None):
        stop=Mock()
        external=SimpleNamespace(LK_NBLCK=1,locking=Mock())
        proc=SimpleNamespace(username=lambda: 'Alice')
        fake=SimpleNamespace(loader=SimpleNamespace(exec_module=lambda _module:None))
        legacy=SimpleNamespace(owned_process=lambda rec:proc,stop_record=stop,
                               psutil=SimpleNamespace(Process=lambda:proc))
        with patch.dict(sys.modules,{'msvcrt':external}), patch.object(MODULE.importlib.util,'spec_from_file_location',return_value=fake),patch.object(MODULE.importlib.util,'module_from_spec',return_value=legacy):
            if expected_error:
                with self.assertRaisesRegex(ValueError,expected_error):
                    MODULE.retire(root)
            else:
                MODULE.retire(root)
        return stop

    def test_stops_only_matching_text(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            record=self.fixture(root,'text')
            self.run_with_fake_old_helpers(root).assert_called_once_with(record.pop('model'))
            self.assertEqual(json.loads((root/'processes.json').read_text()),record)

    def test_does_not_stop_image_or_its_frontend(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            record=self.fixture(root,'image')
            self.run_with_fake_old_helpers(root).assert_not_called()
            self.assertEqual(json.loads((root/'processes.json').read_text()),record)

    def test_mismatched_command_preserved(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            record=self.fixture(root,'text',['C:/user-tool.exe'])
            self.run_with_fake_old_helpers(root,'Unrecognized recorded Colibri text process').assert_not_called()
            self.assertEqual(json.loads((root/'processes.json').read_text()),record)


if __name__=='__main__':
    unittest.main()
