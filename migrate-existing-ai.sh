#!/usr/bin/env bash
# Existing Ubuntu PC migration only. Does not run desktop/system setup stages.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the logged-in desktop user, without sudo.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
profile=${1:-auto}
case "$profile" in auto|NvidiaSingle|NvidiaDual|Intel);; *) echo 'Usage: migrate-existing-ai.sh [NvidiaSingle|NvidiaDual|Intel|auto]' >&2;exit 2;;esac
# Direct raw-GitHub invocation has no companion files. Fetch the same main checkout.
if [[ ! -f $here/install-hermes-local-ai.sh ]]; then
 command -v curl >/dev/null && command -v python3 >/dev/null || { echo 'curl and python3 are required to fetch this migration.' >&2;exit 1; }
 temp=$(mktemp -d "${TMPDIR:-/tmp}/pc-ai-migration.XXXXXX")
 echo "Migration source files: $temp"
 curl -fL --retry 3 https://github.com/murtazarang/ubuntu-PC-setup/archive/refs/heads/main.zip -o "$temp/source.zip"
 python3 - "$temp/source.zip" "$temp" <<'PYZIP'
import pathlib,sys,zipfile,stat
with zipfile.ZipFile(sys.argv[1]) as z:
 for item in z.infolist():
  p=pathlib.PurePosixPath(item.filename)
  if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0]!='ubuntu-PC-setup-main' or stat.S_ISLNK(item.external_attr>>16):raise SystemExit('Unexpected repository archive entry')
 z.extractall(sys.argv[2])
 for item in z.infolist():
  if not item.is_dir():
   target=pathlib.Path(sys.argv[2])/item.filename
   if (item.external_attr>>16)&0o111:target.chmod(0o755)
PYZIP
 for file in migrate-existing-ai.sh install-hermes-local-ai.sh migrate-openwebui.sh retire-legacy-text.py; do
  [[ -f "$temp/ubuntu-PC-setup-main/$file" ]] || { echo "Downloaded release is missing $file; no cleanup started." >&2; exit 1; }
 done
 exec bash "$temp/ubuntu-PC-setup-main/migrate-existing-ai.sh" "$profile"
fi
export PATH="$HOME/.local/bin:$PATH"
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
for file in migrate-openwebui.sh retire-legacy-text.py; do
 [[ -f "$here/$file" ]] || { echo "Missing migration companion $file; no cleanup started." >&2; exit 1; }
done
for command in curl git python3 uv; do
 command -v "$command" >/dev/null || { echo "Missing prerequisite $command; no cleanup started." >&2; exit 1; }
done
# Reuse the verified corpus location from the existing stack; never silently
# download a second archive before discovering a different reference manifest.
new_reference="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup/local-ai/reference.json"
if [[ -e "$base/reference.json" || -L "$base/reference.json" || -e "$new_reference" || -L "$new_reference" ]]; then
 KIWIX_ARCHIVE_DIR=$(python3 - "$base/reference.json" "$new_reference" <<'PYARCHIVE'
import json,os,pathlib,sys
archives=[]
for raw in sys.argv[1:]:
 manifest=pathlib.Path(raw)
 if any(p.is_symlink() for p in (manifest,*manifest.parents)):
  raise SystemExit('Linked Wikipedia manifest; no cleanup or download started.')
 if not manifest.exists():
  continue
 record=json.loads(manifest.read_text());value=record.get('archive')
 if not isinstance(value,str) or any(c in value for c in ('\n','\r','\0')):raise SystemExit('Invalid existing Wikipedia archive location')
 archive=pathlib.Path(value)
 if not archive.is_absolute() or archive.name!='wikipedia_en_all_nopic_2026-06.zim':raise SystemExit('Existing reference uses a different archive; preserved. Resolve that choice before downloading another corpus.')
 archives.append(archive.parent)
if not archives or any(path.resolve()!=archives[0].resolve() for path in archives):
 raise SystemExit('Wikipedia reference manifests disagree; no cleanup or download started.')
explicit=os.environ.get('KIWIX_ARCHIVE_DIR')
if explicit and pathlib.Path(explicit).resolve()!=archives[0].resolve():raise SystemExit('KIWIX_ARCHIVE_DIR conflicts with existing reference.json; no download started.')
print(archives[0])
PYARCHIVE
 )
 export KIWIX_ARCHIVE_DIR
fi
if [[ -n ${KIWIX_ARCHIVE_DIR:-} && $KIWIX_ARCHIVE_DIR != /* ]]; then
 echo 'Use an absolute KIWIX_ARCHIVE_DIR; no cleanup or download started.' >&2
 exit 1
fi
# The old OMP/Paseo/Strata cleanup is separate from retiring Open WebUI/Colibri text.
# Its helpers show inventories and ask for on-machine confirmation before permanent changes.
bash "$here/migrate-openwebui.sh" --cleanup-only
bash "$here/install-hermes-local-ai.sh" "$profile"
python3 "$here/retire-legacy-text.py"
echo 'Existing-PC AI migration finished. The Colibri image server and Open WebUI data were preserved.'
