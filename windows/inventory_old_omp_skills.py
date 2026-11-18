"""Read all owned OMP profile settings, without running OMP or any skill code."""
import argparse
import json
import os
import stat
from pathlib import Path

import yaml

NAMES = {'config.yml', 'config.yaml', 'config.json', 'settings.yml', 'settings.yaml', 'settings.json'}


def reject_link(path):
    try:
        info = path.lstat()  # Never follow a Windows junction to inspect its target.
    except FileNotFoundError:
        return
    if (stat.S_ISLNK(info.st_mode) or
            getattr(info, 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT):
        raise ValueError(f'Linked old OMP state needs manual ownership review: {path}')


def inventory(root):
    result = {'config_files': [], 'custom_roots': []}
    for ancestor in reversed((root, *root.parents)):
        reject_link(ancestor)
    if not root.exists():
        return result
    for current, directories, files in os.walk(root, followlinks=False):
        base = Path(current)
        for name in directories + files:
            item = base / name
            reject_link(item)  # All entries checked before os.walk can descend.
        for name in files:
            if name not in NAMES:
                continue
            path = base / name
            relative = path.relative_to(root).parts
            owned_settings = (len(relative) == 1 or
                              (len(relative) == 2 and relative[0] == 'agent') or
                              (len(relative) == 3 and relative[0] == 'profiles') or
                              (len(relative) == 4 and relative[0] == 'profiles' and relative[2] == 'agent'))
            if not owned_settings:
                continue  # Plugin/model payload config.json files are not OMP settings.
            data = yaml.safe_load(path.read_text(encoding='utf-8-sig'))
            if data is None:
                data = {}
            if not isinstance(data, dict):
                raise ValueError(f'OMP configuration is not a mapping: {path}')
            result['config_files'].append(str(path))
            values = []
            if 'skills.customDirectories' in data:
                values.append(data['skills.customDirectories'])
            if 'skills' in data:
                if not isinstance(data['skills'], dict):
                    raise ValueError(f'Unknown skills configuration schema: {path}')
                if 'customDirectories' in data['skills']:
                    values.append(data['skills']['customDirectories'])
            for value in values:
                if value is None:
                    continue
                if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
                    raise ValueError(f'Unknown customDirectories format: {path}')
                for item in value:
                    expanded = os.path.expandvars(os.path.expanduser(item))
                    if not os.path.isabs(expanded):
                        raise ValueError(f'Relative custom skill path needs review: {item} ({path})')
                    normalized = os.path.abspath(expanded)
                    if normalized not in result['custom_roots']:
                        result['custom_roots'].append(normalized)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(inventory(args.root)))
