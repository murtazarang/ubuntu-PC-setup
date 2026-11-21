#!/usr/bin/env bash
# Preserve/resume existing bytes and verify the official full archive checksum.
set -Eeuo pipefail
(( EUID != 0 )) || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
dir="${KIWIX_ARCHIVE_DIR:-$HOME/.local/share/kiwix-mcp/archives}"
mkdir -p "$dir"
name=wikipedia_en_all_nopic_2026-06.zim
url="https://download.kiwix.org/zim/wikipedia/$name"
checksum=$(mktemp "$dir/.checksum.XXXXXX");trap 'rm -f -- "$checksum"' EXIT
echo 'Fetching official Wikipedia checksum; existing archive/partial downloads are preserved.'
curl -fL --retry 3 --connect-timeout 30 --max-time 180 "$url.sha256" -o "$checksum"
expected=$(python3 - "$checksum" "$name" <<'PY'
import pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text().strip()
m=re.fullmatch(r'([0-9a-fA-F]{64})(?:\s+\*?([^\r\n]+))?',text)
if not m or (m[2] and m[2]!=sys.argv[2]): raise SystemExit('Invalid official checksum response')
print(m[1].lower())
PY
)
file="$dir/$name"
if [[ ! -f $file ]]; then
 file="$file.part"
 echo "Downloading to $file; rerun to resume."
 curl -fL --retry 3 --connect-timeout 30 --continue-at - -o "$file" "$url"
fi
echo 'Verifying full Wikipedia SHA-256; this can take several minutes.'
actual=$(sha256sum -- "$file");actual=${actual%% *}
[[ $actual == "$expected" ]] || { echo "Checksum mismatch: $file. File retained; no archive marked complete." >&2; exit 1; }
if [[ $file == *.part ]]; then mv -- "$file" "$dir/$name";fi
echo "Verified: $dir/$name"

base="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui"
python3 - "${KIWIX_REFERENCE_MANIFEST:-$base/reference.json}" "$dir/$name" "$expected" <<'PYRECORD'
import json,os,pathlib,sys,tempfile
p=pathlib.Path(sys.argv[1]);record={'archive':str(pathlib.Path(sys.argv[2]).absolute()),'sha256':sys.argv[3]}
if any(q.is_symlink() for q in (p,*p.parents)): raise SystemExit('Refusing linked verification record path')
p.parent.mkdir(parents=True,exist_ok=True)
if p.exists() and json.loads(p.read_text()) != record: raise SystemExit('Existing different verification record preserved; inspect it before migration.')
fd,tmp=tempfile.mkstemp(dir=p.parent,prefix='.reference-')
try:
 with os.fdopen(fd,'w') as f:json.dump(record,f);f.write('\n')
 os.replace(tmp,p)
finally:
 if os.path.exists(tmp):os.unlink(tmp)
PYRECORD
