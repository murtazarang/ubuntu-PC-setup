#!/usr/bin/env bash
# Explicit existing-PC legacy cleanup; called before installing the replacement stack.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
export PATH="$HOME/.local/bin:$PATH"
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
[[ ${1:-} == --cleanup-only ]] || { echo 'Run migrate-existing-ai.sh for the complete delete-first replacement workflow.' >&2; exit 2; }
# Protect every active replacement path before allowing legacy directory deletion.
python3 - "$base" "${XDG_DATA_HOME:-$HOME/.local/share}" <<'PYPROTECT'
import json,pathlib,sys
base,data=map(pathlib.Path,sys.argv[1:])
protected=[base,data/'pc-setup-colibri',pathlib.Path(__import__('os').environ.get('KIWIX_ARCHIVE_DIR',str(pathlib.Path.home()/'.local/share/kiwix-mcp/archives')))]
if (base/'reference.json').exists():
 reference=json.loads((base/'reference.json').read_text());protected.append(pathlib.Path(reference['archive']))
if (data/'pc-setup-colibri/managed-models.json').exists():
 models=json.loads((data/'pc-setup-colibri/managed-models.json').read_text())
 protected.extend(pathlib.Path(p) for p in models['roots'].values())
legacy=[data/'strata'/name for name in ('terminal','components','install','models','packs','mtp','Strata-data')]+[data/'xestrata'/name for name in ('models','packs','mtp')]
for keep in protected:
 candidates=[keep]
 if keep.is_dir():candidates.extend(p for p in keep.rglob('*') if p.is_symlink())
 for candidate in candidates:
  resolved=candidate.resolve()
  for old in legacy:
   if resolved==old.resolve() or old.resolve() in resolved.parents:
    raise SystemExit('Active replacement data is inside or linked into a legacy deletion directory: '+str(candidate)+'. Cleanup stopped; relocate it deliberately before retrying.')
PYPROTECT
python3 "$here/remove-omp-runtime.py" --check
python3 "$here/remove-old-omp-skills.py" --check
# Clean only identified legacy paths after the explicit irreversible confirmation.
bash "$here/remove-legacy-ai.sh" --apply
python3 - "${XDG_DATA_HOME:-$HOME/.local/share}" <<'PYLEGACYABSENCE'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
paths=[root/'strata'/n for n in ('terminal','components','install','models','packs','mtp','Strata-data')]+[root/'xestrata'/n for n in ('models','packs','mtp')]
remaining=[str(p) for p in paths if p.exists() or p.is_symlink()]
if remaining:raise SystemExit('Legacy runtime/model directories remain; OMP retained: '+', '.join(remaining))
PYLEGACYABSENCE
for runtime in strata xestrata paseo; do
 if command -v "$runtime" >/dev/null; then
  echo "Legacy runtime remains on PATH: $(command -v "$runtime"). OMP was retained; inspect this installation." >&2; exit 1
 fi
done
for package in paseo xestrata xestrata-contrib-cuda13.1; do
 if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
  echo "Legacy package remains installed: $package. OMP was retained." >&2; exit 1
 fi
done
if pgrep -u "$(id -u)" -x omp >/dev/null; then
 echo 'Close the running OMP application, then rerun migration; it was not stopped automatically.' >&2; exit 1
fi
python3 "$here/remove-omp-runtime.py"
python3 "$here/remove-old-omp-skills.py"
hash -r
if command -v omp >/dev/null; then
 echo 'OMP still resolves on PATH; migration cleanup is not complete.' >&2; exit 1
fi

