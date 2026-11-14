#!/usr/bin/env python3
"""Targeted PowerToys settings merge; invoke only after PowerToys exits.

Schema: microsoft/PowerToys src/settings-ui/Settings.UI.Library/
GeneralSettings.cs, EnabledModules.cs, PowerLauncherProperties.cs.
PowerLauncher is explicitly excluded from PowerToys DSC SettingsResource.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import tempfile


def merged(general, launcher):
    general, launcher = copy.deepcopy(general), copy.deepcopy(launcher)
    if not isinstance(general, dict) or not isinstance(launcher, dict):
        raise ValueError('PowerToys settings must be JSON objects')
    enabled = general.setdefault('enabled', {})
    properties = launcher.setdefault('properties', {})
    if not isinstance(enabled, dict) or not isinstance(properties, dict):
        raise ValueError('Invalid PowerToys enabled/properties object')
    # Serialized JSON names differ from the .NET property PowerLauncher.
    enabled['PowerToys Run'] = True
    enabled['Awake'] = True
    properties['open_powerlauncher'] = {
        'win': True, 'alt': False, 'ctrl': False, 'shift': False, 'code': 113
    }
    launcher.setdefault('name', 'PowerToys Run')
    launcher.setdefault('version', '1.0')
    return general, launcher


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Keep an original backup; repeated runs don't replace that backup.
    backup = path.with_name(path.name + '.pc-setup.bak')
    if path.exists() and not backup.exists():
        backup.write_bytes(path.read_bytes())
    fd, temporary = tempfile.mkstemp(prefix='.pc-setup-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
            json.dump(data, stream, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configure(directory):
    general_path = directory / 'settings.json'
    launcher_path = directory / 'PowerToys Run' / 'settings.json'
    if not general_path.exists():
        raise ValueError('Start PowerToys once and then close it before configuring')
    general = json.loads(general_path.read_text(encoding='utf-8-sig'))
    launcher = json.loads(launcher_path.read_text(encoding='utf-8-sig')) if launcher_path.exists() else {}
    general, launcher = merged(general, launcher)
    save(general_path, general)
    save(launcher_path, launcher)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    configure(parser.parse_args().directory)
