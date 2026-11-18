#!/usr/bin/env bash
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
python3 "$here/openwebui_skills.py" prepare --root "$base/skill-repos"
echo 'After creating your local Open WebUI account, migrate skills, verify Wikipedia and offer OMP removal:'
printf 'bash %q\n' "$base/migrate-openwebui.sh"
echo 'Existing OMP skills and user-created files are preserved. Removal requires explicit confirmation after verification.'
