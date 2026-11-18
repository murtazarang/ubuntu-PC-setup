import importlib.util
import json
import os
import stat
import subprocess
from types import SimpleNamespace
from unittest.mock import patch
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('inventory',Path(__file__).resolve().parents[1]/'inventory_old_omp_skills.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class InventoryTests(unittest.TestCase):
    def test_reparse_attribute_blocks_before_walk_or_read(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'.omp';root.mkdir()
            actual=Path.lstat
            def fake(path, *args, **kwargs):
                if path == root:
                    return SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=stat.FILE_ATTRIBUTE_REPARSE_POINT)
                return actual(path, *args, **kwargs)
            with patch.object(Path, 'lstat', fake), patch.object(module.os, 'walk') as walk:
                with self.assertRaises(ValueError):module.inventory(root)
                walk.assert_not_called()
    def test_reparse_child_blocks_before_config_read(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);child=root/'agent';child.mkdir()
            (child/'config.yml').write_text('skills: {}')
            actual=Path.lstat
            def fake(path, *args, **kwargs):
                if path == child:
                    return SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=stat.FILE_ATTRIBUTE_REPARSE_POINT)
                return actual(path, *args, **kwargs)
            with patch.object(Path, 'lstat', fake), patch.object(module.yaml, 'safe_load') as read:
                with self.assertRaises(ValueError):module.inventory(root)
                read.assert_not_called()
    @unittest.skipUnless(os.name == 'nt', 'Requires real Windows junction')
    def test_windows_junction_never_reads_external_config(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'.omp';root.mkdir();outside=Path(temp)/'outside';outside.mkdir()
            (outside/'config.yml').write_text('skills: {}')
            link=root/'agent'
            subprocess.run(['cmd.exe','/d','/c','mklink','/J',str(link),str(outside)],check=True,capture_output=True)
            try:
                with patch.object(module.yaml, 'safe_load') as read:
                    with self.assertRaises(ValueError):module.inventory(root)
                    read.assert_not_called()
            finally:
                link.rmdir()  # Remove only disposable junction, not its target.
    def test_all_profiles_and_json_yaml(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'.omp';a=root/'agent';b=root/'profiles'/'other'/'agent'
            a.mkdir(parents=True);b.mkdir(parents=True)
            one=str(Path(temp)/'one');two=str(Path(temp)/'two')
            (a/'config.yml').write_text('skills:\n  customDirectories:\n    - '+json.dumps(one)+'\n')
            (b/'settings.json').write_text(json.dumps({'skills.customDirectories':[two]}))
            result=module.inventory(root)
            self.assertEqual(set(result['custom_roots']),{one,two})
            self.assertEqual(len(result['config_files']),2)
    def test_bad_schema_stops(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'config.yml').write_text('skills:\n  customDirectories: not-a-list\n')
            with self.assertRaises(ValueError):module.inventory(root)
    def test_relative_reference_stops(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'settings.json').write_text('{"skills":{"customDirectories":["../shared"]}}')
            with self.assertRaises(ValueError):module.inventory(root)
    def test_missing_runtime_root_is_empty(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertEqual(module.inventory(Path(temp)/'missing')['custom_roots'],[])
if __name__=='__main__':unittest.main()
