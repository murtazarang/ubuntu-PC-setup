#!/usr/bin/env python3
"""Opt-in real Open WebUI/mcpo/OpenZIM integration with fake model backends.

Needs independently installed executables and a small real ZIM fixture directory.
Never installs software, downloads models, touches user app data, or uses a GPU.
Ports 8000/8001/8002 must be free because production helpers target those ports.
Example fixture: openzim/zim-testing-suite data/withns/
wikipedia_en_climate_change_mini_2024-06.zim. This does not test the full corpus.
"""
import argparse
import base64
import contextlib
import http.server
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM0sAAAAASUVORK5CYII='
IMAGE_MODEL = 'qwen-image-2.1-colibri'
FINAL = 'Fixture verified Wikipedia article A/Climate_change.'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


class Backend(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send_json(self, value, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(value).encode())

    def do_GET(self):
        model = IMAGE_MODEL if self.server.server_port == 8001 else 'fixture-text'
        self.send_json({'data': [{'id': model, 'object': 'model'}]})

    def do_POST(self):
        try:
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            if self.server.server_port == 8001:
                require(self.path == '/v1/images/generations', 'Wrong image route')
                require(data['model'] == IMAGE_MODEL and data['n'] == 1 and
                        data['response_format'] == 'b64_json', 'Wrong image request')
                self.server.state['image_requests'] += 1
                self.send_json({'data': [{'b64_json': PNG}]})
                return
            require(self.path == '/v1/chat/completions', 'Wrong chat route')
            returned = [m for m in data['messages'] if m.get('role') == 'tool']
            if returned:
                require('A/Climate_change' in str(returned), 'Real article/source missing')
                self.server.state['tool_returned'] = True
                message = {'role': 'assistant', 'content': FINAL}
                finish = 'stop'
            else:
                names = [t['function']['name'] for t in data.get('tools', [])
                         if 'zim_query' in t['function']['name']]
                require(names, 'Wikipedia tool not advertised to model')
                message = {'role': 'assistant', 'content': None, 'tool_calls': [{
                    'id': 'call_fixture', 'type': 'function', 'function': {
                        'name': names[0], 'arguments': json.dumps({
                            'query': 'tell me about climate change', 'max_content_length': 500})}}]}
                finish = 'tool_calls'
            if data.get('stream'):
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.end_headers()
                delta = dict(message)
                if 'tool_calls' in delta:
                    delta['tool_calls'][0]['index'] = 0
                chunk = {'id': 'chatcmpl-fixture', 'object': 'chat.completion.chunk',
                         'created': 1, 'model': 'fixture-text',
                         'choices': [{'index': 0, 'delta': delta, 'finish_reason': None}]}
                end = {'choices': [{'index': 0, 'delta': {}, 'finish_reason': finish}]}
                self.wfile.write(('data: ' + json.dumps(chunk) + '\n\ndata: ' +
                                  json.dumps(end) + '\n\ndata: [DONE]\n\n').encode())
            else:
                self.send_json({'id': 'chatcmpl-fixture', 'object': 'chat.completion',
                                'created': 1, 'model': 'fixture-text',
                                'choices': [{'index': 0, 'message': message,
                                             'finish_reason': finish}]})
        except Exception as exc:
            self.server.state['errors'].append(str(exc))
            self.send_json({'error': str(exc)}, 500)


def stop_process(process):
    if process.poll() is not None:
        return
    if os.name == 'nt':
        # Only the exact test-owned PID and its descendants, never image-name matching.
        subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    else:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        if os.name != 'nt':
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=10)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--webui-exe', required=True, type=Path)
    parser.add_argument('--mcpo-exe', required=True, type=Path)
    parser.add_argument('--openzim-exe', required=True, type=Path)
    parser.add_argument('--archive-dir', required=True, type=Path)
    parser.add_argument('--helper-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--skills-root', type=Path, help='Optional complete three-repository inventory to import/read back')
    parser.add_argument('--retrieval-cache', type=Path, help='Optional pre-populated Hugging Face cache for real BGE/MiniLM OpenVINO CPU retrieval tests; never downloads weights')
    args = parser.parse_args()
    for executable in (args.webui_exe, args.mcpo_exe, args.openzim_exe):
        require(executable.is_file(), 'Missing executable: ' + str(executable))
    require(args.archive_dir.is_dir() and any(args.archive_dir.glob('*.zim')), 'Missing real ZIM fixture')
    sys.path.insert(0, str(args.helper_root.resolve()))
    import openwebui_skills as skills
    import openwebui_connections as connections

    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    state = {'tool_returned': False, 'image_requests': 0, 'errors': []}
    processes, servers, threads, logs = [], [], [], []
    with tempfile.TemporaryDirectory(prefix='openwebui-runtime-') as temp:
        work = Path(temp)
        def launch(argv, name, env=None):
            log = (work / (name + '.log')).open('w')
            logs.append(log)
            process = subprocess.Popen(argv, cwd=work, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=(os.name != 'nt'))
            processes.append(process)
            return process
        try:
            # Reserve all fixed ports before starting anything. No existing service is stopped.
            for port in (8000, 8001, 8002):
                check = socket.socket()
                try:
                    check.bind(('127.0.0.1', port))
                finally:
                    check.close()
            for port in (8000, 8001):
                server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Backend)
                server.state = state
                servers.append(server)
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                threads.append(thread)
            with socket.socket() as check:
                check.bind(('127.0.0.1', 0))
                webport = check.getsockname()[1]
            key = secrets.token_hex(32)
            keyfile = work / 'mcpo-key'
            keyfile.write_text(key)
            bridge = launch([str(args.mcpo_exe.resolve()), '--host', '127.0.0.1', '--port', '8002',
                             '--api-key', key, '--', str(args.openzim_exe.resolve()),
                             str(args.archive_dir.resolve())], 'mcpo')
            env = dict(os.environ, DATA_DIR=str(work / 'data'), WEBUI_SECRET_KEY=secrets.token_hex(32),
                       OFFLINE_MODE='true', HF_HUB_OFFLINE='1', RAG_EMBEDDING_MODEL_AUTO_UPDATE='false',
                       WHISPER_MODEL_AUTO_UPDATE='false', ENABLE_OLLAMA_API='false',
                       RAG_EMBEDDING_ENGINE='openai', OPENAI_API_BASE_URL='http://127.0.0.1:8000/v1',
                       OPENAI_API_KEY='local-test', WEBUI_AUTH='true')
            if args.retrieval_cache:
                require(args.retrieval_cache.is_dir(), 'Missing pre-populated retrieval cache')
                env.update(HF_HOME=str(args.retrieval_cache.resolve()),
                           SENTENCE_TRANSFORMERS_HOME=str(args.retrieval_cache.resolve() / 'hub'),
                           RAG_EMBEDDING_ENGINE='', RAG_EMBEDDING_MODEL='BAAI/bge-small-en-v1.5',
                           RAG_EMBEDDING_QUERY_PREFIX='Represent this sentence for searching relevant passages: ',
                           RAG_EMBEDDING_CONTENT_PREFIX='',
                           RAG_EMBEDDING_MODEL_TRUST_REMOTE_CODE='false',
                           RAG_RERANKING_MODEL_TRUST_REMOTE_CODE='false',
                           RAG_RERANKING_ENGINE='', RAG_RERANKING_MODEL='cross-encoder/ms-marco-MiniLM-L6-v2',
                           RAG_RERANKING_MODEL_AUTO_UPDATE='false', ENABLE_RAG_HYBRID_SEARCH='true',
                           RAG_TEXT_SPLITTER='token_transformers', RAG_TOKENIZER_MODEL='BAAI/bge-small-en-v1.5',
                           CHUNK_SIZE='400', CHUNK_OVERLAP='50',
                           USE_CUDA_DOCKER='false', USE_SLIM_DOCKER='false',
                           SENTENCE_TRANSFORMERS_BACKEND='openvino',
                           SENTENCE_TRANSFORMERS_CROSS_ENCODER_BACKEND='openvino',
                           SENTENCE_TRANSFORMERS_MODEL_KWARGS='{"device":"CPU"}',
                           SENTENCE_TRANSFORMERS_CROSS_ENCODER_MODEL_KWARGS='{"device":"CPU"}')
            web = launch([str(args.webui_exe.resolve()), 'serve', '--host', '127.0.0.1',
                          '--port', str(webport)], 'webui', env)
            for port, route, proc in ((8002, '/openapi.json', bridge), (webport, '/health', web)):
                for _ in range(240):
                    require(proc.poll() is None, 'Test service exited; see log')
                    try:
                        request = urllib.request.Request(f'http://127.0.0.1:{port}{route}',
                                                         headers={'Authorization': 'Bearer ' + key})
                        with opener.open(request, timeout=2) as response:
                            require(response.status == 200, 'Unexpected readiness status')
                        break
                    except (OSError, urllib.error.URLError):
                        time.sleep(1)
                else:
                    raise RuntimeError('Test service did not become ready')
            api = skills.API(f'http://127.0.0.1:{webport}')
            def post(path, data):
                return api.request(path, json.dumps(data).encode())
            account = post('/api/v1/auths/signup', {'name': 'Runtime fixture',
                            'email': secrets.token_hex(8) + '@example.test', 'password': secrets.token_hex(24)})
            api.token = account['token']
            require(account['role'] == 'admin', 'Fresh account is not admin')
            if args.retrieval_cache:
                emb = api.request('/api/v1/retrieval/embedding')
                rag = api.request('/api/v1/retrieval/config')
                require(emb['RAG_EMBEDDING_ENGINE'] == '' and emb['RAG_EMBEDDING_MODEL'] == 'BAAI/bge-small-en-v1.5', 'Wrong embedding model')
                expected = {'RAG_RERANKING_ENGINE': '', 'RAG_RERANKING_MODEL': 'cross-encoder/ms-marco-MiniLM-L6-v2',
                            'ENABLE_RAG_HYBRID_SEARCH': True, 'TEXT_SPLITTER': 'token_transformers',
                            'RAG_TOKENIZER_MODEL': 'BAAI/bge-small-en-v1.5', 'CHUNK_SIZE': 400, 'CHUNK_OVERLAP': 50}
                require(all(rag.get(k) == v for k, v in expected.items()), 'Native retrieval defaults differ')
                doc = post('/api/v1/retrieval/process/text', {'name': 'Climate fixture', 'content':
                    'Carbon dioxide from burning fossil fuels traps heat and contributes to global warming. '
                    'Reducing fossil fuel emissions helps limit climate change. ' * 25})
                require(doc.get('status') is True, 'Native text ingestion failed')
                result = post('/api/v1/retrieval/query/doc', {'collection_name': doc['collection_name'],
                              'query': 'What causes global warming?', 'hybrid': True, 'k': 2, 'k_reranker': 2})
                require('fossil fuel' in json.dumps(result).lower(), 'Native hybrid retrieval returned no fixture text')
                print('PASS: real BGE/MiniLM OpenVINO CPU native text ingestion and hybrid query; token chunks 400/50.', flush=True)
            fixture = {'id': 'runtime-fixture', 'name': 'Runtime fixture', 'is_active': True,
                       'meta': {'tags': ['runtime-test'], 'i18n': None}, 'files': [
                           {'path': 'SKILL.md', 'content': '---\nname: runtime-fixture\ndescription: Fixture\n---\nRead references/detail.md.'},
                           {'path': 'references/detail.md', 'content': 'Exact detail: test fact.'},
                           {'path': 'assets/raw.bin', 'encoding': 'base64', 'content': 'AAECAw=='}]}
            skills.import_all(api, [fixture])
            skills.import_all(api, [fixture])
            if args.skills_root:
                packages = skills.inventory(args.skills_root)
                skills.import_all(api, packages)
                skills.import_all(api, packages)
                print('Full inventory imported and rerun:', len(packages), flush=True)
            connections.configure(api, keyfile, IMAGE_MODEL)
            connections.configure(api, keyfile, IMAGE_MODEL)
            require('server:pc-setup-wikipedia' in [t['id'] for t in api.request('/api/v1/tools/')],
                    'Wikipedia server missing or disabled')
            require(any(m['id'] == 'fixture-text' for m in api.request('/api/models')['data']), 'Text backend missing')
            chat = post('/api/v1/chats/new', {'chat': {'title': 'Runtime fixture',
                        'history': {'messages': {}, 'currentId': None}, 'models': ['fixture-text']}})
            post('/api/chat/completions', {'model': 'fixture-text', 'messages': [
                {'role': 'user', 'content': 'What is climate change?'}], 'stream': True,
                'chat_id': chat['id'], 'id': 'runtime-assistant', 'tool_ids': ['server:pc-setup-wikipedia'],
                'params': {'function_calling': 'native', 'tool_approval_mode': 'full'}})
            for _ in range(90):
                saved = api.request('/api/v1/chats/' + chat['id'])
                message = saved['chat']['history']['messages'].get('runtime-assistant', {})
                if message.get('done'):
                    break
                time.sleep(1)
            require(state['tool_returned'] and message.get('content') == FINAL,
                    'Real Wikipedia result did not complete model tool loop')
            require(any(o.get('type') == 'function_call_output' and o.get('status') == 'completed'
                        for o in message.get('output', [])), 'No completed tool output persisted')
            images = post('/api/v1/images/generations', {'model': 'pc-setup-colibri-image:' + IMAGE_MODEL,
                                                      'prompt': 'Fixture'})
            require(state['image_requests'] == 1 and images[0]['content_type'] == 'image/png', 'Image flow failed')
            request = urllib.request.Request(api.url + images[0]['url'],
                                             headers={'Authorization': 'Bearer ' + api.token})
            with opener.open(request, timeout=10) as response:
                require(response.read() == base64.b64decode(PNG), 'Stored image differs from fixture')
            require(not state['errors'], repr(state['errors']))
            print('PASS: real WebUI skill import/readback/rerun; real Wikipedia tool loop; fake-model image flow.', flush=True)
            print('Not tested: actual GPU inference, full Wikipedia corpus, optional skill execution tools.', flush=True)
        except Exception:
            for log in logs:
                log.flush()
                print('\nTEST LOG:', Path(log.name).name, file=sys.stderr)
                print(Path(log.name).read_text(errors='replace')[-6000:], file=sys.stderr)
            raise
        finally:
            for process in reversed(processes):
                stop_process(process)
            for server in servers:
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join(timeout=5)
            for log in logs:
                log.close()


if __name__ == '__main__':
    main()
