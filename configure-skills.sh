#!/usr/bin/env bash
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
python3 "$here/openwebui_skills.py" prepare --root "$base/skill-repos"
echo 'After creating your local Open WebUI account, finish the new stack with:'
printf 'bash %q\n' "$base/finish-openwebui.sh"
