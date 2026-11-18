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
import os,pathlib,sys
roots=[str(pathlib.Path(x).absolute()) for x in sys.argv[1:]]
package_files=set(os.environ['PACKAGE_FILES'].splitlines())
for proc in pathlib.Path('/proc').glob('[0-9]*'):
 try:
  if proc.stat().st_uid!=os.getuid() or int(proc.name)==os.getpid():continue
  args=(proc/'cmdline').read_bytes().decode(errors='replace').split('\0')
  executable=os.readlink(proc/'exe').removesuffix(' (deleted)')
 except (OSError,ValueError):continue
 if executable in package_files or any(executable==root or executable.startswith(root+'/') for root in roots) or any(arg==root or arg.startswith(root+'/') for arg in args for root in roots):
  raise SystemExit('A legacy runtime is still running (PID '+proc.name+'). Close it and rerun; nothing was forcibly killed.')
PY
if (( ${#packages[@]} )); then sudo apt-get remove "${packages[@]}"; fi
check_paths
for p in "${paths[@]}"; do [[ ! -e $p ]] || rm -rf --one-file-system -- "$p"; done
if [[ $remove_shim == true && -L $shim && $(readlink "$shim") == "$data/strata/terminal/current/bin/strata" ]]; then rm -- "$shim"; fi
systemctl --user daemon-reload || true
# The previous installer did not author a user override unit. Preserve that config;
# apt removes the vendor unit it owns after the service has been disabled.
printf '%s\n' 'Legacy app uninstall and listed runtime/model deletion completed. No quarantine or new backup was created.' 'Chat/history/config/state, external models, prior backups and unrelated packages were preserved. Install Colibri with ./configure-ai.sh.'
