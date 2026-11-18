#!/usr/bin/env bash
# Verify full migration before uninstalling the OMP executable installed by this setup.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
# Interactive sign-in is local to WebUI. Import failure stops before any deletion.
python3 "$here/openwebui_skills.py" import --root "$base/skill-repos" --url http://127.0.0.1:8080 --wiki-key-file "$base/mcpo-key" --reference-manifest "$base/reference.json"
target="$HOME/.local/bin/omp"
if [[ ! -e $target && ! -L $target ]]; then
 echo 'The default standalone OMP executable is absent. No custom installation was removed.'; exit 0
fi
[[ -f $target && ! -L $target ]] || { echo "Nonstandard OMP path retained: $target" >&2; exit 1; }
identity=$(python3 - "$target" <<'PY'
import pathlib,sys,json,hashlib
p=pathlib.Path(sys.argv[1])
if any(x.is_symlink() for x in (p,*p.parents)): raise SystemExit('OMP path is linked; refusing automatic removal.')
s=p.stat();print(json.dumps([s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,hashlib.sha256(p.read_bytes()).hexdigest()]))
PY
)
if pgrep -u "$(id -u)" -x omp >/dev/null; then
 echo 'Close the running OMP application, then rerun migration; it was not stopped automatically.' >&2; exit 1
fi
printf 'Verified migration. Remove standalone OMP executable: %s\n' "$target"
echo 'All skills, custom configuration, conversations, Wikipedia, shared packages and Bun are retained.'
read -r -p 'Type REMOVE OMP to uninstall this executable: ' answer
[[ $answer == 'REMOVE OMP' ]] || { echo 'OMP kept.'; exit 0; }
python3 - "$target" "$identity" <<'PY'
import pathlib,sys,json,hashlib
p=pathlib.Path(sys.argv[1])
if any(x.is_symlink() for x in (p,*p.parents)):raise SystemExit('OMP path changed while awaiting confirmation; retained.')
s=p.stat();actual=[s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,hashlib.sha256(p.read_bytes()).hexdigest()]
if actual!=json.loads(sys.argv[2]):raise SystemExit('OMP executable changed while awaiting confirmation; retained.')
p.unlink()
PY
echo 'Standalone OMP uninstalled. Open WebUI does not depend on it.'
