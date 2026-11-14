"""Validate installed EPT files and enable its existing settings without replacing others."""
import argparse
import copy
import json
from pathlib import Path
from configure_powertoys import save

PLUGIN_ID = 'A86867E2D932459CBD77D176373DD657'


def enabled(data):
    data = copy.deepcopy(data)
    if not isinstance(data, dict) or not isinstance(data.get('plugins', []), list):
        raise ValueError('Invalid PowerToys Run settings')
    matches = []
    for plugin in data.get('plugins', []):
        if not isinstance(plugin, dict):
            raise ValueError('Invalid PowerToys Run plugin settings')
        if plugin.get('Id', '').upper() == PLUGIN_ID:
            matches.append(plugin)
    if len(matches) > 1:
        raise ValueError('Duplicate Everything plugin settings; inspect before retrying')
    if matches:
        matches[0]['Disabled'] = False
    # Newly discovered plugins inherit plugin.json's defaults. Do not create an
    # incomplete settings entry that would suppress those upstream defaults.
    return data


def configure(settings, manifest):
    metadata = json.loads(manifest.read_text(encoding='utf-8-sig'))
    if metadata.get('ID') != PLUGIN_ID or metadata.get('Name') != 'Everything':
        raise ValueError('Unexpected Everything plugin identity')
    dll = metadata.get('ExecuteFileName')
    if not isinstance(dll, str) or Path(dll).name != dll or not (manifest.parent / dll).is_file():
        raise ValueError('Everything plugin DLL is missing or invalid')
    if not settings.exists():
        raise ValueError('PowerToys Run settings are missing; initialize PowerToys first')
    original = json.loads(settings.read_text(encoding='utf-8-sig'))
    result = enabled(original)
    if result != original:
        save(settings, result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--settings', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    args = parser.parse_args()
    configure(args.settings, args.manifest)
