import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('apply_firefox_policy', Path(__file__).resolve().parents[1] / 'apply_firefox_policy.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ExistingProfilesTests(unittest.TestCase):
    def test_relative_profile_blocks_destructive_initial_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profile = root / 'Profiles' / 'example'
            profile.mkdir(parents=True)
            ini = root / 'profiles.ini'
            ini.write_text('[Profile0]\nPath=Profiles/example\nIsRelative=1\n')
            (profile / 'extensions.json').write_text(json.dumps({'addons': [{'id': 'uBlock0@raymondhill.net'}]}))
            policy = root / 'policies.json'
            original = '{"policies":{"Homepage":{"URL":"https://example.org"}}}'
            policy.write_text(original)
            with self.assertRaisesRegex(RuntimeError, 'Existing uBlock profile'):
                module.merge(policy, profiles_ini=ini)
            self.assertEqual(policy.read_text(), original)

    def test_absolute_profile_xpi_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profile = root / 'custom'
            (profile / 'extensions').mkdir(parents=True)
            (profile / 'extensions' / 'uBlock0@raymondhill.net.xpi').touch()
            ini = root / 'profiles.ini'
            ini.write_text('[Profile0]\nPath=' + str(profile) + '\nIsRelative=0\n')
            self.assertTrue(module.existing_ublock(ini))

    def test_release_refuses_unrelated_managed_filters(self):
        with tempfile.TemporaryDirectory() as tmp:
            policy = Path(tmp) / 'policies.json'
            original = json.dumps({'policies': {'3rdparty': {'Extensions': {'uBlock0@raymondhill.net': {'toOverwrite': {'filters': ['my-existing-rule']}}}}}})
            policy.write_text(original)
            with self.assertRaises(RuntimeError): module.merge(policy, release=True)
            self.assertEqual(policy.read_text(), original)

    def test_previous_setup_list_set_is_recognized(self):
        with tempfile.TemporaryDirectory() as tmp:
            policy = Path(tmp) / 'policies.json'
            module.merge(policy)
            data = json.loads(policy.read_text())
            data['policies']['3rdparty']['Extensions']['uBlock0@raymondhill.net']['toOverwrite']['filterLists'].append('ublock-abuse')
            policy.write_text(json.dumps(data))
            module.merge(policy, release=True)
            self.assertNotIn('toOverwrite', json.loads(policy.read_text())['policies']['3rdparty']['Extensions']['uBlock0@raymondhill.net'])

    def test_fresh_profile_allows_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            module.merge(root / 'policies.json', profiles_ini=root / 'missing.ini')
            self.assertIn('ExtensionSettings', json.loads((root / 'policies.json').read_text())['policies'])

if __name__ == '__main__': unittest.main()
