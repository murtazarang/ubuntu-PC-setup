#!/usr/bin/env python3
"""Install desktop entries invoking the upstream Colibri CLI, not a new launcher."""
import argparse
import os
from pathlib import Path
import subprocess


def quote(value):
    # Desktop Entry Exec quoting: shell metacharacters have no shell meaning.
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'


def write_entry(path, text):
    if path.exists() and 'X-PC-Setup-Colibri=true' not in path.read_text():
        raise SystemExit(f'Refusing to replace an unrelated desktop entry: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)


def install(cli, model, icon, dual, home=None, image=False, python=None):
    home = Path(home or Path.home())
    env = ['-u', 'COLI_VK_DEV2', '-u', 'COLI_DENSE_BITS', 'COLI_CUDA=0', 'COLI_VULKAN=1', 'COLI_NO_OMP_TUNE=1']
    if dual and not image:
        env.append('COLI_VK_DEV2=auto')
    name = 'Colibri Serve Image' if image else 'Colibri Serve'
    slug = 'pc-setup-colibri-serve-image' if image else 'pc-setup-colibri-serve'
    port = 8001 if image else 8000
    ui_port = 8791 if image else 8790
    runtime = python or '/usr/bin/python3'
    # Two upstream commands in a visible terminal, with no saved runtime wrapper.
    # Port checks never stop an existing service or silently attach to it.
    startup = """import socket,subprocess,sys,time
py,cli,model,port,uiport=sys.argv[1:]
sockets=[]
try:
 for value in (port,uiport):
  s=socket.socket();s.bind(('127.0.0.1',int(value)));sockets.append(s)
except OSError as e:
 raise SystemExit('Colibri port already occupied; close the existing instance first: '+str(e))
finally:
 for s in sockets:s.close()
server=subprocess.Popen([py,cli,'serve','--model',model,'--host','127.0.0.1','--port',port])
time.sleep(1)
if server.poll() is not None:raise SystemExit('Colibri server exited; see error above.')
print('Starting the upstream Colibri UI. The model may still be loading.',flush=True)
ui=subprocess.Popen([py,cli,'ui','--host','127.0.0.1','--port',uiport,'--backend','http://127.0.0.1:'+port])
while server.poll() is None and ui.poll() is None:time.sleep(1)
print('A Colibri process exited. This launcher does not kill other processes; use Ctrl+C in this terminal to stop its remaining foreground process group.',flush=True)
server.wait();ui.wait()
"""
    # Keep Exec on one line: Python accepts an escaped source string via exec.
    inline = 'exec(' + repr(startup) + ')'
    command = '/usr/bin/env ' + ' '.join(env) + ' ' + ' '.join(quote(x) for x in (runtime, '-c', inline, runtime, cli, model, str(port), str(ui_port)))
    if image:
        command = '/usr/bin/env ' + ' '.join(env) + ' ' + ' '.join(quote(x) for x in (runtime, cli, 'web', '--model', model, '--host', '127.0.0.1', '--port', str(port)))
    text = '\n'.join(['[Desktop Entry]', 'Type=Application', f'Name={name}',
        'Comment=Start the local Colibri model server',
        f'Exec={command}',
        f'Icon={icon}', 'Terminal=true', 'Categories=Development;',
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
