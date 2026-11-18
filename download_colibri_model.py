#!/usr/bin/env python3
"""Download pinned Colibri model artifacts with resume and SHA-256 verification."""
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import time
import urllib.error
import urllib.request

CHUNK = 4 * 1024 * 1024
RESERVE = 1024 ** 3


def linked(path):
    return path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction())


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(CHUNK), b''):
            h.update(data)
    return h.hexdigest()


def validate_manifest(entry):
    if not re.fullmatch(r'[0-9a-f]{40}', entry['revision']):
        raise ValueError('Model revision must be a pinned commit SHA')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', entry['repository']):
        raise ValueError('Invalid model repository')
    seen = set()
    for item in entry['files']:
        path = PurePosixPath(item['path'])
        if path.is_absolute() or '..' in path.parts or '\\' in item['path'] or str(path) != item['path'] or item['path'] in seen:
            raise ValueError('Invalid or duplicated artifact path')
        seen.add(item['path'])
        if not re.fullmatch(r'[0-9a-f]{64}', item['sha256']) or not isinstance(item['size'], int) or item['size'] <= 0:
            raise ValueError('Every artifact requires exact size and SHA-256')
    if not seen:
        raise ValueError('Empty artifact manifest')


def check_path(path, root):
    current = path
    while current != root.parent:
        if linked(current):
            raise ValueError(f'Refusing symlink: {current}')
        current = current.parent


def download_file(url, target, size, sha, opener=urllib.request.urlopen, sleep=time.sleep):
    partial = target.with_name(target.name + '.part')
    for attempt in range(6):
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > size:
            raise ValueError(f'Partial file exceeds expected size; preserved: {partial}')
        if offset == size:
            break
        request = urllib.request.Request(url, headers={'User-Agent': 'ubuntu-PC-setup/Colibri', 'Accept-Encoding': 'identity', **({'Range': f'bytes={offset}-'} if offset else {})})
        try:
            with opener(request, timeout=60) as response:
                status = response.status
                if offset:
                    match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', response.headers.get('Content-Range', ''))
                    if status != 206 or not match or tuple(map(int, match.groups())) != (offset, size - 1, size):
                        raise ValueError('Server did not honor resume range; partial preserved')
                elif status != 200:
                    raise ValueError(f'Unexpected download HTTP status {status}')
                received = offset
                last_report = time.monotonic()
                print(f'{target.name}: downloading/resuming at {offset:,} of {size:,} bytes', flush=True)
                with partial.open('ab' if offset else 'wb') as stream:
                    while True:
                        data = response.read(CHUNK)
                        if not data:
                            break
                        if received + len(data) > size:
                            raise ValueError('Response exceeds expected artifact size')
                        stream.write(data)
                        received += len(data)
                        if time.monotonic() - last_report >= 5:
                            print(f'{target.name}: {received/size:.1%} ({received:,}/{size:,} bytes)', flush=True)
                            last_report = time.monotonic()
                if received != size:
                    raise OSError(f'Download interrupted at {received:,}/{size:,} bytes')
            break
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as error:
            if attempt == 5:
                raise RuntimeError(f'Download interrupted; rerun to resume {partial}: {error}') from error
            print(f'Transfer interrupted; retrying in {min(2 ** attempt, 20)}s: {error}', flush=True)
            sleep(min(2 ** attempt, 20))
    print(f'{target.name}: verifying SHA-256 (may take several minutes)', flush=True)
    if digest(partial) != sha:
        raise ValueError(f'SHA-256 mismatch; partial preserved at {partial}. Do not use it; remove only this .part file before retrying.')
    os.replace(partial, target)


def install(entry, destination, downloader=download_file, disk_usage=shutil.disk_usage, reserve_bytes=0):
    validate_manifest(entry)
    root = Path(destination).absolute()
    for ancestor in (root, *root.parents):
        if linked(ancestor):
            raise ValueError(f'Refusing symlink destination: {ancestor}')
    root.mkdir(parents=True, exist_ok=True)
    pending = []
    needed = 0
    for item in entry['files']:
        target = root / item['path']
        check_path(target, root)
        partial = target.with_name(target.name + '.part')
        check_path(partial, root)
        if target.exists():
            print(f'{target.name}: checking existing file', flush=True)
            if target.stat().st_size != item['size'] or digest(target) != item['sha256']:
                raise ValueError(f'Existing artifact differs from pinned model; preserved: {target}')
            continue
        already = partial.stat().st_size if partial.exists() else 0
        if already > item['size']:
            raise ValueError(f'Oversized partial retained: {partial}')
        needed += item['size'] - already
        pending.append((item, target))
    if reserve_bytes < 0:
        raise ValueError('Reserve must not be negative')
    reserve = reserve_bytes + RESERVE
    if disk_usage(root).free < needed + reserve:
        raise OSError(f'Insufficient space: need {needed:,} remaining download bytes plus {reserve:,} conversion/safety reserve; rerun after freeing space.')
    for item, target in pending:
        target.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://huggingface.co/{entry['repository']}/resolve/{entry['revision']}/{item['path']}"
        downloader(url, target, item['size'], item['sha256'])
    print(f'All model artifacts verified: {root}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', required=True)
    parser.add_argument('--destination', required=True)
    parser.add_argument('--reserve-bytes', type=int, default=0, help='Additional space needed for native conversion')
    parser.add_argument('--manifest', default=str(Path(__file__).with_name('colibri-models.json')))
    args = parser.parse_args()
    models = json.loads(Path(args.manifest).read_text(encoding='utf-8'))
    install(models[args.model], args.destination, reserve_bytes=args.reserve_bytes)


if __name__ == '__main__':
    main()
