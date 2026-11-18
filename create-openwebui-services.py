#!/usr/bin/env python3
"""Generate owned user services. Never replace an unrelated service or data file."""
import argparse
import json
import os
from pathlib import Path
import importlib.util
import secrets

MARKER = '# ubuntu-pc-setup-openwebui'

def unit_quote(value):
    value = str(value)
    if '\n' in value or '\r' in value: raise ValueError('Newlines not allowed in service arguments')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%').replace('$', '$$') + '"'

def no_links(path):
    for candidate in (Path(path), *Path(path).parents):
        if candidate.is_symlink(): raise SystemExit('Refusing linked setup path: '+str(candidate))

def owned(path, content):
    no_links(path)
    if path.exists() and path.read_text() != content:
        raise SystemExit('Refusing unrelated service: ' + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    path.chmod(0o600)

def configure(base, archives, home=None, backend_env=None):
    base=Path(base).absolute(); home=Path(home or Path.home()); archives=Path(archives).absolute()
    no_links(base)
    base.mkdir(parents=True, exist_ok=True)
    units=Path(os.environ.get('XDG_CONFIG_HOME', str(home/'.config')))/'systemd/user'
    secret=base/'webui-secret'
    for file in ('webui-secret','webui.env','mcpo-key','launch-webui.sh'): no_links(base/file)
    if not secret.exists():
        fd=os.open(secret, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
        with os.fdopen(fd,'w') as f: f.write(secrets.token_hex(32))
    env=base/'webui.env'
    if not env.exists():
        # EnvironmentFile uses its own quoting, not systemd Exec percent escaping.
        values={'DATA_DIR':str(base/'data'),'WEBUI_SECRET_KEY':secret.read_text().strip(),
                'OPENAI_API_BASE_URL':'http://127.0.0.1:8000/v1','OPENAI_API_KEY':'local',
                'ENABLE_OLLAMA_API':'false','WEBUI_AUTH':'true','USE_CUDA_DOCKER':'true','USE_SLIM_DOCKER':'false',
                'RAG_EMBEDDING_MODEL':'BAAI/bge-small-en-v1.5',
                'RAG_RERANKING_MODEL':'cross-encoder/ms-marco-MiniLM-L6-v2',
                'ENABLE_RAG_HYBRID_SEARCH':'true','CHUNK_SIZE':'400','CHUNK_OVERLAP':'50',
                'RAG_TEXT_SPLITTER':'token_transformers','RAG_TOKENIZER_MODEL':'BAAI/bge-small-en-v1.5',
                'RAG_EMBEDDING_ENGINE':'','RAG_RERANKING_ENGINE':'',
                'RAG_EMBEDDING_MODEL_TRUST_REMOTE_CODE':'false','RAG_RERANKING_MODEL_TRUST_REMOTE_CODE':'false',
                'RAG_EMBEDDING_QUERY_PREFIX':'Represent this sentence for searching relevant passages: ',
                'RAG_EMBEDDING_CONTENT_PREFIX':''}
        env.write_text('\n'.join(k+'='+json.dumps(v) for k,v in values.items())+'\n'); env.chmod(0o600)
    if secret.stat().st_mode & 0o077: raise SystemExit('Existing WebUI secret is not private; inspect its permissions.')
    # API key retained in a private file; no key in generated desktop files.
    key=base/'mcpo-key'
    if not key.exists():
        fd=os.open(key, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
        with os.fdopen(fd,'w') as f:f.write(secrets.token_hex(32))
    if key.stat().st_mode & 0o077: raise SystemExit('Existing MCP key is not private; inspect its permissions.')
    backend_path=base/'backend.env'
    if backend_env is None:
        backend={'USE_CUDA_DOCKER':'true','USE_SLIM_DOCKER':'false',
                 'SENTENCE_TRANSFORMERS_BACKEND':'torch','SENTENCE_TRANSFORMERS_CROSS_ENCODER_BACKEND':'torch',
                 'SENTENCE_TRANSFORMERS_MODEL_KWARGS':'{}','SENTENCE_TRANSFORMERS_CROSS_ENCODER_MODEL_KWARGS':'{}'}
        check=[base/'tools/open-webui/bin/python','-c',"import torch; assert torch.cuda.is_available(), 'Open WebUI CUDA unavailable; refusing silent CPU fallback'; from open_webui.env import DEVICE_TYPE; assert DEVICE_TYPE == 'cuda', 'Open WebUI did not select CUDA'"]
    else:
        backend=json.loads(Path(backend_env).read_text())
        import re
        if not isinstance(backend,dict) or any(not re.fullmatch(r'[A-Z][A-Z0-9_]*',k) or not isinstance(v,str) or '\n' in v or '\r' in v for k,v in backend.items()):
            raise SystemExit('Invalid backend environment mapping')
        if backend.get('SENTENCE_TRANSFORMERS_BACKEND')!='openvino' or backend.get('SENTENCE_TRANSFORMERS_CROSS_ENCODER_BACKEND')!='openvino':
            raise SystemExit('Expected explicit OpenVINO embeddings and reranking')
        backend.update(USE_CUDA_DOCKER='false',USE_SLIM_DOCKER='false')
        check=[base/'tools/open-webui/bin/python',base/'openwebui_gpu.py','verify-openvino']
    owned(backend_path,MARKER+'\n'+'\n'.join(k+'='+json.dumps(v) for k,v in backend.items())+'\n')
    forced=['/usr/bin/env',*[k+'='+v for k,v in backend.items()]]
    # Backend variables are process-local and take precedence over inherited CPU/slim defaults.
    for name, args, extras in [
      ('pc-setup-openwebui',forced+[base/'bin/open-webui','serve','--host','127.0.0.1','--port','8080'],
       'EnvironmentFile='+str(env).replace('%','%%')+'\nExecStartPre='+' '.join(map(unit_quote,forced+check))+'\n'),
      ('pc-setup-wikipedia',[base/'bin/mcpo','--host','127.0.0.1','--port','8002','--api-key',key.read_text().strip(),'--',base/'bin/openzim-mcp',archives],'')]:
        owned(units/(name+'.service'), MARKER+'\n[Unit]\nDescription='+name+'\n[Service]\nType=exec\n'+extras+'ExecStart='+' '.join(map(unit_quote,args))+'\nRestart=on-failure\nRestartSec=5\n')
    launcher=base/'launch-webui.sh'
    content = '#!/usr/bin/env bash\nset -e\nsystemctl --user start pc-setup-wikipedia.service pc-setup-openwebui.service\nfor i in $(seq 1 90); do\n if curl -fsS --max-time 2 http://127.0.0.1:8080/health >/dev/null; then exec xdg-open http://127.0.0.1:8080; fi\n sleep 2\ndone\necho "Open WebUI did not become ready. Check journalctl --user -u pc-setup-openwebui." >&2\nexit 1\n'
    if launcher.exists() and not launcher.read_text().startswith('#!/usr/bin/env bash\nset -e\nsystemctl --user start pc-setup-wikipedia.service'):
        raise SystemExit('Refusing custom launcher: '+str(launcher))
    launcher.write_text(content); launcher.chmod(0o700)
    source=Path(__file__).with_name('create-colibri-shortcuts.py')
    spec=importlib.util.spec_from_file_location('desktop_shortcuts',source)
    desktop_module=importlib.util.module_from_spec(spec); spec.loader.exec_module(desktop_module)
    text='\n'.join(['[Desktop Entry]','Type=Application','Name=Open WebUI',
         'Exec='+desktop_module.quote(launcher),'Terminal=false','Icon=applications-internet',
         'X-PC-Setup-Colibri=true',''])
    applications=Path(os.environ.get('XDG_DATA_HOME',str(home/'.local/share')))/'applications'
    desktop_module.write_entry(applications/'pc-setup-openwebui.desktop',text)
    import subprocess
    try:
        desktop=Path(subprocess.check_output(['xdg-user-dir','DESKTOP'],text=True).strip())
        if not desktop.is_absolute() or desktop==home: raise ValueError()
    except (OSError,subprocess.CalledProcessError,ValueError): desktop=home/'Desktop'
    desktop_module.write_entry(desktop/'Open WebUI.desktop',text)
    return units

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--archives',required=True);p.add_argument('--backend-env')
    a=p.parse_args();configure(a.base,a.archives,backend_env=a.backend_env)
