#!/usr/bin/env python3
"""Install and open the setup-owned local Hermes/llama.cpp workspace."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.request import ProxyHandler, build_opener

from engine import BASE_URL, PROFILES

ENDPOINT = BASE_URL.removesuffix('/v1')
MANAGED_SHORTCUT = 'X-PC-Setup=HermesLocalAI'
urlopen = build_opener(ProxyHandler({})).open


def run(*args, **options):
    return subprocess.run([os.fspath(arg) for arg in args], check=True, **options)


def write_record(path, data):
    fd, raw = tempfile.mkstemp(prefix='.desktop-', dir=path.parent)
    tmp = Path(raw)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(data, handle, indent=2)
            handle.write('\n')
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def record_for(root):
    return root / 'desktop.json'


def launcher(root, path):
    if not path.is_file() or not path.resolve().is_relative_to((root / 'hermes-home').resolve()):
        raise ValueError('The setup-owned Hermes CLI was not found.')
    if os.name == 'nt' and path.suffix == '.cmd' and any(c in str(path) for c in '%!\r\n'):
        raise ValueError('The Hermes batch launcher path contains unsupported command-shell characters.')
    return path


def hermes(root, executable, *args):
    env = os.environ | {'HERMES_HOME': str(root / 'hermes-home')}
    for key in ('OPENAI_BASE_URL', 'OPENAI_API_KEY', 'OPENROUTER_BASE_URL', 'HERMES_RUNTIME_DIR'):
        env.pop(key, None)
    # urllib/httpx prefer different spellings; keep any user proxy exceptions.
    for key in ('no_proxy', 'NO_PROXY'):
        env[key] = ','.join(filter(None, (env.get(key), '127.0.0.1', 'localhost')))
    # Use only the exact upstream checkout launcher, not a PATH alias.
    return run(launcher(root, executable), *args, env=env)


def engine(root, profile, action):
    return run(sys.executable, Path(__file__).with_name('engine.py'), action, '--profile', profile, '--root', root)


def check_endpoint(alias, context):
    # The llama.cpp model alias and per-slot allocation must both be real.
    with urlopen(f'{ENDPOINT}/v1/models', timeout=5) as response:
        ids = [entry['id'] for entry in json.load(response)['data']]
    with urlopen(f'{ENDPOINT}/props', timeout=5) as response:
        props = json.load(response)
    if (ids != [alias] or props.get('total_slots') != 1 or
            props.get('default_generation_settings', {}).get('n_ctx') != context or
            not props.get('chat_template')):
        raise RuntimeError('The running server does not match the configured model, tool template, or context.')


def configure(args):
    import hermes_config

    root = args.root
    spec = PROFILES[args.profile]
    home = root / 'hermes-home'
    path = launcher(root, args.hermes)
    # Native MCP remains local; the adapter reads the existing verified profile
    # rather than doing any further archive downloads or indexing.
    repos = root / 'skill-repos'
    hermes_config.prepare(repos)
    hermes_config.configure(argparse.Namespace(home=home, repos=repos, model=spec.alias,
                                                context=spec.context, reference_manifest=args.reference,
                                                wiki_command=args.bridge, hermes_source=home / 'hermes-agent'))
    hermes(root, path, '--version')
    hermes(root, path, 'webapp', '--build-only')
    engine(root, args.profile, 'install')
    write_record(record_for(root), {'profile': args.profile, 'hermes': str(path),
                                   'alias': spec.alias, 'context': spec.context})


def quote_desktop(arg):
    # Desktop Entry Exec is not shell syntax. This also protects field codes.
    arg = str(arg)
    if any(char in arg for char in '\r\n\x00'):
        raise ValueError('Desktop launcher paths cannot contain newlines or NUL.')
    arg = arg.replace('%', '%%')
    for char in ('\\', '"', '`', '$'):
        arg = arg.replace(char, '\\' + char)
    # A backslash must survive the desktop key-value unescape before Exec parse.
    return '"' + arg.replace('\\', '\\\\') + '"'


def shortcuts(root, profile):
    directory = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'applications'
    directory.mkdir(parents=True, exist_ok=True)
    for action in ('start', 'stop'):
        title = action.capitalize() + ' Local AI'
        path = directory / f'pc-setup-hermes-{action}.desktop'
        arguments = (sys.executable, Path(__file__).resolve(), action, '--root', root, '--profile', profile)
        body = ('[Desktop Entry]\nType=Application\n'
                f'Name={title}\nExec={" ".join(map(quote_desktop, arguments))}\n'
                f'Icon=utilities-terminal\nTerminal=true\n{MANAGED_SHORTCUT}\n')
        if path.is_symlink() or (path.exists() and MANAGED_SHORTCUT not in path.read_text(encoding='utf-8').splitlines()):
            raise ValueError(f'Unrelated launcher preserved: {path}')
        path.write_text(body, encoding='utf-8')


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('action', choices=('configure', 'shortcuts', 'start', 'stop', 'status'))
    cli.add_argument('--root', required=True, type=Path)
    cli.add_argument('--profile', required=True, choices=PROFILES)
    cli.add_argument('--hermes', type=Path)
    cli.add_argument('--bridge', type=Path)
    cli.add_argument('--reference', type=Path)
    args = cli.parse_args()
    args.root = args.root.resolve()
    try:
        if args.action == 'configure':
            if not all((args.hermes, args.bridge, args.reference)):
                cli.error('configure requires --hermes, --bridge and --reference')
            configure(args)
        elif args.action == 'shortcuts':
            shortcuts(args.root, args.profile)
        else:
            record = json.loads(record_for(args.root).read_text(encoding='utf-8'))
            if record['profile'] != args.profile:
                raise ValueError('This shortcut does not match the installed hardware profile.')
            if args.action == 'start':
                engine(args.root, args.profile, 'start')
                check_endpoint(record['alias'], record['context'])
                hermes(args.root, Path(record['hermes']), 'webapp', '--skip-build')
            else:
                engine(args.root, args.profile, args.action)
                if args.action == 'status':
                    check_endpoint(record['alias'], record['context'])
    except (KeyError, OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Local AI: {error}', file=sys.stderr)
        if os.name == 'nt' and args.action in ('start', 'stop') and sys.stdin.isatty():
            input('Press Enter to close.')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
