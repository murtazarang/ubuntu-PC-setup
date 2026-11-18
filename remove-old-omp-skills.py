#!/usr/bin/env python3
"""Remove only collections installed by configure-skills.sh at da19d04/fac0e5a."""
import json
import os
from pathlib import Path
import shutil
import sys
import subprocess
import re

NAMES = ('scientific-agent-skills', 'claude-scientific-writer', 'education-agent-skills')

def mountpoints():
    # mountinfo includes bind mounts, which Path.is_mount can miss.
    rows = Path('/proc/self/mountinfo').read_text().splitlines()
    return [Path(re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1],8)), row.split()[4])) for row in rows]

def inventory(home, protected, roots=None):
    root = home / '.local/share/omp-skills'
    for parent in (root, *root.parents):
        if parent.is_symlink():
            raise RuntimeError(f'Refusing linked legacy collection parent: {parent}')
    result = []
    for path in (roots if roots is not None else [root / name for name in NAMES]):
        if any(p.is_symlink() for p in (path,*path.parents)):
            raise RuntimeError(f'Refusing linked legacy collection: {path}')
        if not path.exists():
            continue
        if not path.is_dir() and path != home / '.local/share/omp-skills/installed-skills.json':
            raise RuntimeError(f'Expected collection directory: {path}')
        if not path.is_dir() and not path.is_file():
            raise RuntimeError(f'Expected regular metadata file: {path}')
        for mount in mountpoints():
            if mount == path or path in mount.parents:
                raise RuntimeError(f'Refusing mounted deletion subtree: {mount}')
        # An archive may predate reference.json or live at a custom location.
        # Do not follow directory links or cross mounts; mounts were rejected above.
        if path.is_dir():
            def fail_walk(error):
                raise RuntimeError('Cannot inspect old data for Wikipedia archives: '+str(error))
            for directory, dirs, files in os.walk(path, followlinks=False, onerror=fail_walk):
                for name in (*dirs, *files):
                    if name.lower().endswith(('.zim', '.zim.part')):
                        raise RuntimeError('Wikipedia/archive download retained; cleanup stopped before deletion: '+str(Path(directory)/name)+'. Relocate it deliberately before retrying.')
        for keep in protected:
            resolved = keep.resolve()
            if resolved == path.resolve() or path.resolve() in resolved.parents or resolved in path.resolve().parents:
                raise RuntimeError(f'Protected replacement data is within {path}: {keep}')
        stat = path.stat()
        result.append((path, (stat.st_dev, stat.st_ino)))
    return result

def remove(home, protected, confirm=input, roots=None, process_guard=None):
    before = inventory(home, protected, roots)
    if not before:
        print('No identified old application data or OMP skill collections remain.')
        return
    print('Permanently delete these OLD AI application data and OMP collections, INCLUDING histories, settings, custom edits and added files:')
    for path, _ in before:
        print(path)
    print('New Open WebUI skills, Wikipedia and unrelated directories are retained.')
    if confirm('Type DELETE OLD OMP SKILLS to confirm: ').strip() != 'DELETE OLD OMP SKILLS':
        raise RuntimeError('Old skill cleanup declined; migration cleanup remains incomplete.')
    if process_guard is not None:
        process_guard()
    if inventory(home, protected, roots) != before:
        raise RuntimeError('Collection identity changed during confirmation; nothing deleted.')
    if not shutil.rmtree.avoids_symlink_attacks:
        raise RuntimeError('This Python lacks safe directory deletion; nothing deleted.')
    for path, identity in before:
        if inventory(home, protected, roots) and (path.is_symlink() or (path.stat().st_dev, path.stat().st_ino) != identity):
            raise RuntimeError(f'Collection changed: {path}')
        if path.is_dir(): shutil.rmtree(path)
        else: path.unlink()
    if inventory(home, protected, roots):
        raise RuntimeError('Old collection directories remain; cleanup incomplete.')

