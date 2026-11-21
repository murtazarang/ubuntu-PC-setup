#!/usr/bin/env bash
# Fresh local-AI provisioning only. Never uninstalls another stack.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PATH="$HOME/.local/bin:$PATH"
profile=${1:-auto}
case "$profile" in
 auto)
   if command -v nvidia-smi >/dev/null && gpus=$(nvidia-smi --query-gpu=name --format=csv,noheader); then
     mapfile -t gpus <<<"$gpus"
     if (( ${#gpus[@]} == 2 )) && [[ ${gpus[0]} == *'RTX 3060' && ${gpus[1]} == *'RTX 3060' ]]; then profile=NvidiaDual
     elif (( ${#gpus[@]} == 1 )) && [[ ${gpus[0]} == *'RTX 3080' ]]; then profile=NvidiaSingle; fi
   fi
   if [[ $profile == auto ]] && command -v vulkaninfo >/dev/null &&
      vulkaninfo --summary 2>/dev/null | grep -Ei 'Arc.*B580' >/dev/null; then profile=Intel; fi
   ;;
 NvidiaSingle|NvidiaDual|Intel) ;;
esac
case "$profile" in NvidiaSingle|NvidiaDual|Intel);;
 *) echo 'Use NvidiaSingle, NvidiaDual, or Intel; the GPU was not identified.' >&2; exit 2;;
esac
for cmd in uv curl git python3; do command -v "$cmd" >/dev/null || { echo "$cmd is required." >&2; exit 1; }; done
root="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup/local-ai"
mkdir -p -- "$root/scripts"
install -m 0644 "$here"/local_ai/*.py "$root/scripts/"
install -D -m 0644 "$here/local_ai/offline-wikipedia/SKILL.md" "$root/scripts/offline-wikipedia/SKILL.md"
export HERMES_HOME="$root/hermes-home"
hermes_commit=caafe5389ae585ef77387a962aee05b1bcf17029
hermes="$HERMES_HOME/hermes-agent/.hermes/bin/hermes"
if [[ ! -x $hermes ]] || [[ $(git -C "$HERMES_HOME/hermes-agent" rev-parse HEAD) != "$hermes_commit" ]]; then
  if [[ -e "$HERMES_HOME/hermes-agent/.git" ]] &&
     [[ -n $(git -C "$HERMES_HOME/hermes-agent" status --porcelain --untracked-files=no) ]]; then
    echo 'Local Hermes source modifications were not overwritten.' >&2; exit 1
  fi
  curl -fsSL --retry 3 "https://raw.githubusercontent.com/NousResearch/hermes-agent/$hermes_commit/scripts/install.sh" -o "$root/hermes-install.sh"
  env -u HERMES_REPO_URL -u HERMES_RUNTIME_DIR -u HERMES_INSTALL_CHANNEL bash "$root/hermes-install.sh" --hermes-home "$HERMES_HOME" --dir "$HERMES_HOME/hermes-agent" --commit "$hermes_commit" --non-interactive --skip-browser --skip-computer-use
fi
[[ $(git -C "$HERMES_HOME/hermes-agent" rev-parse HEAD) == "$hermes_commit" ]] || { echo 'Hermes release pin not installed.' >&2; exit 1; }
# Checkout-local launchers are emitted by the vendor installer. Do not resolve
# through PATH, which could select an independent Hermes installation.
[[ -x "$hermes" ]] || { echo "Hermes checkout launcher not found: $hermes" >&2; exit 1; }

export KIWIX_REFERENCE_MANIFEST="$root/reference.json"
"$here/download-wikipedia.sh"
UV_TOOL_DIR="$root/openzim/tools" UV_TOOL_BIN_DIR="$root/openzim/bin" uv tool install --python 3.12 'openzim-mcp==3.4.0'
bridge="$root/openzim/bin/openzim-mcp"
"$bridge" --help >/dev/null
uv run --no-project --python 3.12 --with 'PyYAML==6.0.3' python "$root/scripts/local_setup.py" configure --root "$root" --profile "$profile" --hermes "$hermes" --bridge "$bridge" --reference "$KIWIX_REFERENCE_MANIFEST"
python3 "$root/scripts/local_setup.py" shortcuts --root "$root" --profile "$profile"
printf 'Local AI is installed. Open Start Local AI from the application menu. Use Stop Local AI to free model memory.\n'
