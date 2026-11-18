"""Small Windows shortcut lifecycle, only for this setup's recorded processes.

No service, no arbitrary port-owner termination, no model/user data deletion.
"""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import webbrowser

import psutil


def owned_process(record):
    try:
        process = psutil.Process(record['pid'])
        if abs(process.create_time() - record['created']) > 0.01:
            return None
        if process.cmdline() != record['command']:
            return None
        return process
    except (KeyError, psutil.NoSuchProcess, psutil.AccessDenied):
        return None


def stop_record(record):
    process = owned_process(record)
    if process is None:
        return
    # Capture descendants before parent termination; never kill by name or port.
    targets = process.children(recursive=True) + [process]
    for child in reversed(targets):
        try:
            child.terminate()
        except psutil.NoSuchProcess:
            pass
    _, alive = psutil.wait_procs(targets, timeout=10)
    if alive:
        raise RuntimeError('A recorded process did not stop. Close it before switching models.')


def check_port(port):
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', port))


def start(command, port, root, name, env):
    check_port(port)
    with (root / f'{name}.log').open('ab') as log:
        process = subprocess.Popen(command, cwd=root, env=env, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    tracked = psutil.Process(process.pid)
    record = {'pid': process.pid, 'created': tracked.create_time(), 'command': tracked.cmdline()}
    time.sleep(1)
    if process.poll() is not None:
        raise RuntimeError(f'{name} exited. Read {root / (name + ".log")}')
    return record


def webui_environment(config, inherited):
    env = inherited.copy()
    preferences = config.get('webui_environment', {})
    env.update(preferences)
    if str(preferences.get('WEBUI_AUTH', 'true')).lower() != 'true':
        raise RuntimeError('Existing WebUI settings disable authentication; settings preserved.')
    env['WEBUI_AUTH'] = 'true'
    if config['hardware'] in ('NvidiaSingle', 'NvidiaDual'):
        if str(preferences.get('USE_SLIM_DOCKER', 'false')).lower() != 'false':
            raise RuntimeError('Existing WebUI settings enable slim mode, which disables CUDA; settings preserved.')
        if str(preferences.get('USE_CUDA_DOCKER', 'true')).lower() != 'true':
            raise RuntimeError('Existing WebUI settings disable CUDA; settings preserved.')
        env['USE_CUDA_DOCKER'] = 'true'
        env['USE_SLIM_DOCKER'] = 'false'
        for key in ('SENTENCE_TRANSFORMERS_BACKEND', 'SENTENCE_TRANSFORMERS_CROSS_ENCODER_BACKEND'):
            if preferences.get(key, 'torch') != 'torch':
                raise RuntimeError('Existing NVIDIA retrieval backend is not torch; settings preserved.')
            env[key] = 'torch'
        for key in ('SENTENCE_TRANSFORMERS_MODEL_KWARGS', 'SENTENCE_TRANSFORMERS_CROSS_ENCODER_MODEL_KWARGS'):
            if json.loads(preferences.get(key, '{}')) != {}:
                raise RuntimeError('Existing NVIDIA retrieval model kwargs differ from managed CUDA settings; preserved.')
            env[key] = '{}'

    return env


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['text', 'image', 'stop', 'ui'])
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    config = json.loads((root / 'desktop.json').read_text(encoding='utf-8-sig'))
    # OS-backed exclusive lock is released even after process termination.
    import msvcrt
    with (root / 'desktop.lock').open('a+b') as lock:
        lock.seek(0)
        if lock.read(1) == b'':
            lock.write(b'0'); lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise RuntimeError('Another shortcut action is running. Please wait and try again.')
        state_path = root / 'processes.json'
        state = json.loads(state_path.read_text()) if state_path.exists() else {}
        def save():
            temporary = state_path.with_suffix('.tmp')
            temporary.write_text(json.dumps(state), encoding='utf-8')
            temporary.replace(state_path)
        env = os.environ.copy()
        if args.action in ('text', 'image', 'stop'):
            previous = state.get('model')
            if previous and args.action == previous.get('kind') and owned_process(previous):
                return
            if previous:
                stop_record(previous)
                state.pop('model', None); save()
            if args.action == 'stop':
                return
            env.update(COLI_VULKAN='1', COLI_CUDA='0', COLI_NO_OMP_TUNE='1')
            for key in ('COLI_VK_DEV2', 'COLI_DENSE_BITS', 'COLI_DENSE_INT4'):
                env.pop(key, None)
            if args.action == 'text' and config['hardware'] == 'NvidiaDual':
                env['COLI_VK_DEV2'] = 'auto'
            port = 8000 if args.action == 'text' else 8001
            command = [config['coli_python'], config['coli'], 'serve', '--host', '127.0.0.1',
                       '--port', str(port), '--model', config[args.action + '_model']]
            state['model'] = start(command, port, root, args.action, env)
            state['model']['kind'] = args.action
            save()
            return
        # Durable data and secret live in this installation, not a temporary setup folder.
        env = webui_environment(config, env)
        if config['hardware'] in ('NvidiaSingle', 'NvidiaDual'):
            import torch
            if not torch.cuda.is_available():
                raise RuntimeError('NVIDIA CUDA is unavailable. No CPU fallback: check the driver and WebUI CUDA environment.')
            subprocess.run([config['webui_command'][0].replace('open-webui.exe', 'python.exe'), '-c',
                            "from open_webui.env import DEVICE_TYPE; assert DEVICE_TYPE == 'cuda', 'Open WebUI selected a non-CUDA device'"],
                           env=env, cwd=root, check=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if config['hardware'] == 'Intel':
            import sys
            subprocess.run([sys.executable, str(root / 'openwebui_gpu.py'), 'verify-openvino'],
                           env=env, cwd=root, check=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        env['DATA_DIR'] = str(root / 'data')
        for name, port, command in [('wikipedia', 8002, config['mcpo_command']),
                                    ('webui', 8080, config['webui_command'])]:
            if not owned_process(state.get(name, {})):
                state[name] = start(command, port, root, name, env)
                save()
        # Open a startup page only after actual HTTP readiness, not merely a live PID.
        import urllib.request
        for _ in range(180):
            try:
                with urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2) as response:
                    if response.status == 200:
                        webbrowser.open('http://127.0.0.1:8080'); return
            except (OSError, TimeoutError):
                time.sleep(2)
        raise RuntimeError(f'Open WebUI is still starting or failed. Read {root / "webui.log"}.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        import ctypes
        ctypes.windll.user32.MessageBoxW(0, str(error), 'Local AI setup', 0x10)
        raise