def main():
    home = Path.home()
    data = Path(os.environ.get('XDG_DATA_HOME', home / '.local/share'))
    base = data / 'pc-setup-openwebui'
    protected = [base, data / 'pc-setup-colibri', Path(os.environ.get('KIWIX_ARCHIVE_DIR', home / '.local/share/kiwix-mcp/archives'))]
    if (base / 'reference.json').exists():
        reference = json.loads((base / 'reference.json').read_text())
        protected.append(Path(reference['archive']))
    model_file = data / 'pc-setup-colibri/managed-models.json'
    if model_file.exists():
        models = json.loads(model_file.read_text())
        protected.extend(map(Path, models['roots'].values()))
    # Follow links in active replacement trees as well as their root paths.
    for keep in list(protected):
        if keep.is_dir():
            protected.extend(p for p in keep.rglob('*') if p.is_symlink())
    roots = [home / '.local/share/omp-skills' / n for n in NAMES]
    # Source contracts: OMP utils/dirs.ts; Paseo paseo-home.ts/Electron app name;
    # Strata paths.py and XeStrata serve/places.py. Never shared package caches.
    roots += [home / '.omp', home / '.paseo', home / '.local/share/omp-scientific-tools', home / '.local/share/omp-skills/installed-skills.json']
    for key, fallback in [('XDG_DATA_HOME','.local/share'),('XDG_CONFIG_HOME','.config'),('XDG_STATE_HOME','.local/state'),('XDG_CACHE_HOME','.cache')]:
        location = Path(os.environ.get(key, home / fallback))
        if not location.is_absolute(): raise RuntimeError(f'{key} must be absolute')
        families = ['strata','xestrata'] if key != 'XDG_CACHE_HOME' else []
        if key == 'XDG_CONFIG_HOME': families += ['Paseo']
        if key in ('XDG_DATA_HOME','XDG_STATE_HOME','XDG_CACHE_HOME') and key in os.environ: families += ['omp']
        roots += [location / family for family in families]
    # Broad/custom overrides cannot establish exclusive ownership automatically.
    for key in ('PI_CONFIG_DIR','PI_CODING_AGENT_DIR','PASEO_HOME','PASEO_ELECTRON_USER_DATA_DIR','STRATA_SETTINGS_FILE','STRATA_TUNE_DIR','STRATA_TIMESKIP_DIR'):
        value = os.environ.get(key)
        if value:
            candidate = Path(value).expanduser()
            if key == 'PI_CONFIG_DIR': candidate = home / candidate
            candidate = candidate.absolute()
            if not any(candidate == r or r in candidate.parents for r in roots):
                raise RuntimeError(f'Custom {key} retained; exact exclusive ownership must be reviewed: {candidate}')
    roots = list(dict.fromkeys(roots))
    roots = [p for p in roots if not any(other != p and other in p.parents for other in roots)]
    # Official OMP config CLI was used by the original installer to register
    # customDirectories. Read it before removing the runtime; never execute skills.
    if sys.argv[1:] == ['--check']:
        config_roots = [r for r in roots if r.name in ('.omp','omp')]
        positions = [d for r in config_roots for d in (r,r/'agent')]
        for r in config_roots:
            profiles = r/'profiles'
            if profiles.exists():
                if profiles.is_symlink(): raise RuntimeError('Linked OMP profiles require review: '+str(profiles))
                positions.extend(d for profile in profiles.iterdir() if profile.is_dir() for d in (profile,profile/'agent'))
        configs = list(dict.fromkeys(d/name for d in positions for name in ('config.yml','config.yaml','settings.json') if (d/name).exists()))
        configs += [Path(v).expanduser() for v in os.environ.get('PI_CONFIG_FILES','').split(os.pathsep) if v]
        for config in configs:
            if not config.is_absolute() or any(p.is_symlink() for p in (config,*config.parents)):
                raise RuntimeError('Linked/relative OMP configuration requires review: '+str(config))
            if config.suffix == '.json':
                value = json.loads(config.read_text())
            else:
                uv = shutil.which('uv')
                if not uv: raise RuntimeError('uv is required to safely parse existing OMP YAML before cleanup; nothing removed.')
                result = subprocess.run([uv,'run','--no-project','--with','PyYAML','python','-c', 'import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))',str(config)],capture_output=True,text=True,check=True)
                value = json.loads(result.stdout)
            if value is None: continue
            if not isinstance(value,dict): raise RuntimeError('Unexpected OMP configuration: '+str(config))
            skills = value.get('skills',{})
            if not isinstance(skills,dict): raise RuntimeError('Unexpected skill settings: '+str(config))
            registered = skills.get('customDirectories',value.get('skills.customDirectories',[]))
            if not isinstance(registered,list): raise RuntimeError('Unexpected customDirectories in '+str(config))
            for raw in registered:
                if not isinstance(raw,str): raise RuntimeError('Invalid custom skill path in '+str(config))
                candidate = Path(raw).expanduser()
                if not candidate.is_absolute(): raise RuntimeError('Relative custom skill directory needs original working-directory context: '+raw)
                if candidate.exists() and not any(candidate == r or r in candidate.parents for r in roots):
                    raise RuntimeError('External custom skill directory requires ownership review before cleanup: '+str(candidate))
    executable = shutil.which('omp')
    if executable and sys.argv[1:] == ['--check']:
        result = subprocess.run([executable, 'config', 'get', 'skills.customDirectories', '--json'], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError('Cannot inventory OMP custom skill directories; cleanup has not started.')
        registered = json.loads(result.stdout).get('value')
        if not isinstance(registered, list) or any(not isinstance(p,str) for p in registered):
            raise RuntimeError('Unexpected OMP custom skill directory inventory; cleanup has not started.')
        outside = []
        for raw in registered:
            candidate = Path(raw).expanduser().absolute()
            if candidate.exists() and not any(candidate == r or r in candidate.parents for r in roots):
                outside.append(str(candidate))
        if outside:
            raise RuntimeError('Additional custom skill directories need explicit ownership review before cleanup: ' + ', '.join(outside))
    if sys.argv[1:] == ['--check']:
        inventory(home, protected, roots)
        print('Old application data scope and protected paths checked; no data deleted.')
    elif sys.argv[1:]:
        raise RuntimeError('Usage: remove-old-omp-skills.py [--check]')
    else:
        subprocess.run([sys.executable, str(Path(__file__).with_name('remove-omp-runtime.py')), '--check'], check=True)
        remove(home, protected, roots=roots, process_guard=lambda: subprocess.run([sys.executable, str(Path(__file__).with_name('remove-omp-runtime.py')), '--check'], check=True))

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as exc:
        raise SystemExit(str(exc))
