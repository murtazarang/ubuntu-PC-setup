#!/usr/bin/env bash
# Direct uninstall patch. Preview first; explicit confirmation before deleting models.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user, not sudo.' >&2; exit 1; fi
[[ $# -le 1 && ( ${1:-} == '' || ${1:-} == --apply ) ]] || { echo 'Usage: ./remove-legacy-ai.sh [--apply]' >&2; exit 2; }
export PATH="$HOME/.local/bin:$PATH"
data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
paths=()
# These are upstream runtime/install or model-library subdirectories, not entire
# app-data roots: chats, settings, state and shared Hugging Face caches stay put.
for name in terminal components install models packs mtp Strata-data; do paths+=("$data/strata/$name"); done
for name in models packs mtp; do paths+=("$data/xestrata/$name"); done
packages=()
for p in paseo xestrata xestrata-contrib-cuda13.1; do
 if dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null | grep -qx installed; then packages+=("$p"); fi
done
printf 'Packages to uninstall (no autoremove of shared dependencies): %s\n' "${packages[*]:-none}"
echo 'Known runtime/model downloads to DELETE permanently:'
for p in "${paths[@]}"; do [[ ! -e $p && ! -L $p ]] || printf '  %s\n' "$p"; done
shim="$HOME/.local/bin/strata"
if [[ -L $shim && $(readlink "$shim") == "$data/strata/terminal/current/bin/strata" ]]; then
 remove_shim=true; printf 'Known launcher link to unlink: %s\n' "$shim"
else remove_shim=false; [[ ! -e $shim ]] || echo "Unrecognized Strata launcher preserved: $shim"; fi
unit="$config/systemd/user/xestrata.service"
if [[ -e $unit ]]; then printf 'XeStrata user service to inspect/disable (file preserved): %s\n' "$unit"; fi
python3 - "$config/strata/settings.json" "$data/strata/app-settings.json" "$config/xestrata/settings.json" <<'PY'
import json,pathlib,sys
for name in sys.argv[1:]:
 p=pathlib.Path(name)
 if p.is_file():
  try:value=json.loads(p.read_text()).get('data_dir')
  except (ValueError,OSError): print('Unreadable settings preserved:',p);continue
  if value:print('Configured data_dir (preserved unless an exact listed subtree):',value)
PY
printf '%s\n' 'Chat/history/config/state, OMP, skills, Wikipedia, shared packages/caches, external model folders and earlier backups are preserved.' 'Only the exact listed runtime/download subtrees are removed; no quarantine is created.'
[[ ${1:-} == --apply ]] || { echo 'Preview only. Run with --apply to confirm direct uninstall and permanent deletion.'; exit 0; }
read -r -p 'Type DELETE LEGACY AI to uninstall the packages and permanently delete ALL listed runtime/model files: ' answer
[[ $answer == 'DELETE LEGACY AI' ]] || exit 1
# Reject symlinked roots/parents and mounted model subtrees; never follow them.
check_paths() {
 python3 - "${paths[@]}" <<'PY'
import pathlib,sys
for name in sys.argv[1:]:
 p=pathlib.Path(name)
 for part in (p,*p.parents):
  if part.is_symlink():raise SystemExit('Refusing symlinked deletion path: '+str(part))
 if p.exists():
  for child in (p,*p.rglob('*')):
   if child.is_mount():raise SystemExit('Refusing mounted deletion subtree: '+str(child))
PY
}
check_paths
# Use only the upstream launcher rooted at this installation, never an arbitrary
# command of the same name on PATH. Stop its own engine through its native CLI.
if [[ $remove_shim == true && -x $shim ]]; then
 "$shim" launch --stop || { echo 'Strata stop failed; no files deleted. Stop it and rerun.' >&2; exit 1; }
fi
unit_text=$(systemctl --user cat xestrata.service 2>/dev/null || true)
if [[ -n $unit_text ]]; then
 [[ $(grep -c '^ExecStart=' <<<"$unit_text") == 1 ]] && grep -Eq '^ExecStart=/usr/bin/xestrata( |$)' <<<"$unit_text" || { echo 'Unrecognized XeStrata service preserved; inspect it before removal.' >&2; exit 1; }
 python3 - "$unit" <<'PYUNIT'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
if any(x.is_symlink() for x in (p,*p.parents)):
 raise SystemExit('Symlinked user service path preserved: '+str(p))
PYUNIT
 systemctl --user disable --now xestrata.service
elif [[ -e $unit || -L $unit ]]; then
 echo "Cannot validate existing user service; preserved: $unit" >&2; exit 1
fi
# Never kill arbitrary Python, Electron, or user processes. Refuse deletion while
# a known installation still runs; native package manager handles package files.
package_files=''
if (( ${#packages[@]} )); then package_files=$(dpkg-query -L "${packages[@]}"); fi
PACKAGE_FILES="$package_files" python3 - "${paths[@]}" <<'PY'
import json,os,pathlib,subprocess,sys
roots=[str(pathlib.Path(x).absolute()) for x in sys.argv[1:]]
package_files=set(os.environ['PACKAGE_FILES'].splitlines())
unreadable=[]
for proc in pathlib.Path('/proc').glob('[0-9]*'):
 if 'started' in locals():del started
 try:
  if proc.stat().st_uid!=os.getuid() or int(proc.name)==os.getpid():continue
  started=(proc/'stat').read_text().rsplit(')',1)[1].split()[19]
  args=(proc/'cmdline').read_bytes().decode(errors='replace').split('\0')
  executable=os.readlink(proc/'exe').removesuffix(' (deleted)')
 except (FileNotFoundError,ProcessLookupError):continue
 except OSError as exc:
  details=[]
  for name in ('comm','status','cmdline'):
   try:
    text=(proc/name).read_text().replace('\x00',' ')
    if name=='status':text='; '.join(line for line in text.splitlines() if line.startswith(('Name:','State:','Uid:','Gid:','TracerPid:','NoNewPrivs:')))
    details.append(name+'='+text[:1000].strip())
   except OSError as detail_error:details.append(name+' unreadable: '+str(detail_error))
  if 'started' not in locals():raise SystemExit('Cannot establish process identity before privileged inspection: '+proc.name)
  unreadable.append({'pid':int(proc.name),'started':started,'detail':'PID '+proc.name+': '+str(exc)+' | '+' | '.join(details)})
  continue
 if executable in package_files or any(executable==root or executable.startswith(root+'/') for root in roots) or any(arg==root or arg.startswith(root+'/') for arg in args for root in roots):
  raise SystemExit('A legacy runtime is still running (PID '+proc.name+'). Close it and rerun; nothing was forcibly killed.')
if unreadable:
 print('Some current-user process executables require elevated read access. Requesting sudo for a READ-ONLY rescan of these PIDs only:', ', '.join(str(p['pid']) for p in unreadable),flush=True)
 # Isolated Python ignores user PYTHONPATH. The helper only reads /proc; it does
 # not kill processes, modify files, alter permissions or change system settings.
 privileged = r"""
import json,os,pathlib,sys
request=json.loads(sys.argv[1]);roots=request['roots'];packages=set(request['packages']);uid=request['uid']
for item in request['processes']:
 p=pathlib.Path('/proc')/str(int(item['pid']))
 try:
  owner=p.stat().st_uid
  started=(p/'stat').read_text().rsplit(')',1)[1].split()[19]
  if owner!=uid or started!=item['started']:raise SystemExit('Process identity changed; rerun cleanup: '+p.name)
  executable=os.readlink(p/'exe').removesuffix(' (deleted)')
  args=(p/'cmdline').read_bytes().decode(errors='replace').split('\0')
  if p.stat().st_uid!=uid or (p/'stat').read_text().rsplit(')',1)[1].split()[19]!=started:
   raise SystemExit('Process identity changed during inspection: '+p.name)
 except (FileNotFoundError,ProcessLookupError):continue
 except OSError as exc:raise SystemExit('Privileged process inspection failed; no deletion: '+str(exc))
 if executable in packages or any(executable==r or executable.startswith(r+'/') for r in roots) or any(a==r or a.startswith(r+'/') for a in args for r in roots):
  raise SystemExit('A legacy runtime is still running (PID '+p.name+'). Close it and rerun.')
"""
 payload={'uid':os.getuid(),'roots':roots,'packages':list(package_files),'processes':unreadable}
 try:result=subprocess.run(['/usr/bin/sudo','/usr/bin/python3','-I','-c',privileged,json.dumps(payload)],check=False)
 except OSError as exc:raise SystemExit('Read-only sudo inspection unavailable; no deletion: '+str(exc))
 if result.returncode:raise SystemExit('Read-only process verification failed or was declined; no deletion performed.')

PY
if (( ${#packages[@]} )); then sudo apt-get remove "${packages[@]}"; fi
check_paths
for p in "${paths[@]}"; do [[ ! -e $p ]] || rm -rf --one-file-system -- "$p"; done
if [[ $remove_shim == true && -L $shim && $(readlink "$shim") == "$data/strata/terminal/current/bin/strata" ]]; then rm -- "$shim"; fi
systemctl --user daemon-reload || true
# The previous installer did not author a user override unit. Preserve that config;
# apt removes the vendor unit it owns after the service has been disabled.
printf '%s\n' 'Legacy app uninstall and listed runtime/model deletion completed. No quarantine or new backup was created.' 'Chat/history/config/state, external models, prior backups and unrelated packages were preserved. Install Colibri with ./configure-ai.sh.'
