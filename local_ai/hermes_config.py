#!/usr/bin/env python3
"""Configure an isolated Hermes v0.23.3 home; never edits the default home.

Requires PyYAML from Hermes's environment. Complete original skill checkouts stay
at --repos; native skill copies preserve every byte and executable mode. No skill
scripts are run and no optional cloud services are enabled. Downloads occur only
with the explicit prepare action. Runtime config uses only loopback inference.
"""
from __future__ import annotations
import argparse
from collections import Counter
import copy
import hashlib
import importlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

HERMES_COMMIT = 'caafe5389ae585ef77387a962aee05b1bcf17029'
BASE_URL = 'http://127.0.0.1:8081/v1'
REPOS = {
    'scientific-agent-skills': ('https://github.com/K-Dense-AI/scientific-agent-skills.git', 'ec59a29a03d5c40f73ab40878df04860bc00e876'),
    'claude-scientific-writer': ('https://github.com/K-Dense-AI/claude-scientific-writer.git', '9820740d252800ecf0b8fc066ffb5bf9659f4a51'),
    'education-agent-skills': ('https://github.com/GarethManning/education-agent-skills.git', '135d6275e7db0657d70b147f46d3191c5430677d'),
}
LOCAL_TOOLS = ['terminal', 'file', 'skills', 'todo', 'memory', 'session_search', 'mcp-openzim']


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


def no_links(path):
    for part in (path, *path.parents):
        try:
            st = part.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(st.st_mode) or getattr(st, 'st_file_attributes', 0) & 0x400:
            raise ValueError(f'Linked/reparse path refused: {part}')


def files(root):
    no_links(root)
    for current, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d != '.git')
        for name in dirs + names:
            no_links(Path(current) / name)
        for name in sorted(names):
            path = Path(current) / name
            if not path.is_file():
                raise ValueError(f'Nonregular file: {path}')
            yield path


def digest_tree(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files(root)}


