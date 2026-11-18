#!/usr/bin/env bash
# Verify full migration before uninstalling the OMP executable installed by this setup.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
# Interactive sign-in is local to WebUI. Import failure stops before any deletion.
python3 "$here/openwebui_skills.py" import --root "$base/skill-repos" --url http://127.0.0.1:8080 --wiki-key-file "$base/mcpo-key" --reference-manifest "$base/reference.json"
if pgrep -u "$(id -u)" -x omp >/dev/null; then
 echo 'Close the running OMP application, then rerun migration; it was not stopped automatically.' >&2; exit 1
fi
python3 "$here/remove-omp-runtime.py"
hash -r
if command -v omp >/dev/null; then
 echo 'OMP still resolves on PATH; migration cleanup is not complete.' >&2; exit 1
fi
