#!/usr/bin/env python3
"""Install desktop entries invoking the upstream Colibri CLI, not a new launcher."""
import argparse
import os
import json
from pathlib import Path
import subprocess


def quote(value):
    # First quote an Exec argument, then apply Desktop Entry string escaping.
    # GKeyFile decodes general escapes before GIO parses the Exec arguments.
    inner = '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'
    return inner.replace('\\', '\\\\')



def write_entry(path, text):
    if path.exists() and 'X-PC-Setup-Colibri=true' not in path.read_text():
        raise SystemExit(f'Refusing to replace an unrelated desktop entry: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)


def install(cli, model, icon, dual, home=None, image=False, python=None):
    home = Path(home or Path.home())
    env = ['-u', 'COLI_VK_DEV2', '-u', 'COLI_DENSE_BITS', '-u', 'COLI_DENSE_INT4', 'COLI_CUDA=0', 'COLI_VULKAN=1', 'COLI_NO_OMP_TUNE=1']
    if dual and not image:
        env.append('COLI_VK_DEV2=auto')
    name = 'Colibri Serve Image' if image else 'Colibri Serve'
    slug = 'pc-setup-colibri-serve-image' if image else 'pc-setup-colibri-serve'
    port = 8001 if image else 8000
    runtime = python or '/usr/bin/python3'
    # systemd owns only this process group. Stop controls never kill arbitrary ports.
    service = slug + '.service'
    unit_dir = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config'))) / 'systemd/user'
    for candidate in (unit_dir, *unit_dir.parents):
        if candidate.is_symlink(): raise SystemExit('Refusing linked service path: '+str(candidate))
    unit_dir.mkdir(parents=True, exist_ok=True)
    unit = unit_dir / service
    marker = '# ubuntu-pc-setup-colibri'
    if unit.is_symlink(): raise SystemExit('Refusing linked service file: '+str(unit))
    if unit.exists() and marker not in unit.read_text():
        raise SystemExit('Refusing unrelated service: ' + str(unit))
    def uq(x):
        return '"' + str(x).replace('\\', '\\\\').replace('"', '\\"').replace('%','%%').replace('$','$$') + '"'
    command_args = ['/usr/bin/env', *env, runtime, cli, 'serve', '--model', model, '--host', '127.0.0.1', '--port', str(port)]
    # Starting either model stops the other managed model to release memory.
    other = 'pc-setup-colibri-serve.service' if image else 'pc-setup-colibri-serve-image.service'
    content = marker+'\n[Unit]\nDescription='+name+'\nConflicts='+other+('\nAfter='+other if image else '')+'\n[Service]\nType=exec\nExecStart='+' '.join(uq(x) for x in command_args)+'\nKillMode=control-group\nTimeoutStopSec=30\n'
    if unit.exists() and unit.read_text()!=content: raise SystemExit('Existing managed service was customized; retained: '+str(unit))
    unit.write_text(content)
    unit.chmod(0o600)
    # Exact active model roots are recorded for the separate legacy migration guard.
    state=Path(os.environ.get('XDG_DATA_HOME',str(home/'.local/share')))/'pc-setup-colibri/managed-models.json'
    for candidate in (state,*state.parents):
        if candidate.is_symlink(): raise SystemExit('Refusing linked model inventory: '+str(candidate))
    inventory=json.loads(state.read_text()) if state.exists() else {'owner':'ubuntu-PC-setup','roots':{}}
    if not isinstance(inventory,dict) or inventory.get('owner')!='ubuntu-PC-setup' or not isinstance(inventory.get('roots'),dict):
        raise SystemExit('Unrecognized model inventory preserved')
    root=str(Path(model).absolute().parent)
    if slug in inventory['roots'] and inventory['roots'][slug]!=root:
        raise SystemExit('Different existing model root preserved; inspect migration inventory')
    inventory['roots'][slug]=root
    state.parent.mkdir(parents=True,exist_ok=True);state.write_text(json.dumps(inventory,indent=2)+'\n');state.chmod(0o600)
    command = '/usr/bin/systemctl --user start ' + service
    text = '\n'.join(['[Desktop Entry]', 'Type=Application', f'Name={name}',
        'Comment=Start the local Colibri model server',
        f'Exec={command}',
        f'Icon={icon}', 'Terminal=false', 'Categories=Development;',
        'X-PC-Setup-Colibri=true', ''])
    applications = Path(os.environ.get('XDG_DATA_HOME', str(home / '.local/share'))) / 'applications'
    write_entry(applications / (slug + '.desktop'), text)
    try:
        result = subprocess.run(['xdg-user-dir', 'DESKTOP'], check=True, capture_output=True, text=True)
        desktop = Path(result.stdout.strip())
        if not desktop.is_absolute() or desktop == home:
            raise ValueError('No distinct desktop folder configured')
    except (OSError, subprocess.CalledProcessError, ValueError):
        desktop = home / 'Desktop'
    write_entry(desktop / (name + '.desktop'), text)
    stop_text = text.replace('Name='+name, 'Name=Stop '+name).replace('--user start ', '--user stop ')
    write_entry(applications / (slug + '-stop.desktop'), stop_text)
    write_entry(desktop / ('Stop ' + name + '.desktop'), stop_text)
    print('Serve shortcut installed:', desktop / (name + '.desktop'))
    print('GNOME may ask you to right-click the desktop icon and choose Allow Launching once.')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--cli', required=True)
    p.add_argument('--model', required=True)
    p.add_argument('--icon', required=True)
    p.add_argument('--dual', action='store_true')
    p.add_argument('--image', action='store_true')
    p.add_argument('--python')
    a = p.parse_args()
    install(a.cli, a.model, a.icon, a.dual, image=a.image, python=a.python)
