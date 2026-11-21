#!/usr/bin/env python3
"""Existing Ubuntu migration only: retire owned text launchers; preserve data/image."""
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile


UNITS = {
    'pc-setup-colibri-serve.service': '# ubuntu-pc-setup-colibri',
}
MENU = {'pc-setup-colibri-serve.desktop': 'Colibri Serve',
        'pc-setup-colibri-serve-stop.desktop': 'Stop Colibri Serve'}
DESKTOP = {f'{name}.desktop': name for name in MENU.values()}


def regular(path):
    for part in (path,*path.parents):
        try:
            info=part.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode):
            raise ValueError(f'Refusing linked old setup path: {part}')
    if not path.exists():
        return False
    if not path.is_file():
        raise ValueError(f'Expected a regular old setup file: {path}')
    return True


def owned_unit(path, marker):
    if not regular(path):
        return False
    if not path.read_text().startswith(marker+'\n'):
        raise ValueError(f'Old service is not setup-owned; not stopping it: {path}')
    return True


def owned_shortcut(path, name):
    try:
        if not regular(path):
            return False
        lines=path.read_text().splitlines()
        group=lines.index('[Desktop Entry]')
        entry=lines[group+1:]
        exec_lines=[line for line in entry if line.startswith('Exec=')]
        if (len(exec_lines)!=1 or entry.count('Name='+name)!=1 or
                entry.count('X-PC-Setup-Colibri=true')!=1):
            raise ValueError('Fingerprint differs')
        current=exec_lines[0]
        operation='stop' if name.startswith('Stop ') else 'start'
        cmd=f'Exec=/usr/bin/systemctl --user {operation} pc-setup-colibri-serve.service'
        if current!=cmd:
            raise ValueError('Command differs')
        return True
    except (OSError,ValueError) as exc:
        print(f'Keeping unrecognized shortcut {path}: {exc}')
        return False


def loaded_unit(path):
    result=subprocess.run(['systemctl','--user','show',path.name,
                           '--property=FragmentPath','--property=DropInPaths'],
                          check=True,text=True,capture_output=True)
    properties=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    if properties.get('FragmentPath')!=str(path) or properties.get('DropInPaths')!='':
        raise ValueError(f'Cannot verify the live unit or it has custom drop-ins: {path}. Retained.')


def main():
    home=Path.home()
    config=Path(os.environ.get('XDG_CONFIG_HOME',home/'.config'))
    data=Path(os.environ.get('XDG_DATA_HOME',home/'.local/share'))
    if not config.is_absolute() or not data.is_absolute():
        raise ValueError('XDG directories must be absolute')
    base=data/'pc-setup-openwebui'
    desktop=home/'Desktop'
    try:
        found=Path(subprocess.check_output(['xdg-user-dir','DESKTOP'],text=True).strip())
        if found.is_absolute() and found!=home:
            desktop=found
    except (OSError,subprocess.CalledProcessError):
        pass
    units=[p for n,m in UNITS.items() if owned_unit(p:=config/'systemd/user'/n,m)]
    shortcuts=[p for parent,mapping in ((data/'applications',MENU),(desktop,DESKTOP))
               for n,label in mapping.items() if owned_shortcut(p:=parent/n,label)]
    if not units and not shortcuts:
        return
    print('Retire only the old text launchers and stop the listed owned user units. Open WebUI, its image connection, and old data stay installed.',flush=True)
    for path in units+shortcuts:
        print(path,flush=True)
    if input('Type RETIRE TEXT or press Enter to leave everything as is: ')!='RETIRE TEXT':
        print('Legacy text retirement skipped.')
        return
    for path in units:
        loaded_unit(path)
    if units:
        subprocess.run(['systemctl','--user','stop',*[path.name for path in units]],check=True)
    if shortcuts:
        backup_root=base/'retired-shortcuts'
        for member in (backup_root,*backup_root.parents):
            if member.is_symlink():
                raise ValueError(f'Refusing linked backup location: {member}')
        backup_root.mkdir(parents=True,exist_ok=True)
        backup=Path(tempfile.mkdtemp(prefix='retire-',dir=backup_root))
        for i,path in enumerate(shortcuts):
            target=backup/str(i)
            target.mkdir()
            shutil.move(path,target/path.name)
        (backup/'source-paths.txt').write_text('\n'.join(map(str,shortcuts))+'\n')
        print(f'Old text shortcuts archived in {backup}; image shortcuts remain.')


if __name__=='__main__':
    main()
