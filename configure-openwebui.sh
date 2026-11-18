#!/usr/bin/env bash
# Native Ubuntu install. Authenticated WebUI stays on loopback; no firewall changes.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
export PATH="$HOME/.local/bin:$PATH"
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
archives="${KIWIX_ARCHIVE_DIR:-$HOME/.local/share/kiwix-mcp/archives}"
command -v uv >/dev/null
systemctl --user show-environment >/dev/null
mkdir -p "$base" "$archives"
# Dedicated tools avoid changing independently installed user applications.
export UV_TOOL_DIR="$base/tools" UV_TOOL_BIN_DIR="$base/bin"
if ! uv tool install --help | grep -q -- '--torch-backend'; then
  echo 'This uv is too old for explicit WebUI dependency selection. Update uv, then rerun.' >&2; exit 1
fi
if ! command -v nvidia-smi >/dev/null || ! nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null; then
  echo 'Open WebUI GPU setup currently supports the NVIDIA PCs. Intel supporting-model backend awaits an explicit choice; no CPU fallback was installed.' >&2; exit 1
fi
uv tool install --torch-backend cu128 --with torch==2.9.1 --python 3.11 open-webui==0.13.4
uv tool install --python 3.12 --with mcp==1.30.0 --with fastapi==0.115.12 mcpo==0.0.20
uv tool install --python 3.12 openzim-mcp==3.4.0
"$base/tools/open-webui/bin/python" -c "import torch; assert torch.cuda.is_available(), 'Open WebUI CUDA is unavailable; no CPU fallback will be configured.'; print('Open WebUI CUDA devices:', torch.cuda.device_count())"
"$base/bin/open-webui" serve --help >/dev/null
"$base/bin/mcpo" --help >/dev/null
"$base/bin/openzim-mcp" --help >/dev/null
python3 "$here/create-openwebui-services.py" --base "$base" --archives "$archives"
systemctl --user daemon-reload
# On-demand desktop start, not an always-on model consuming RAM at login.
echo 'Open WebUI installed. Use its desktop shortcut, create your local admin account, then complete the documented skills/Wikipedia import.'
