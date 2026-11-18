#!/usr/bin/env python3
"""Remove only the former setup's exact OMP provider shape; preserve all other data."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import os
import yaml


def legacy_provider(entry):
    if not isinstance(entry, dict):
        return False
    for port in (8080, 8095):
        models = entry.get('models')
        if not isinstance(models, list) or len(models) != 1 or not isinstance(models[0], dict):
            continue
        model = models[0].get('id')
        if not isinstance(model, str) or not model:
            continue
        expected = {'baseUrl': f'http://127.0.0.1:{port}/v1', 'api': 'openai-completions',
                    'auth': 'none', 'compat': {'supportsDeveloperRole': False},
                    'models': [{'id': model, 'name': 'Local ' + model, 'reasoning': True,
                                'input': ['text'], 'contextWindow': 32768, 'maxTokens': 4096,
                                'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}}]}
        if entry == expected:
            return True
    return False


def clean_models(data):
    if not isinstance(data, dict) or not isinstance(data.get('providers', {}), dict):
        raise ValueError('Models configuration is not a mapping')
    providers = data.get('providers', {})
    if not legacy_provider(providers.get('local-inference')):
        return False
    del providers['local-inference']
    return True


def clean_roles(roles, expected_selector):
    if not isinstance(roles, dict):
        raise ValueError('Global model roles are not a mapping')
    return {k: v for k, v in roles.items() if not (isinstance(v, str) and v == expected_selector)}


def run(omp, *args):
    return subprocess.check_output([omp, 'config', *args], text=True).strip()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--omp', required=True)
    p.add_argument('--backup', required=True, type=Path)
    args = p.parse_args()
    root = Path(run(args.omp, 'path'))
    files = [root / name for name in ('models.yml', 'models.yaml', 'models.json')]
    # Same precedence as the old setup/OMP; don't activate or overwrite a dormant config.
    path = next((f for f in files if f.exists()), None)
    if path is None:
        print('No OMP model configuration to clean.'); return
    original = path.read_text(encoding='utf-8-sig')
    data = json.loads(original) if path.suffix == '.json' else yaml.safe_load(original)
    if data is None: data = {}
    # Capture only the selector proved by the exact former provider shape.
    provider = data.get('providers', {}).get('local-inference') if isinstance(data, dict) and isinstance(data.get('providers', {}), dict) else None
    expected_selector = 'local-inference/' + provider['models'][0]['id'] if legacy_provider(provider) else None
    if not clean_models(data):
        print('OMP local-inference absent or customized; retained.'); return
    global_settings = json.loads(run(args.omp, 'list', '--scope', 'global', '--json'))
    if not isinstance(global_settings, dict): raise ValueError('Invalid global settings')
    record = global_settings.get('modelRoles', {'value': {}})
    if not isinstance(record, dict): raise ValueError('Invalid modelRoles record')
    roles = record.get('value', {})
    cleaned = clean_roles(roles, expected_selector)
    args.backup.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, args.backup / path.name)
    (args.backup / 'modelRoles.json').write_text(json.dumps(roles, indent=2), encoding='utf-8')
    content = json.dumps(data, indent=2) + '\n' if path.suffix == '.json' else yaml.safe_dump(data, sort_keys=False)
    fd, name = tempfile.mkstemp(prefix='.models-cleanup-', dir=path.parent)
    roles_attempted = False
    try:
        # Stage the complete replacement before touching global settings. A
        # permission/disk error here must leave both live configurations intact.
        with os.fdopen(fd, 'w', encoding='utf-8') as f: f.write(content)
        if cleaned != roles:
            roles_attempted = True
            run(args.omp, 'set', 'modelRoles', json.dumps(cleaned))
        os.replace(name, path)
    except Exception:
        if roles_attempted:
            # Even a failed CLI can have partially persisted its change.
            # Restore the saved layer; never read effective project overrides.
            run(args.omp, 'set', 'modelRoles', json.dumps(roles))
        raise
    finally:
        if os.path.exists(name): os.unlink(name)
    print('Removed former setup OMP provider and matching global roles; other settings preserved.')

if __name__ == '__main__': main()