def atomic_text(path, text):
    no_links(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.pc-setup-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
            stream.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def prepare(root):
    no_links(root)
    root.mkdir(parents=True, exist_ok=True)
    for name, (url, rev) in REPOS.items():
        dest = root / name
        if not dest.exists():
            subprocess.run(['git', 'clone', '--', url, str(dest)], check=True)
            subprocess.run(['git', '-C', str(dest), 'checkout', '--detach', rev], check=True)
    return source_inventory(root)


def source_inventory(root):
    packages = []
    for name, (url, rev) in REPOS.items():
        repo = root / name
        no_links(repo)
        if git(repo, 'remote', 'get-url', 'origin') != url or git(repo, 'rev-parse', 'HEAD') != rev:
            raise ValueError(f'Unexpected source/revision preserved: {repo}')
        if git(repo, 'status', '--porcelain'):
            raise ValueError(f'Changed skill checkout preserved: {repo}')
        sparse = subprocess.run(['git', '-C', str(repo), 'config', '--get', 'core.sparseCheckout'], capture_output=True, text=True)
        if sparse.stdout.strip() == 'true':
            raise ValueError(f'Incomplete sparse checkout: {repo}')
        markers = sorted(p for p in files(repo) if p.name == 'SKILL.md')
        roots = []
        for marker in markers:
            if any(marker.parent.is_relative_to(parent) for parent in roots):
                continue
            roots.append(marker.parent)
        for directory in roots:
            rel = directory.relative_to(repo).as_posix()
            # Equal-depth names avoid Hermes's shallow-copy preference. Original
            # frontmatter stays unchanged; name collisions get native path aliases.
            key = name + '--' + hashlib.sha256(rel.encode()).hexdigest()[:16]
            packages.append({'source': directory, 'destination': key, 'repository': name,
                             'revision': rev, 'directory': rel, 'files': digest_tree(directory)})
    if len(packages) != 422 or sum(len(p['files']) for p in packages) != 3968:
        raise ValueError('Expected pinned inventory of 422 packages / 3968 files; nothing omitted')
    return packages


def hermes_utils(source):
    if git(source, 'rev-parse', 'HEAD') != HERMES_COMMIT:
        raise ValueError('Hermes source must be the audited v0.23.3 commit')
    sys.path.insert(0, str(source))
    return importlib.import_module('agent.skill_utils')


def catalog(root, util):
    rows = []
    for marker in util.iter_skill_index_files(root, 'SKILL.md'):
        front, _ = util.parse_frontmatter(marker.read_text(encoding='utf-8')[:4000])
        name = front.get('name', marker.parent.name)
        if not isinstance(name, str):
            raise ValueError(f'Invalid native skill name: {marker}')
        rows.append({'name': name[:64], 'tier': util.TIER_LOCAL, 'root': root, 'path': marker,
                     'visible': bool(util.skill_matches_platform(front) and
                                     util.skill_matches_environment(front) and util.skill_matches_apps(front))})
    return util.resolve_skill_catalog(rows)


def verify_reference(manifest, command=None):
    data = json.loads(manifest.read_text(encoding='utf-8-sig'))
    archive = Path(data['archive'])
    bridge = Path(command or data['bridge'])
    directory = Path(data.get('archive_directory', archive.parent))
    for path in (archive, bridge, directory):
        no_links(path)
    if not archive.is_file() or archive.suffix.lower() != '.zim' or not bridge.is_file():
        raise ValueError('Verified ZIM archive or installed OpenZIM bridge is missing')
    if archive.parent.resolve() != directory.resolve():
        raise ValueError('Archive directory does not contain the verified archive')
    expected = str(data['sha256']).lower()
    digest = hashlib.sha256()
    with archive.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise ValueError('Wikipedia archive no longer matches its checksum manifest')
    return {'command': str(bridge.resolve()), 'args': [str(directory.resolve())],
            'sampling': {'enabled': False}}


def config_update(existing, model, context, wiki, aux_names=()):
    if context not in (131072, 262144):
        raise ValueError('Context must be 131072 (single GPU) or 262144 (dual GPU)')
    out = copy.deepcopy(existing)
    if not isinstance(out, dict):
        raise ValueError('Config must be a mapping')
    def section(name):
        value = out.setdefault(name, {})
        if not isinstance(value, dict):
            raise ValueError(f'{name} must be a mapping')
        return value
    section('model').update(provider='llamacpp', default=model, base_url=BASE_URL,
                            api_key='local-only', context_length=context)
    out['fallback_providers'] = []
    out['fallback'] = {}
    for task in sorted(set(aux_names) | {k for k, v in section('auxiliary').items() if isinstance(v, dict)}):
        task_cfg = section('auxiliary').setdefault(task, {})
        if not isinstance(task_cfg, dict):
            raise ValueError(f'Invalid auxiliary task: {task}')
        task_cfg.update(provider='main', model=model, base_url=BASE_URL, api_key='local-only')
    section('webapp').update(enabled=True, host='127.0.0.1', port=9121, public_url='')
    section('gateway')['standalone'] = True
    for platform in ('cli', 'web', 'webapp', 'desktop', 'api_server'):
        section('platform_toolsets')[platform] = list(LOCAL_TOOLS)
    section('skills').update(external_dirs=[], trusted_project_dirs=[], create_dir='')
    section('mcp_servers')['openzim'] = wiki
    # Refuse pre-existing remote MCP rather than silently disable unrelated tools.
    if set(section('mcp_servers')) != {'openzim'}:
        raise ValueError('Dedicated home contains unrelated MCP servers; preserved, not changed')
    return out


def configure(args):
    import yaml
    home = args.home.absolute()
    no_links(home)
    if home.resolve() == (Path.home() / '.hermes').resolve():
        raise ValueError('Use a dedicated HERMES_HOME; default ~/.hermes is never edited')
    packages = source_inventory(args.repos)
    util = hermes_utils(args.hermes_source)
    from hermes_cli.config_defaults import DEFAULT_CONFIG
    aux_names = [k for k, v in DEFAULT_CONFIG['auxiliary'].items() if isinstance(v, dict)]
    path = home / 'config.yaml'
    existing = yaml.safe_load(path.read_text(encoding='utf-8')) if path.exists() else {}
    cfg = config_update(existing or {}, args.model, args.context,
                        verify_reference(args.reference_manifest, args.wiki_command), aux_names)
    wiki_source = Path(__file__).parent / 'offline-wikipedia'
    packages.append({'source': wiki_source, 'destination': 'offline-wikipedia',
                     'repository': 'pc-setup', 'revision': 'local', 'directory': 'offline-wikipedia',
                     'files': digest_tree(wiki_source)})
    home.mkdir(parents=True, exist_ok=True)
    target = home / 'skills'
    no_links(target)
    # Full preflight before installing anything: collisions preserve old bytes.
    for package in packages:
        dest = target / package['destination']
        no_links(dest)
        if dest.exists() and digest_tree(dest) != package['files']:
            raise ValueError(f'Changed native skill preserved: {dest}')
    with tempfile.TemporaryDirectory(prefix='.pc-setup-audit-', dir=home) as temp:
        stage = Path(temp) / 'skills'
        if target.exists():
            list(files(target))
            shutil.copytree(target, stage)
        else:
            stage.mkdir()
        for package in packages:
            dest = stage / package['destination']
            if not dest.exists():
                shutil.copytree(package['source'], dest)
        rows = catalog(stage, util)
        by_path = {r['relative_path']: r for r in rows}
        for package in packages:
            row = by_path.get(package['destination'])
            if not row or not row['load_name'] or not row['visible']:
                raise ValueError(f'Hermes would hide skill: {package["destination"]}')
            disabled = cfg.get('skills', {}).get('disabled', [])
            if row['name'] in disabled or row['load_name'] in disabled:
                raise ValueError(f'Imported skill disabled by existing config: {row["name"]}')
            package['load_name'] = row['load_name']
            package['status'] = row['status']
        target.mkdir(exist_ok=True)
        for package in packages:
            dest = target / package['destination']
            if not dest.exists():
                os.replace(stage / package['destination'], dest)
            if digest_tree(dest) != package['files']:
                raise ValueError(f'Copy verification failed: {dest}')
    record = [{k: v for k, v in p.items() if k != 'source'} for p in packages]
    atomic_text(home / 'pc-setup-skills.json', json.dumps(record, indent=2) + '\n')
    atomic_text(path, yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))
    print(json.dumps({'home': str(home), 'packages': len(packages),
                      'statuses': dict(Counter(p['status'] for p in packages)),
                      'model': args.model, 'context': args.context, 'webapp': 'http://127.0.0.1:9121'}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'configure'])
    parser.add_argument('--repos', type=Path, required=True)
    parser.add_argument('--home', type=Path)
    parser.add_argument('--hermes-source', type=Path)
    parser.add_argument('--model')
    parser.add_argument('--context', type=int, choices=[131072, 262144])
    parser.add_argument('--reference-manifest', type=Path)
    parser.add_argument('--wiki-command', type=Path)
    args = parser.parse_args()
    if args.action == 'prepare':
        print(f'Verified {len(prepare(args.repos))} complete packages; no tools executed.')
    else:
        for name in ('home', 'hermes_source', 'model', 'context', 'reference_manifest'):
            if getattr(args, name) is None:
                parser.error('--' + name.replace('_', '-') + ' is required for configure')
        configure(args)


if __name__ == '__main__':
    main()
