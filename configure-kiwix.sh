#!/usr/bin/env bash
# Install and register the local Kiwix MCP bridge; archive download is separate.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user, without sudo.' >&2; exit 1; fi
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
command -v uv >/dev/null
command -v omp >/dev/null
base="$HOME/.local/share/kiwix-mcp"
repo="$base/server"
archives="${KIWIX_ARCHIVE_DIR:-$base/archives}"
mkdir -p "$base" "$archives"
if [[ -d "$repo/.git" ]]; then
  echo "Keeping existing checkout $repo."
elif [[ -e "$repo" ]]; then
  echo "Refusing to overwrite $repo" >&2; exit 1
else
  git clone --depth 1 https://github.com/roanpy/kiwix-mcp.git "$repo"
fi
(cd "$repo" && uv sync --frozen)
agent_dir=$(omp config path)
mkdir -p "$agent_dir"
python3 - "$agent_dir/mcp.json" "$repo" "$archives" "$(command -v uv)" <<'PYCODE'
import json, os, pathlib, sys, tempfile
path, repo, archive, uv = sys.argv[1:]
p = pathlib.Path(path)
data = json.loads(p.read_text()) if p.exists() else {}
if not isinstance(data, dict) or not isinstance(data.setdefault('mcpServers', {}), dict):
    raise SystemExit('Invalid MCP configuration; refusing to change it')
server = {'type':'stdio','command':uv,'args':['run','--frozen','python','server.py'],
          'cwd':repo,'env':{'KIWIX_ARCHIVE_DIR':archive}}
old = data['mcpServers'].get('kiwix')
if old is not None and old != server:
    raise SystemExit('Existing kiwix MCP configuration differs; leaving it unchanged')
data['mcpServers']['kiwix'] = server
fd, tmp = tempfile.mkstemp(dir=p.parent, prefix='.mcp-', text=True)
try:
    with os.fdopen(fd, 'w') as f: json.dump(data, f, indent=2); f.write('\n')
    os.replace(tmp, p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PYCODE
echo "Kiwix MCP registered. Put ZIM archives in $archives and restart Oh My Pi."
