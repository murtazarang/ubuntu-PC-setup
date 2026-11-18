#!/usr/bin/env bash
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
python3 "$here/openwebui_skills.py" prepare --root "$base/skill-repos"
echo 'After creating your Open WebUI account, import and verify every skill with:'
printf 'python3 %q import --root %q --url http://127.0.0.1:8080 --wiki-key-file %q --reference-manifest %q\n' "$here/openwebui_skills.py" "$base/skill-repos" "$base/mcpo-key" "$base/reference.json"
echo 'Existing OMP skills and user-created files have not been deleted.'
