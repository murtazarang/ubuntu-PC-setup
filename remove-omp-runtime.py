#!/usr/bin/env python3
"""Remove only recognized OMP runtimes after verified migration, never user data.
Upstream: omp.sh/install (standalone and Bun), bun pm/remove docs, npm ls/uninstall docs.
"""
import hashlib,json,os,pathlib,re,shutil,subprocess
PACKAGE='@oh-my-pi/pi-coding-agent'

def run(args, allowed=(0,)):
    result=subprocess.run(args,capture_output=True,text=True,timeout=60)
    if result.returncode not in allowed:raise RuntimeError('Could not safely inspect/run '+repr(args)+': '+result.stderr)
    return result.stdout.strip()

def identity(p):
    p=pathlib.Path(p)
    if any(x.is_symlink() for x in (p,*p.parents)):raise RuntimeError('Nonstandard linked standalone path retained: '+str(p))
    st=p.stat()
    return [st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns,hashlib.sha256(p.read_bytes()).hexdigest()]

def discover(home=None):
    home=pathlib.Path(home or pathlib.Path.home());records=[];known=set()
    standalone=home/'.local/bin/omp'
    standalone_candidates=[standalone]
    override=os.environ.get('PI_INSTALL_DIR')
    if override:
        custom=pathlib.Path(override).expanduser()
        if not custom.is_absolute():raise RuntimeError('Relative PI_INSTALL_DIR cannot be resolved safely; specify its absolute original install location.')
        if custom/'omp' not in standalone_candidates:standalone_candidates.append(custom/'omp')
    for binary in standalone_candidates:
        if binary.exists() and not binary.is_symlink():
            records.append({'kind':'standalone','path':str(binary),'identity':identity(binary)});known.add(str(binary.absolute()))
    bun=shutil.which('bun')
    if bun:
        listing=run([bun,'pm','ls','-g'])
        if re.search(re.escape(PACKAGE)+r'@[^\s]+',listing):
            bindir=pathlib.Path(run([bun,'pm','bin','-g']))
            if not bindir.is_absolute():raise RuntimeError('Unexpected Bun global bin path')
            records.append({'kind':'bun','manager':bun,'package':PACKAGE,'listing':listing,'bin':str(bindir/'omp')})
            known.add(str((bindir/'omp').absolute()))
    npm=shutil.which('npm')
    if npm:
        root=pathlib.Path(run([npm,'root','--global']))
        if not root.is_absolute():raise RuntimeError('Unexpected npm global package root')
        package_dir=root/PACKAGE
        if package_dir.exists():
            metadata=json.loads((package_dir/'package.json').read_text())
            if metadata.get('name')!=PACKAGE:raise RuntimeError('Unrecognized npm OMP package metadata; retained')
            data=json.loads(run([npm,'ls','--global','--depth=0','--json',PACKAGE],allowed=(0,1)))
            if 'error' in data:raise RuntimeError('npm global inventory failed: '+str(data['error']))
            package=data.get('dependencies',{}).get(PACKAGE)
            if package is None:raise RuntimeError('OMP package directory is not accounted for by npm; retained')
            prefix=pathlib.Path(run([npm,'prefix','--global']))
            if not prefix.is_absolute():raise RuntimeError('Unexpected npm prefix')
            records.append({'kind':'npm','manager':npm,'package':PACKAGE,'version':package,'bin':str(prefix/'bin/omp')})
            known.add(str((prefix/'bin/omp').absolute()))
    candidates={str(binary.absolute()) for binary in standalone_candidates}
    candidates.add(str((home/'.bun/bin/omp').absolute()))
    candidates.update(str((pathlib.Path(part or '.')/'omp').absolute()) for part in os.environ.get('PATH','').split(os.pathsep))
    unknown=[]
    for value in sorted(candidates):
        p=pathlib.Path(value)
        if (p.exists() or p.is_symlink()) and value not in known:unknown.append(value)
    if unknown:raise RuntimeError('Unrecognized/duplicate OMP runtime retained; uninstall using its owner before retrying: '+', '.join(unknown))
    return records

def ensure_stopped(records):
    paths={str(pathlib.Path(r.get('path',r.get('bin',''))).resolve()) for r in records}
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name)==os.getpid():continue
        try:
            if proc.stat().st_uid!=os.getuid():continue
            args=(proc/'cmdline').read_bytes().decode(errors='replace').split('\0')
        except FileNotFoundError:continue
        except PermissionError:raise RuntimeError('Cannot inspect same-user process '+proc.name+'; OMP removal stopped.')
        if not args or not args[0]:continue
        if pathlib.Path(args[0]).name=='omp' or any(PACKAGE in arg or arg in paths for arg in args):
            raise RuntimeError('OMP runtime/source process '+proc.name+' is running; close it before cleanup. No process was killed.')

def uninstall(input_fn=input):
    records=discover()
    if not records:
        print('No OMP runtime found in the default locations, current PATH or inspected Bun/npm global packages.');return
    ensure_stopped(records)
    print('Verified migration. OMP runtime inventory:',flush=True)
    for r in records:print(' - '+r['kind']+': '+r.get('path',r.get('bin','')),flush=True)
    print('Skills, chats, settings, Wikipedia, shared packages and Bun/Node are retained.',flush=True)
    if input_fn('Type REMOVE OMP to uninstall these runtimes: ')!='REMOVE OMP':raise RuntimeError('OMP retained at your request; runtime removal is incomplete.')
    # Re-discover identity, paths and package-manager ownership after confirmation.
    if discover()!=records:raise RuntimeError('OMP installation changed while awaiting confirmation; nothing removed.')
    ensure_stopped(records)
    for r in records:
        if r['kind']=='standalone':
            p=pathlib.Path(r['path'])
            if identity(p)!=r['identity']:raise RuntimeError('OMP binary changed; retained.')
            p.unlink()
        elif r['kind']=='bun':run([r['manager'],'remove','--global',PACKAGE])
        else:run([r['manager'],'uninstall','--global','--ignore-scripts',PACKAGE])
    remaining=discover()
    if remaining or shutil.which('omp'):raise RuntimeError('An OMP installation remains; uninstall was not marked complete.')
    print('OMP runtime absence verified in current PATH, default locations and inspected package managers.')

if __name__=='__main__':
    try:uninstall()
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as exc:raise SystemExit(str(exc))
