#!/usr/bin/env bash
# Separate migration patch. Preview by default; no permanent deletion of model data.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user, not sudo.' >&2; exit 1; fi
if [[ ${1:-} == --purge-backup ]]; then
 [[ $# == 2 ]] || { echo 'Usage: ./remove-legacy-ai.sh --purge-backup BACKUP_DIRECTORY' >&2; exit 2; }
 root="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-legacy-ai-backup"
 target=$(realpath -e -- "$2")
 [[ $target == "$root/"* && -f $target/manifest.tsv && ! -L $2 ]] || { echo 'Not a recognized backup directory.' >&2; exit 1; }
 echo "This permanently deletes all archived files, including any models, inside $target"
 du -sh -- "$target"
 read -r -p 'Type the full backup directory to permanently delete it: ' answer
 [[ $answer == "$target" ]] || exit 1
 rm -rf -- "$target"
 exit 0
fi
[[ ${1:-} == '' || ${1:-} == --apply ]] || { echo 'Usage: ./remove-legacy-ai.sh [--apply] OR --purge-backup BACKUP_DIRECTORY' >&2; exit 2; }
data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}
paths=("$HOME/.paseo" "$data/strata" "$config/strata" "$state/strata" "$data/xestrata" "$config/xestrata" "$state/xestrata")
packages=()
for p in paseo xestrata xestrata-contrib-cuda13.1; do
 if dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null | grep -qx installed; then packages+=("$p"); fi
done
printf 'Legacy app packages to uninstall (shared dependencies retained): %s\n' "${packages[*]:-none}"
echo 'Existing app data/config directories to move into a recoverable backup:'
for p in "${paths[@]}"; do [[ ! -e $p ]] || printf '  %s\n' "$p"; done
printf '%s\n' 'External/custom model directories, shared Hugging Face caches, OMP, skills and Wikipedia are NOT deleted.' 'Review custom data_dir/model paths in old settings before deciding whether to delete any model files.'
[[ ${1:-} == --apply ]] || { echo 'Preview only. Run with --apply to confirm and perform the listed migration.'; exit 0; }
read -r -p 'Type REMOVE LEGACY AI to stop/uninstall these apps and archive the listed data: ' answer
[[ $answer == 'REMOVE LEGACY AI' ]] || exit 1
backup="$data/pc-setup-legacy-ai-backup/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$backup"; chmod 700 "$backup"
# Let the recognized upstream launcher stop its own instance, never kill generic Python.
if command -v strata >/dev/null; then strata launch --stop || { echo 'Strata stop failed; stop it manually before continuing.' >&2; exit 1; }; fi
# Only stop the known user service when its command names XeStrata.
if systemctl --user cat xestrata.service > "$backup/xestrata.service.txt" 2>/dev/null; then
 grep -Eq '^ExecStart=.*(xestrata|XeStrata)' "$backup/xestrata.service.txt" || { echo 'Unrecognized xestrata service; inspect before removal.' >&2; exit 1; }
 systemctl --user disable --now xestrata.service
fi
if (( ${#packages[@]} )); then sudo apt-get remove "${packages[@]}"; fi
# Record source -> backup mapping. mv preserves models rather than wiping them.
n=0
for p in "${paths[@]}"; do
 if [[ -e $p ]]; then n=$((n+1)); printf '%s\t%s\n' "$p" "$backup/$n" >> "$backup/manifest.tsv"; mv -- "$p" "$backup/$n"; fi
done
shim="$HOME/.local/bin/strata"
if [[ -f $shim ]] && grep -Fq "$data/strata" "$shim"; then mv -- "$shim" "$backup/strata-launcher"; fi
unit="$config/systemd/user/xestrata.service"
if [[ -f $unit ]] && grep -Eq '^ExecStart=.*(xestrata|XeStrata)' "$unit"; then mv -- "$unit" "$backup/xestrata.service"; systemctl --user daemon-reload; fi
printf 'Legacy migration finished. Recoverable backup: %s\n' "$backup"
echo 'To reclaim the archived disk space, review manifest.tsv and run this script with --purge-backup BACKUP_DIRECTORY; it requires a separate permanent-deletion confirmation.'
echo 'No model data was permanently deleted. Install Colibri with ./configure-ai.sh; connect OMP after starting a model with ./connect-colibri.sh.'
