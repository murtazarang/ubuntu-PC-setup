#!/usr/bin/env bash
# Fresh-stack first-use configuration only. No legacy inventory or cleanup.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
python3 "$here/openwebui_skills.py" import --root "$base/skill-repos" --url http://127.0.0.1:8080 --wiki-key-file "$base/mcpo-key" --reference-manifest "$base/reference.json"
echo 'Open WebUI skills, reference and connection verification completed.'
