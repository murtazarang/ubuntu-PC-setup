#!/usr/bin/env bash
# Connect OMP to the local Strata or XeStrata instance after it has started.
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
port=${1:-8095}
[[ $port =~ ^(8080|8095)$ ]] || { echo "Expected local port 8080 or 8095" >&2; exit 1; }
model=$(curl -fsS --max-time 10 "http://127.0.0.1:$port/v1/models" | jq -er '.data[0].id | select(type == "string" and length > 0)')
agent_dir=$(omp config path)
mkdir -p "$agent_dir"
/usr/bin/python3 - "$agent_dir/models.yml" "$model" "$port" <<'PY'
import os,sys,tempfile,yaml
p,model,port=sys.argv[1:]
if os.path.exists(p):
 with open(p) as f: data=yaml.safe_load(f) or {}
else: data={}
if not isinstance(data,dict): raise SystemExit('models.yml must be a mapping')
providers=data.setdefault('providers',{})
providers['local-inference']={'baseUrl':f'http://127.0.0.1:{port}/v1','api':'openai-completions','auth':'none','compat':{'supportsDeveloperRole':False},'models':[{'id':model,'name':'Local '+model,'reasoning':True,'input':['text'],'contextWindow':32768,'maxTokens':4096,'cost':{'input':0,'output':0,'cacheRead':0,'cacheWrite':0}}]}
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(p));os.fchmod(fd,0o600)
with os.fdopen(fd,'w') as f: yaml.safe_dump(data,f,sort_keys=False)
os.replace(tmp,p)
PY
selector="local-inference/$model"
roles=$(omp config get modelRoles --json | jq -ec --arg m "$selector" '.value | if type == "object" then .default = $m else {default:$m} end')
omp config set modelRoles "$roles"
echo "OMP default model set to $selector on 127.0.0.1:$port."
echo 'Test a prompt and tool call in OMP and Paseo after starting XeStrata.'
