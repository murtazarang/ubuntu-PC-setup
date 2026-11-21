"""Non-destructive tests for local AI launcher wiring."""
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'local_ai'))
import local_setup


def response(data):
    return io.BytesIO(json.dumps(data).encode())


class LauncherTests(unittest.TestCase):
    def test_verify_rejects_short_context_and_multiple_slots(self):
        models = {'data': [{'id': 'qwen-flash-next'}]}
        def check(n_ctx, slots):
            props = {'total_slots': slots, 'default_generation_settings': {'n_ctx': n_ctx},
                     'chat_template': 'built-in'}
            with patch.object(local_setup, 'urlopen', side_effect=[response(models), response(props)]):
                local_setup.check_endpoint('qwen-flash-next', 262144)
        check(262144, 1)
        for args in ((131072, 1), (262144, 2)):
            with self.assertRaises(RuntimeError):
                check(*args)

    def test_refuse_non_owned_hermes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            binary = root / 'unrelated'
            binary.touch()
            with self.assertRaises(ValueError):
                local_setup.launcher(root, binary)

    def test_existing_json_is_replaced_and_no_stale_temp(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / 'desktop.json'
            local_setup.write_record(path, {'v': 1})
            local_setup.write_record(path, {'v': 2})
            self.assertEqual(json.loads(path.read_text()), {'v': 2})
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_unrelated_linux_shortcut_preserved(self):
        with tempfile.TemporaryDirectory() as td, patch.dict(os.environ, {'XDG_DATA_HOME': td}):
            path = Path(td) / 'applications' / 'pc-setup-hermes-start.desktop'
            path.parent.mkdir()
            path.write_text('User file', encoding='utf-8')
            with self.assertRaises(ValueError):
                local_setup.shortcuts(Path(td), 'Intel')
            self.assertEqual(path.read_text(encoding='utf-8'), 'User file')


if __name__ == '__main__':
    unittest.main()
