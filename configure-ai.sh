#!/usr/bin/env bash
# Run on the installed PC after the driver reboot and after install-apps.sh.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
for c in jq curl lspci omp uv; do command -v "$c" >/dev/null || { echo "Missing $c; run the previous stages first." >&2; exit 1; }; done
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
available_kib=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
if [[ $available_kib =~ ^[0-9]+$ ]] && (( available_kib < 120 * 1024 * 1024 )); then
  echo "Warning: less than 120 GiB free in HOME; model downloads and preparation can require 60–120 GB or more. Check free space before continuing." >&2
fi
"$here/configure-skills.sh"
# Preserve existing Paseo settings; enable only its built-in OMP provider.
mkdir -p "$HOME/.paseo"
/usr/bin/python3 - "$HOME/.paseo/config.json" <<'PY'
import json,os,sys,tempfile,shutil
p=sys.argv[1]
if os.path.exists(p):
 with open(p) as f: data=json.load(f)
else: data={}
assert isinstance(data,dict)
omp=data.setdefault('agents',{}).setdefault('providers',{}).setdefault('omp',{})
omp['enabled']=True
omp['command']=[shutil.which('omp') or os.path.expanduser('~/.local/bin/omp')]
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(p)); os.fchmod(fd,0o600)
with os.fdopen(fd,'w') as f: json.dump(data,f,indent=2);f.write('\n')
os.replace(tmp,p)
PY
graphics=$(lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
if grep -qi nvidia <<<"$graphics"; then
  command -v nvidia-smi >/dev/null || { echo 'NVIDIA driver not ready. Reboot and verify nvidia-smi.' >&2; exit 1; }
  count=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)
  if [[ $count == 2 ]]; then model=iq3_xxs; roles=(--gpu-roles "0=main,1=helper")
  elif [[ $count == 1 ]]; then model=iq2_xs; roles=()
  else echo "Expected one or two NVIDIA GPUs; found $count." >&2; exit 1; fi
  if ! command -v strata >/dev/null; then
    tmp=$(mktemp); trap 'rm -f -- "$tmp"' EXIT
    curl -fsSL --retry 3 https://github.com/Niko1221/Strata/releases/latest/download/install.sh -o "$tmp"
    sh "$tmp"
    export PATH="$HOME/.local/bin:$PATH"
  fi
  command -v strata >/dev/null || { echo 'Strata not found on PATH after installation.' >&2; exit 1; }
  # Deliberately local-only; no LAN listener or paid AI service.
  strata launch --family qwen --model "$model" --context 32k --access local --vision off --yes --no-tui "${roles[@]}"
  "$here/connect-xestrata.sh" 8080
elif grep -qi intel <<<"$graphics"; then
  # Package recommended upstream for Ubuntu 26.04 Intel GPU.
  tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT
  release=$(curl -fsSL https://api.github.com/repos/MistVVK/XeStrata/releases/latest)
  deb=$(jq -er '[.assets[] | select(.name|test("^xestrata-contrib-cuda13\\.1_.*_amd64\\.deb$"))] | if length == 1 then .[0] else error("Expected one Intel-compatible XeStrata deb") end' <<<"$release")
  name=$(jq -r .name <<<"$deb"); url=$(jq -r .browser_download_url <<<"$deb")
  sums=$(jq -er '[.assets[]|select(.name == "SHA256SUMS")|.browser_download_url] | if length == 1 then .[0] else error("Missing checksums") end' <<<"$release")
  curl -fL --retry 3 "$url" -o "$tmpdir/$name"
  curl -fL --retry 3 "$sums" -o "$tmpdir/SHA256SUMS"
  (cd "$tmpdir"; grep -F "  $name" SHA256SUMS | sha256sum -c -)
  sudo apt-get install -y "$tmpdir/$name"
  if ! id -nG | tr ' ' '\n' | grep -qx render; then
    sudo usermod -aG render "$USER"
    echo 'Added your user to render. Log out and back in, then rerun this script.'; exit 75
  fi
  xestrata --setup --family gyro --model Gyro-S --context 32768 --vision no --yes --no-start
  systemctl --user start xestrata
  echo 'Waiting for the local model to start (this may take several minutes)...'
  ready=false
  for _ in {1..120}; do if curl -fsS --max-time 3 http://127.0.0.1:8095/v1/models >/dev/null; then ready=true; break; fi; sleep 5; done
  if [[ $ready == true ]]; then "$here/connect-xestrata.sh" 8095; else echo 'XeStrata is still starting; once ready run ./connect-xestrata.sh 8095.' >&2; exit 1; fi
else
  echo 'No supported discrete NVIDIA/Intel graphics device found.' >&2; exit 1
fi
echo 'Start or restart Paseo so it reads its updated OMP provider configuration.'
