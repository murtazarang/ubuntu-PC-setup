#!/usr/bin/env bash
# Setup only: download/import a model and create a native CLI desktop shortcut.
set -Eeuo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
release=${1:?Colibri release directory required}
profile=${2:-auto}
if [[ $profile == auto ]]; then
 if command -v nvidia-smi >/dev/null && gpu_names=$(nvidia-smi --query-gpu=name --format=csv,noheader) && [[ -n $gpu_names ]]; then
  count=$(printf '%s\n' "$gpu_names" | wc -l)
  if [[ $count == 2 && $(grep -c '3060' <<<"$gpu_names") == 2 ]]; then profile=NvidiaDual
  elif [[ $count == 1 && $gpu_names == *3080* ]]; then profile=NvidiaSingle
  else echo 'GPU profile is not one of the three configured PCs; specify NvidiaSingle, NvidiaDual or Intel.' >&2; exit 1; fi
 elif command -v lspci >/dev/null && lspci -nn | grep -Ei '(VGA|Display).*Intel.*(B580|Battlemage)' >/dev/null; then profile=Intel
 else echo 'Cannot identify a supported working GPU. Run configure-ai.sh NvidiaSingle, NvidiaDual or Intel explicitly after checking its driver.' >&2; exit 1; fi
fi
case $profile in
 NvidiaDual) key=flash-next-iq2-xs; extra=(--dual);;
 NvidiaSingle|Intel) key=dense27b; extra=();;
 *) echo 'Expected hardware profile NvidiaSingle, NvidiaDual or Intel.' >&2; exit 1;;
esac
root="${COLIBRI_MODELS_DIR:-$HOME/colibri-models}/$key"
source="$root/source"; model="$root/model"
mkdir -p "$root"
python3 "$here/download_colibri_model.py" --model "$key" --destination "$source"
shard=$(python3 - "$here/colibri-models.json" "$key" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))[sys.argv[2]]
if m['format'] != 'gguf': raise SystemExit('Expected a text GGUF model')
print(m['first_shard'])
PY
)
if [[ -L $model ]]; then echo "Refusing symlinked imported model directory: $model" >&2; exit 1; fi
if [[ -e $model ]]; then
 python3 - "$model" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); marker=p/'.pc-setup-import.json'
if not marker.is_file(): raise SystemExit('Existing model folder is not owned by setup; preserved.')
expected=json.loads(marker.read_text())
actual={str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in p.rglob('*') if f.is_file() and f!=marker}
if expected!=actual: raise SystemExit('Imported model was customized; preserved. Choose another COLIBRI_MODELS_DIR.')
PY
fi
# Small imported metadata only; link mode leaves the large verified GGUF in source.
stage=$(mktemp -d "$root/.import.XXXXXX"); trap 'rm -rf -- "$stage"' EXIT
python3 "$release/coli" import "$source/$shard" --out "$stage" --mode link --no-mtp
python3 - "$stage" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
for name in ('config.json','tokenizer.json','gguf.json'):
 if not (p/name).is_file(): raise SystemExit('Import missing '+name)
files={str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in p.rglob('*') if f.is_file()}
(p/'.pc-setup-import.json').write_text(json.dumps(files,sort_keys=True))
PY
if [[ -e $model ]]; then mv "$model" "$root/model.previous.$(date -u +%Y%m%dT%H%M%SZ).$$"; fi
mv "$stage" "$model"; trap - EXIT
icon_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
mkdir -p "$icon_dir"
cp "$here/assets/colibri/colibri-serve.svg" "$icon_dir/pc-setup-colibri-serve.svg"
python3 "$here/create-colibri-shortcuts.py" --cli "$release/coli" --model "$model" --icon "$icon_dir/pc-setup-colibri-serve.svg" "${extra[@]}"
echo "Colibri text model ready: $model"
echo 'Use Colibri Serve to start the local server. This text-only GGUF does not accept images/video.'

# Image checkpoint is native: no conversion or GGUF import.
image_model="${COLIBRI_MODELS_DIR:-$HOME/colibri-models}/qwen-image-2.1/model"
python3 "$here/download_colibri_model.py" --model qwen-image-2.1 --destination "$image_model"
venv="${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-colibri/image-python"
if [[ ! -x $venv/bin/python ]]; then
 [[ ! -e $venv ]] || { echo "Incomplete image Python environment: $venv" >&2; exit 1; }
 uv venv --python 3.11 "$venv"
fi
uv pip install --python "$venv/bin/python" numpy Pillow
cp "$here/assets/colibri/colibri-serve-image.svg" "$icon_dir/pc-setup-colibri-serve-image.svg"
python3 "$here/create-colibri-shortcuts.py" --cli "$release/coli" --python "$venv/bin/python" --model "$image_model" --icon "$icon_dir/pc-setup-colibri-serve-image.svg" --image
echo 'Colibri Serve Image uses loopback port 8001. Run text and image separately unless memory permits both.'
echo 'Qwen-Image-2.1 is licensed for research/evaluation; see its downloaded LICENSE.'

systemctl --user daemon-reload
