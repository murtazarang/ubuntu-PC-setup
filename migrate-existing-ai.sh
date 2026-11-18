#!/usr/bin/env bash
# Existing Ubuntu PC migration only. Does not run desktop/system setup stages.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the logged-in desktop user, without sudo.' >&2; exit 1; }
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
profile=${1:-auto}
case "$profile" in auto|NvidiaSingle|NvidiaDual|Intel);; *) echo 'Usage: migrate-existing-ai.sh [NvidiaSingle|NvidiaDual|Intel|auto]' >&2;exit 2;;esac
# Direct raw-GitHub invocation has no companion files. Fetch the same main checkout.
if [[ ! -f $here/configure-openwebui.sh ]]; then
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
 exec bash "$temp/ubuntu-PC-setup-main/migrate-existing-ai.sh" "$profile"
fi
export PATH="$HOME/.local/bin:$PATH"
base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
# Reuse the verified corpus location from the existing stack; never silently
# download a second archive before discovering a different reference manifest.
if [[ -f "$base/reference.json" ]]; then
 KIWIX_ARCHIVE_DIR=$(python3 - "$base/reference.json" <<'PYARCHIVE'
import json,os,pathlib,sys
record=json.loads(pathlib.Path(sys.argv[1]).read_text());value=record.get('archive')
if not isinstance(value,str) or '\n' in value or '\r' in value:raise SystemExit('Invalid existing Wikipedia archive location')
archive=pathlib.Path(value)
if not archive.is_absolute() or archive.name!='wikipedia_en_all_nopic_2026-06.zim':raise SystemExit('Existing reference uses a different archive; preserved. Resolve that choice before downloading another corpus.')
explicit=os.environ.get('KIWIX_ARCHIVE_DIR')
if explicit and pathlib.Path(explicit).resolve()!=archive.parent.resolve():raise SystemExit('KIWIX_ARCHIVE_DIR conflicts with existing reference.json; no download started.')
print(archive.parent)
PYARCHIVE
 )
 export KIWIX_ARCHIVE_DIR
fi
# Explicitly approved delete-first migration; no replacement verification gate.
bash "$here/migrate-openwebui.sh" --cleanup-only
# Install only missing AI prerequisites, never drivers, gaming apps, Firefox or full desktop settings.
missing=false
for tool in curl git python3 tar sha256sum lspci; do command -v "$tool" >/dev/null || missing=true;done
if [[ $missing == true ]]; then
 sudo apt-get update
 sudo apt-get install --no-install-recommends -y curl git python3 pciutils ca-certificates coreutils tar
fi
if ! command -v uv >/dev/null; then curl -LsSf https://astral.sh/uv/install.sh | sh;fi
command -v uv >/dev/null
systemctl --user show-environment >/dev/null
bash "$here/configure-skills.sh"
bash "$here/download-wikipedia.sh"
bash "$here/configure-ai.sh" "$profile"
bash "$here/configure-openwebui.sh"
# Only this existing-PC path installs migration/removal companions.
python3 - "$here" "$base" <<'PYMIGRATE'
import pathlib,sys,shutil,json,hashlib
source,dest=map(pathlib.Path,sys.argv[1:])
# Exact unmodified migration helper published in repository commit 7efa03d.
known={'migrate-openwebui.sh':['472517c89ec78e5e57c22b0660b0832aa210be74f81936836085ea816d0cab77']}
names=['migrate-openwebui.sh','remove-omp-runtime.py','remove-legacy-ai.sh','remove-old-omp-skills.py']
for name in names:
 src=source/name;target=dest/name
 if not src.is_file():raise SystemExit('Missing migration companion: '+str(src))
 if any(p.is_symlink() for p in (target,*target.parents)):raise SystemExit('Refusing linked migration helper path')
 if target.exists() and target.read_bytes()!=src.read_bytes() and hashlib.sha256(target.read_bytes()).hexdigest() not in known.get(name,[]):raise SystemExit('Existing differing migration helper retained: '+str(target))
for name in names:shutil.copyfile(source/name,dest/name)
PYMIGRATE
bash "$base/launch-webui.sh"
echo 'Create or sign in to your local Open WebUI account in the browser at http://127.0.0.1:8080.'
read -r -p 'Press Enter when your account is ready to import and verify skills/Wikipedia: ' _
bash "$base/finish-openwebui.sh"
echo 'Existing-PC AI migration finished. Unrelated desktop applications and settings were not changed.'
