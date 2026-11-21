#!/usr/bin/env bash
# Safe checks on the actual Ubuntu PC. --model also sends one local prompt.
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
fail=0
check() { printf '\n== %s ==\n' "$1"; shift; "$@" || { echo 'FAILED or unavailable'; fail=1; }; }
check 'OS release' cat /etc/os-release
# shellcheck disable=SC2329  # invoked through check
check_root() {
 findmnt -no SOURCE,FSTYPE,FSROOT /
 [[ $(findmnt -n -o FSTYPE /) == btrfs && $(findmnt -n -o FSROOT /) == /@ ]]
}
check 'Root filesystem and subvolume' check_root
check 'Timeshift snapshots' sudo timeshift --list --btrfs
check 'Vulkan devices' vulkaninfo --summary
if command -v nvidia-smi >/dev/null; then
 check 'NVIDIA GPUs and driver' nvidia-smi -L
 # shellcheck disable=SC2329  # invoked through check
 check_nvidia_license() { local license; license=$(modinfo -F license nvidia) || return 1; echo "$license"; [[ $license == NVIDIA ]]; }
 check 'NVIDIA proprietary kernel module' check_nvidia_license
fi
for c in steam uv; do check "$c on PATH" command -v "$c"; done
for app in spotify code mailspring; do check "Snap: $app" snap list "$app"; done
if command -v flatpak >/dev/null && flatpak info --user com.stremio.Stremio >/dev/null 2>&1; then
 check 'Stremio Flatpak' flatpak info --user com.stremio.Stremio
else
 check 'Stremio package' dpkg-query -W stremio
fi
enabled=$(gnome-extensions list --enabled 2>/dev/null || true)
for extension in caffeine@patapon.info clipboard-history@alexsaveau.dev lightning-gnome-launcher@avimanyu; do
 if grep -Fxq "$extension" <<<"$enabled"; then echo "Enabled: $extension"; else echo "Not enabled: $extension (try logging out/in)"; fail=1; fi
done
root="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup/local-ai"
endpoint='http://127.0.0.1:8081/v1'
if [[ -r $root/desktop.json ]]; then
 profile=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile"])' "$root/desktop.json")
 check 'Hermes llama.cpp profile and context' python3 "$root/scripts/local_setup.py" status --root "$root" --profile "$profile"
else
 echo 'Setup-owned Local AI profile not found.'; fail=1
fi
if ! curl -fsS --max-time 3 "$endpoint/models" >/dev/null; then endpoint=''; fi
if [[ -n $endpoint ]]; then
 check 'Local inference models' curl -fsS --max-time 5 "$endpoint/models"
 if [[ ${1:-} == --model ]]; then
   model=$(curl -fsS "$endpoint/models" | jq -er '.data[0].id') || exit 1
   payload=$(jq -n --arg m "$model" '{model:$m,messages:[{role:"user",content:"Reply with exactly OK."}],max_tokens:16}')
   check 'Local inference smoke test' curl -fsS --max-time 300 -H 'Content-Type: application/json' -d "$payload" "$endpoint/chat/completions"
 fi
else echo 'Local model is not running; start it and rerun verification.'; fail=1
fi
printf '\nConfirm Firefox about:policies, uBlock settings, Super+F2, Steam Proton, a real game, and Hermes writing skills and Offline Wikipedia search and citation interactively.\n'
exit "$fail"
