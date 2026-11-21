import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('hermes_config', ROOT / 'local_ai/hermes_config.py')
hc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hc)


class ConfigTests(unittest.TestCase):
    def test_local_config_preserves_unrelated(self):
        old = {'display': {'theme': 'dark'}, 'model': {'temperature': 0.4}}
        new = hc.config_update(old, 'qwen-local', 131072, {'command': 'bridge'}, ['vision', 'compression'])
        self.assertEqual(new['display'], old['display'])
        self.assertEqual(new['model']['temperature'], .4)
        self.assertEqual(new['model']['provider'], 'llamacpp')
        self.assertEqual(new['model']['base_url'], 'http://127.0.0.1:8081/v1')
        self.assertEqual(new['auxiliary']['vision']['base_url'], hc.BASE_URL)
        self.assertTrue(new['webapp']['enabled'])
        self.assertEqual(new['webapp']['host'], '127.0.0.1')
        self.assertEqual(new['fallback_providers'], [])
        self.assertNotIn('web', new['platform_toolsets']['cli'])
        self.assertIn('mcp-openzim', new['platform_toolsets']['cli'])
        self.assertNotIn('auxiliary', old)

    def test_dual_context(self):
        self.assertEqual(hc.config_update({}, 'qwen-local', 262144, {})['model']['context_length'], 262144)
        with self.assertRaises(ValueError): hc.config_update({}, 'x', 8192, {})

    def test_other_mcp_preserved_on_refusal(self):
        old = {'mcp_servers': {'cloud': {'url': 'https://example.org'}}}
        with self.assertRaises(ValueError): hc.config_update(old, 'x', 131072, {})
        self.assertNotIn('openzim', old['mcp_servers'])

    def test_reference_checksum_and_direct_stdio(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / 'wikipedia.zim'; archive.write_bytes(b'archive fixture')
            bridge = root / 'openzim-mcp'; bridge.write_text('not executed')
            manifest = root / 'reference.json'
            manifest.write_text(json.dumps({'archive': str(archive), 'bridge': str(bridge),
                'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}))
            config = hc.verify_reference(manifest)
            self.assertEqual(config['command'], str(bridge))
            self.assertEqual(config['args'], [str(root)])
            self.assertFalse(config['sampling']['enabled'])
            archive.write_bytes(b'changed')
            with self.assertRaises(ValueError): hc.verify_reference(manifest)

    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root / 'target').mkdir()
            try: (root / 'link').symlink_to(root / 'target', target_is_directory=True)
            except OSError: self.skipTest('symlink unavailable')
            with self.assertRaises(ValueError): hc.no_links(root / 'link' / 'child')

    def test_atomic_text_and_all_assets(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hc.atomic_text(root / 'SKILL.md', 'skill\n')
            (root / 'asset.bin').write_bytes(b'\0\xff')
            self.assertEqual(set(hc.digest_tree(root)), {'SKILL.md', 'asset.bin'})


@unittest.skipUnless(os.environ.get('HERMES_SOURCE'), 'Set HERMES_SOURCE to audited v0.23.3 checkout')
class NativeCatalogTests(unittest.TestCase):
    def test_actual_hermes_duplicates_have_exact_aliases(self):
        util = hc.hermes_utils(Path(os.environ['HERMES_SOURCE']))
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name, body in [('repo-a', 'one'), ('repo-b', 'two')]:
                package = root / name
                package.mkdir()
                (package / 'SKILL.md').write_text('---\nname: shared-name\ndescription: example\n---\n' + body)
            rows = hc.catalog(root, util)
            self.assertEqual({r['load_name'] for r in rows}, {'repo-a', 'repo-b'})
            self.assertTrue(all(r['status'] == 'ambiguous' and r['visible'] for r in rows))

    @unittest.skipUnless(os.environ.get('HERMES_SKILL_REPOS'), 'Set HERMES_SKILL_REPOS to all three pinned repos')
    def test_complete_pinned_inventory(self):
        packages = hc.source_inventory(Path(os.environ['HERMES_SKILL_REPOS']))
        self.assertEqual(len(packages), 422)
        self.assertEqual(sum(len(p['files']) for p in packages), 3968)


if __name__ == '__main__': unittest.main()
