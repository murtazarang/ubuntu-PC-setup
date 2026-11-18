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
python3 - "$here" "$base" <<'PYHELPER'
import pathlib,sys,shutil
source,dest=map(pathlib.Path,sys.argv[1:])
names=['openwebui_gpu.py','openwebui_skills.py','openwebui_connections.py','finish-openwebui.sh']
for name in names:
 src=source/name;target=dest/name
 if not src.is_file():raise SystemExit('Missing setup companion: '+str(src))
 if any(p.is_symlink() for p in (target,*target.parents)):raise SystemExit('Refusing linked helper destination')
 if target.exists() and target.read_bytes()!=src.read_bytes():raise SystemExit('Existing differing helper retained: '+str(target))
for name in names:shutil.copyfile(source/name,dest/name)
PYHELPER
export DATA_DIR="$base/data"
export RAG_EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
export RAG_RERANKING_MODEL=cross-encoder/ms-marco-MiniLM-L6-v2
export RAG_EMBEDDING_QUERY_PREFIX='Represent this sentence for searching relevant passages: '
export RAG_EMBEDDING_CONTENT_PREFIX=''
export RAG_EMBEDDING_ENGINE='' RAG_RERANKING_ENGINE=''
export ENABLE_RAG_HYBRID_SEARCH=true CHUNK_SIZE=400 CHUNK_OVERLAP=50
export RAG_TEXT_SPLITTER=token_transformers RAG_TOKENIZER_MODEL=BAAI/bge-small-en-v1.5
export RAG_EMBEDDING_MODEL_TRUST_REMOTE_CODE=false RAG_RERANKING_MODEL_TRUST_REMOTE_CODE=false
backend_args=()
if command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null; then
  uv tool install --torch-backend cu128 --with torch==2.9.1 --with torchvision==0.24.1 --with sentence-transformers==5.5.1 --python 3.11 open-webui==0.13.4
  "$base/tools/open-webui/bin/python" -c "import torch; assert torch.cuda.is_available(), 'Open WebUI CUDA is unavailable; no CPU fallback will be configured.'; print('Open WebUI CUDA devices:', torch.cuda.device_count())"
  USE_CUDA_DOCKER=true USE_SLIM_DOCKER=false SENTENCE_TRANSFORMERS_BACKEND=torch SENTENCE_TRANSFORMERS_CROSS_ENCODER_BACKEND=torch SENTENCE_TRANSFORMERS_MODEL_KWARGS='{}' SENTENCE_TRANSFORMERS_CROSS_ENCODER_MODEL_KWARGS='{}' "$base/tools/open-webui/bin/python" "$base/openwebui_gpu.py" probe-cuda --embedding-model "$RAG_EMBEDDING_MODEL" --reranking-model "$RAG_RERANKING_MODEL"

elif command -v lspci >/dev/null && lspci -nn | grep -Ei '(VGA|Display).*Intel.*(B580|Battlemage)' >/dev/null; then
  OPENWEBUI_EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
  OPENWEBUI_RERANKING_MODEL=cross-encoder/ms-marco-MiniLM-L6-v2
  # PyTorch is a library dependency here; embeddings/reranking execute on B580 OpenVINO GPU.
  uv tool install --torch-backend cpu --with torch==2.9.1 --with torchvision==0.24.1 --with 'sentence-transformers[openvino]==5.5.1' --with 'optimum-intel[openvino]==2.2.0' --with openvino==2026.4.1 --python 3.11 open-webui==0.13.4
  temp=$(mktemp "$base/.backend.XXXXXX");trap 'rm -f -- "$temp"' EXIT
  "$base/tools/open-webui/bin/python" "$base/openwebui_gpu.py" detect-openvino > "$temp"
  # Use Python to apply the JSON environment safely, never shell-evaluate JSON values.
  "$base/tools/open-webui/bin/python" - "$base/openwebui_gpu.py" "$temp" "$base/data" "$OPENWEBUI_EMBEDDING_MODEL" "$OPENWEBUI_RERANKING_MODEL" <<'PYPROBE'
import json,os,subprocess,sys
mapping=json.load(open(sys.argv[2]));env=os.environ.copy();env.update(mapping);env["DATA_DIR"]=sys.argv[3]
subprocess.run([sys.executable,sys.argv[1],'probe-openvino','--embedding-model',sys.argv[4],'--reranking-model',sys.argv[5]],env=env,check=True)
PYPROBE
  backend_args=(--backend-env "$temp")
else
  echo 'No supported NVIDIA GPU or Intel Arc B580 was detected; no CPU fallback configured.' >&2; exit 1
fi
uv tool install --python 3.12 --with mcp==1.30.0 --with fastapi==0.115.12 mcpo==0.0.20
uv tool install --python 3.12 openzim-mcp==3.4.0
"$base/bin/open-webui" serve --help >/dev/null
"$base/bin/mcpo" --help >/dev/null
"$base/bin/openzim-mcp" --help >/dev/null
python3 "$here/create-openwebui-services.py" --base "$base" --archives "$archives" "${backend_args[@]}"
systemctl --user daemon-reload
# On-demand desktop start, not an always-on model consuming RAM at login.
echo 'Open WebUI installed. Use its desktop shortcut, create your local admin account, then complete the documented skills/Wikipedia import.'
