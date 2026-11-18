#!/usr/bin/env bash
# Install Colibri's built-in browser UI; download models interactively in that UI.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for c in curl python3 tar sha256sum; do command -v "$c" >/dev/null || { echo "Missing $c; run install-apps.sh first." >&2; exit 1; }; done
"$here/configure-skills.sh"
version=v2.1.0
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-colibri"
release="$base/$version"
asset="colibri-$version-linux-x86_64.tar.gz"
[[ $(uname -m) == x86_64 ]] || { echo 'This installer supports x86_64 PCs only.' >&2; exit 1; }
mkdir -p "$base" "$HOME/.local/bin" "$HOME/colibri-models"
if [[ ! -f $release/.pc-setup-complete ]]; then
  stage=$(mktemp -d "$base/.stage.XXXXXX"); trap 'rm -rf -- "$stage"' EXIT
  url="https://github.com/JustVugg/colibri/releases/download/$version"
  curl -fL --retry 3 "$url/$asset" -o "$stage/$asset"
  curl -fL --retry 3 "$url/SHA256SUMS.txt" -o "$stage/SHA256SUMS.txt"
  (cd "$stage"; awk -v n="$asset" '$2==n || $2=="*"n {print}' SHA256SUMS.txt > check; [[ $(wc -l < check) == 1 ]]; sha256sum -c check)
  mkdir "$stage/release"; tar -xzf "$stage/$asset" -C "$stage/release"
  [[ -f $stage/release/coli && -f $stage/release/ui/server.py ]] || { echo 'Unexpected Colibri archive layout.' >&2; exit 1; }
  python3 "$stage/release/coli" ui --help >/dev/null
  [[ ! -e $release ]] || { echo "Incomplete/unmanaged release already exists: $release; inspect it before retrying." >&2; exit 1; }
  touch "$stage/release/.pc-setup-complete"; mv "$stage/release" "$release"
fi
# Expose the upstream CLI unchanged; no custom model-launch wrapper.
link="$HOME/.local/bin/coli"
if [[ -e $link || -L $link ]]; then
 [[ -L $link && $(readlink "$link") == "$release/coli" ]] || { echo "Existing unrelated coli command: $link; refusing to replace it." >&2; exit 1; }
else
 ln -s "$release/coli" "$link"
fi
printf '%s\n' 'Colibri installed. Native UI: coli ui --models-dir "$HOME/colibri-models"'
printf '%s\n' 'Download a model in Models, then start the first gateway with the native coli serve command documented in README.md.'
