#!/usr/bin/env bash
# Install both complete skill repositories for Oh My Pi; run as the desktop user.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run without sudo as the desktop user.' >&2; exit 1; fi
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
command -v omp >/dev/null || { echo 'Install Oh My Pi first.' >&2; exit 1; }
root="$HOME/.local/share/omp-skills"
mkdir -p "$root"
clone_or_keep() {
  local url=$1 dest=$2
  if [[ -d $dest/.git ]]; then
    echo "Keeping existing checkout $dest; update it deliberately when desired."
  elif [[ -e $dest ]]; then
    echo "Refusing to overwrite $dest" >&2; exit 1
  else
    git clone --depth 1 "$url" "$dest"
  fi
}
clone_or_keep https://github.com/K-Dense-AI/scientific-agent-skills.git "$root/scientific-agent-skills"
clone_or_keep https://github.com/K-Dense-AI/claude-scientific-writer.git "$root/claude-scientific-writer"
writer="$root/claude-scientific-writer/skills"
science="$root/scientific-agent-skills/skills"
[[ -d $writer && -d $science ]] || { echo 'Expected skills directories missing.' >&2; exit 1; }
existing=$(omp config get skills.customDirectories --json | jq -ec '.value | if type == "array" then . else error("not an array") end')
merged=$(jq -cn --argjson old "$existing" --arg w "$writer" --arg s "$science" 'reduce ($old + [$w,$s])[] as $item ([]; if index($item) then . else . + [$item] end)')
omp config set skills.customDirectories "$merged"
omp config set skills.enabled true
omp config set skills.enableSkillCommands true
agent_dir=$(omp config path)
mkdir -p "$agent_dir"
rules="$agent_dir/RULES.md"
if ! grep -Fq '<!-- ubuntu-pc-setup-local-ai -->' "$rules" 2>/dev/null; then
  cat >> "$rules" <<'RULE'

<!-- ubuntu-pc-setup-local-ai -->
Use the configured local language model by default. Imported scientific skills may describe K-Dense, Anthropic, or other hosted AI services; do not require their accounts or use those services unless the user explicitly chooses to do so. Use locally available tools where suitable and report when a requested operation requires an unavailable external service. Users remain free to configure and use other Oh My Pi providers. Shared Python packages are in ~/.local/share/omp-scientific-tools/venv; invoke its bin/python or use uv. Shared Node packages are in ~/.local/share/omp-scientific-tools/js/node_modules; set NODE_PATH to that directory when needed.
<!-- /ubuntu-pc-setup-local-ai -->
RULE
fi
printf 'Scientific skills: '; find "$science" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l
printf 'Writer skills: '; find "$writer" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l
omp skill list --json > "$root/installed-skills.json"
/usr/bin/python3 - "$root/installed-skills.json" "$writer" "$science" <<'PYCODE'
import json,os,pathlib,sys
inventory, *roots=sys.argv[1:]
with open(inventory) as f: listed=json.load(f)
actual={os.path.realpath(x['filePath']) for x in listed['skills']}
expected={os.path.realpath(p) for root in roots for p in pathlib.Path(root).glob('*/SKILL.md')}
missing=sorted(expected-actual)
if missing:
 print('OMP did not load these skill definitions:', *missing, sep='\n',file=sys.stderr)
 raise SystemExit(1)
print(f'OMP discovered all {len(expected)} skill definitions.')
PYCODE
echo "Registered both full skill trees. Inventory: $root/installed-skills.json"
