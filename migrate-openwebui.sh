#!/usr/bin/env bash
# Verify full migration before uninstalling the OMP executable installed by this setup.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
export PATH="$HOME/.local/bin:$PATH"
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
# Interactive sign-in is local to WebUI. Import failure stops before any deletion.
bash "$here/finish-openwebui.sh"
# Protect every active replacement path before allowing legacy directory deletion.
python3 - "$base" "${XDG_DATA_HOME:-$HOME/.local/share}" <<'PYPROTECT'
import json,pathlib,sys
base,data=map(pathlib.Path,sys.argv[1:])
reference=json.loads((base/'reference.json').read_text())
models=json.loads((data/'pc-setup-colibri/managed-models.json').read_text())
if models.get('owner')!='ubuntu-PC-setup' or not isinstance(models.get('roots'),dict) or not models['roots']:raise SystemExit('Missing verified active model inventory; run the existing-PC migration installer first.')
protected=[base,base/'skill-repos',pathlib.Path(reference['archive']),*[pathlib.Path(p) for p in models['roots'].values()]]
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
# Verify first, then clean legacy apps while their configuration is still available.
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
hash -r
if command -v omp >/dev/null; then
 echo 'OMP still resolves on PATH; migration cleanup is not complete.' >&2; exit 1
fi
