#!/usr/bin/env bash
# Connect OMP to the local Colibri instance after it has started.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
port=${1:-8000}
[[ $port =~ ^(8000)$ ]] || { echo "Expected local port 8000" >&2; exit 1; }
model=$(curl -fsS --max-time 10 "http://127.0.0.1:$port/v1/models" | jq -er '.data[0].id | select(type == "string" and length > 0)')
agent_dir=$(omp config path)
mkdir -p "$agent_dir"
for other in "$agent_dir/models.json" "$agent_dir/models.yaml"; do
 [[ ! -e $other ]] || { echo "Existing model configuration $other needs a deliberate merge; not creating a competing models.yml." >&2; exit 1; }
done
/usr/bin/python3 - "$agent_dir/models.yml" "$model" "$port" <<'PY'
import os,sys,tempfile,yaml
p,model,port=sys.argv[1:]
if os.path.exists(p):
 with open(p) as f: data=yaml.safe_load(f) or {}
else: data={}
if not isinstance(data,dict): raise SystemExit('models.yml must be a mapping')
providers=data.setdefault('providers',{})
existing=providers.get('pc-setup-colibri')
if existing is not None:
 expected={'baseUrl':'http://127.0.0.1:8000/v1','api':'openai-completions','auth':'none','compat':{'supportsDeveloperRole':False},'models':existing.get('models') if isinstance(existing,dict) else None}
 if existing != expected:
  raise SystemExit('Existing pc-setup-colibri provider has custom settings; refusing to overwrite it')
providers['pc-setup-colibri']={'baseUrl':f'http://127.0.0.1:{port}/v1','api':'openai-completions','auth':'none','compat':{'supportsDeveloperRole':False},'models':[{'id':model,'name':'Local '+model,'reasoning':True,'input':['text'],'contextWindow':32768,'maxTokens':4096,'cost':{'input':0,'output':0,'cacheRead':0,'cacheWrite':0}}]}
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(p));os.fchmod(fd,0o600)
with os.fdopen(fd,'w') as f: yaml.safe_dump(data,f,sort_keys=False)
os.replace(tmp,p)
PY
selector="pc-setup-colibri/$model"
roles=$(omp config get modelRoles --json | jq -ec --arg m "$selector" '.value | if type == "object" then .default = $m else {default:$m} end')
omp config set modelRoles "$roles"
echo "OMP default model set to $selector on 127.0.0.1:$port."
echo 'Test a prompt and tool call in OMP after starting Colibri.'
