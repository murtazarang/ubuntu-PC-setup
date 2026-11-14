#!/usr/bin/env bash
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
path=/etc/firefox/policies/policies.json
if sudo test -f "$path"; then sudo cat "$path" | cat > "$tmp/existing.json"; else echo '{}' > "$tmp/existing.json"; fi
python3 "$here/firefox-policy.py" "$@" < "$tmp/existing.json" > "$tmp/policies.json"
python3 -m json.tool "$tmp/policies.json" >/dev/null
sudo install -d -m 755 /etc/firefox/policies
if sudo test -f "$path"; then sudo cp -a "$path" "$path.backup.$(date +%s)"; fi
sudo install -m 644 "$tmp/policies.json" "$path"
if [[ ${1:-} == --release ]]; then
  echo 'Filter/list overwrite policy removed; future uBlock edits can persist. Restart Firefox.'
else
  echo 'Restart Firefox twice and verify uBlock settings, then run ./configure-firefox.sh --release.'
  echo 'Until release, managed My filters and list selections reset on Firefox startup.'
fi
