#!/usr/bin/env bash
# Download the English full-text snapshot without pictures; rerun to resume.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user, without sudo.' >&2; exit 1; fi
dir="${KIWIX_ARCHIVE_DIR:-$HOME/.local/share/kiwix-mcp/archives}"
mkdir -p "$dir"
name=wikipedia_en_all_nopic_2026-06.zim
url="https://download.kiwix.org/zim/wikipedia/$name"
if [[ -f "$dir/$name" ]]; then echo "Already present: $dir/$name"; exit 0; fi
echo "Downloading approximately 49 GiB to $dir. Rerun this command to resume if interrupted."
curl -fL --retry 3 --continue-at - -o "$dir/$name.part" "$url"
mv "$dir/$name.part" "$dir/$name"
echo "Downloaded $dir/$name"
