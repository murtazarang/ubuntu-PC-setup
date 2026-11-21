"""Install and run the stock llama.cpp engine without configuring a UI or agent."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
from http.client import HTTPConnection
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
from urllib.parse import quote
import zipfile

PIN = "b12359"  # release v1.0.0 points at these builds
HOST, PORT = "127.0.0.1", 8081
BASE_URL = f"http://{HOST}:{PORT}/v1"
GIB = 1024**3
WINDOWS_RESERVE_GIB = 12
DUAL_CPU_MOE_LAYERS = 30
HOST_RUNTIME_ALLOWANCE_GIB = 3
RELEASE = f"https://github.com/ggml-org/llama.cpp/releases/download/{PIN}"
# github.com/ggml-org/llama.cpp/attestations/67120335
ASSETS = {
    ("Windows", "cuda"): (
        ("llama-b12359-bin-win-cuda-12.4-x64.zip", "e9c0abf442e8339c06728366c1ad2c711332f9939c0c00603fb75d85fd44c914"),
        ("cudart-llama-bin-win-cuda-12.4-x64.zip", "8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6"),
    ),
    ("Linux", "cuda"): (
        ("llama-b12359-bin-ubuntu-cuda-12.8-x64.tar.gz", "50c937bec5bbd9f74c99138034f7403283ee21f1943f2429d7b1e4c079eafc11"),
        ("cudart-llama-b12359-bin-ubuntu-cuda-12.8-x64.tar.gz", "75a12d227f44a391608992329241765343bd143ee9445b90dc62e154ee726e5d"),
    ),
    ("Windows", "vulkan"): (
        ("llama-b12359-bin-win-vulkan-x64.zip", "e8d18c6e4210cca87e7307c2ea78363ac8d158e4e1397358ec96ab70b53a0d5e"),
    ),
    ("Linux", "vulkan"): (
        ("llama-b12359-bin-ubuntu-vulkan-x64.tar.gz", "19b60f00395a3f4954e46a5037695bc1d843404fc9d3124f82a612ecd8fbe9f0"),
    ),
}


@dataclass(frozen=True)
class Profile:
    backend: str
    gpu_label: str
    gpu_count: int
    context: int
    alias: str
    repo: str
    revision: str
    files: tuple[tuple[str, str, int], ...]


BOLT = (
    "nemotron-bolt",
    "nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-GGUF",
    "724e3fe",
    (("NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB.gguf",
      "91d63363e782c8a3d5f4be42816eba8e0d42dd2530bd07a7d0d2dc440599af75", 22018326528),),
)
QFN = (
    "qwen-flash-next",
    "ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF",
    "8f752f8ae475984833f74edf84d9e43c5d1eaf98",
    (
        ("Q2_0/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00001-of-00002.gguf",
         "69820c02ec7d0b45ef2ebb19d6620299db749fe2aded7f39f93c6b88b199b720", 37623740192),
        ("Q2_0/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00002-of-00002.gguf",
         "316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113", 28800138432),
    ),
)
PROFILES = {
    "NvidiaSingle": Profile("cuda", "RTX 3080", 1, 131072, *BOLT),
    "Intel": Profile("vulkan", "Arc.*B580", 1, 131072, *BOLT),
    "NvidiaDual": Profile("cuda", "RTX 3060", 2, 262144, *QFN),
}


def default_root() -> Path:
    if os.name == "nt":
        return Path(os.environ["LOCALAPPDATA"]) / "PCSetup/local-ai"
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "pc-setup/local-ai"


def model_dir(root: Path, profile: Profile) -> Path:
    return root / "models" / profile.repo.replace("/", "--")


def runtime_dir(root: Path, profile: Profile) -> Path:
    return root / "engine" / f"{PIN}-{platform.system().lower()}-{profile.backend}"


def json_read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def json_write(path: Path, data: dict) -> None:
    fd, name = tempfile.mkstemp(prefix=".new-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


@contextmanager
def state_lock(root: Path):
    state = root / "engine"
    state.mkdir(parents=True, exist_ok=True)
    with (state / "lock").open("a+b") as handle:
        try:
            if os.name == "nt":
                import msvcrt
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise RuntimeError("The engine is busy with another install, start, or stop.") from error
        yield state


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for data in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def checked_download(url: str, path: Path, digest: str, size: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise RuntimeError(f"Won't use a symbolic link as a download target: {path}")
    if path.exists():
        if (size is None or path.stat().st_size == size) and sha256(path) == digest:
            return
        raise RuntimeError(f"Existing file does not match the official checksum; left intact: {path}")
    partial = path.with_name(path.name + ".part")
    if partial.is_symlink() or (partial.exists() and not partial.is_file()):
        raise RuntimeError(f"Invalid download partial path: {partial}")
    have = partial.stat().st_size if partial.exists() else 0
    if size is not None and (have > size or shutil.disk_usage(path.parent).free < size - have):
        raise RuntimeError(f"Not enough free disk space, or oversized partial: {partial}")
    if size is None or not partial.exists() or have != size:
        curl = shutil.which("curl.exe" if os.name == "nt" else "curl")
        if not curl:
            raise RuntimeError("curl is required to fetch these pinned downloads.")
        flags = ["-q", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https",
                 "--retry", "3", "--connect-timeout", "30", "--continue-at", "-", "--output", str(partial), url]
        print(f"Downloading {path.name} (partial downloads are kept for resume).", flush=True)
        subprocess.run([curl, *flags], check=True)
    print(f"Verifying SHA-256 for {path.name}.", flush=True)
    if (size is not None and partial.stat().st_size != size) or sha256(partial) != digest:
        raise RuntimeError(f"SHA-256/size mismatch; untrusted file kept as {partial}. Move it away to retry.")
    partial.rename(path)


def unpack(path: Path, dest: Path) -> None:
    if path.suffix == ".zip":
        with zipfile.ZipFile(path) as archive:
            for entry in archive.infolist():
                file = dest / entry.filename
                if not file.resolve().is_relative_to(dest.resolve()) or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise RuntimeError(f"Unsafe entry in archive: {entry.filename}")
            archive.extractall(dest)
    else:
        with tarfile.open(path, "r:gz") as archive:
            archive.extractall(dest, filter="data")


def install_runtime(root: Path, profile: Profile) -> Path:
    target = runtime_dir(root, profile)
    if target.exists():
        return binary(root, profile)
    assets = ASSETS[(platform.system(), profile.backend)]
    executable = "llama-server.exe" if os.name == "nt" else "llama-server"
    with tempfile.TemporaryDirectory(prefix="runtime-", dir=target.parent) as temp:
        dest = Path(temp) / "unpacked"
        dest.mkdir()
        for filename, digest in assets:
            archive = target.parent / "downloads" / filename
            checked_download(f"{RELEASE}/{filename}", archive, digest)
            unpack(archive, dest)
        candidates = list(dest.rglob(executable))
        if len(candidates) != 1:
            raise RuntimeError(f"Expected exactly one {executable} in the release.")
        server = candidates[0]
        json_write(dest / "release.json", {"pin": PIN, "binary": server.relative_to(dest).as_posix()})
        dest.rename(target)
    return binary(root, profile)


def binary(root: Path, profile: Profile) -> Path:
    dest = runtime_dir(root, profile)
    if not (dest / "release.json").is_file():
        raise RuntimeError("Pinned llama.cpp is not installed; run the install stage.")
    release = json_read(dest / "release.json")
    server = (dest / release["binary"]).resolve()
    if release.get("pin") != PIN or not server.is_relative_to(dest.resolve()) or not server.is_file():
        raise RuntimeError(f"Invalid installed llama.cpp runtime at {dest}")
    return server


def engine_env(root: Path, profile: Profile, server: Path) -> dict:
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("LLAMA_", "GGML_", "MTMD_"))}
    env.pop("CUDA_VISIBLE_DEVICES", None)
    env.pop("CUDA_DEVICE_ORDER", None)
    env.pop("VK_DRIVER_FILES", None)
    env.pop("VK_ICD_FILENAMES", None)
    windows = os.name == "nt"
    glob = "*.dll" if windows else "*.so*"
    dirs = [server.parent, *sorted({p.parent for p in runtime_dir(root, profile).rglob(glob)}
                                   - {server.parent})]
    key = "PATH" if windows else "LD_LIBRARY_PATH"
    env[key] = os.pathsep.join([*(str(item) for item in dirs), *([env[key]] if windows and env.get(key) else [])])
    return env


def get_devices(root: Path, profile: Profile, server: Path) -> list[str]:
    listing = subprocess.run([str(server), "--list-devices"], cwd=server.parent,
                             env=engine_env(root, profile, server), check=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
    prefix = "CUDA" if profile.backend == "cuda" else "Vulkan"
    ids = re.findall(rf"^\s*({prefix}\d+):[^\r\n]*{profile.gpu_label}[^\r\n]*$",
                     listing.stdout, re.I | re.M)
    if len(set(ids)) != profile.gpu_count:
        raise RuntimeError(f"Expected {profile.gpu_count} {profile.gpu_label} ({profile.backend}) "
                           f"device(s); stock llama.cpp reported:\n{listing.stdout}")
    return ids


def model_stamp(path: Path) -> list[int]:
    st = path.stat()
    return [st.st_size, st.st_mtime_ns]


def install(root: Path, hardware: str) -> None:
    profile = PROFILES[hardware]
    if platform.machine().lower() not in {"amd64", "x86_64"} or (platform.system(), profile.backend) not in ASSETS:
        raise RuntimeError("Only native Windows and Linux x64 builds are supported.")
    with state_lock(root):
        server = install_runtime(root, profile)
        get_devices(root, profile, server)  # Fail before the large download if the vendor runtime is unavailable.
        directory = model_dir(root, profile)
        verification = directory / "verified.json"
        existing = json_read(verification) if verification.is_file() else {}
        stamp = {}
        for name, digest, size in profile.files:
            path = directory / name
            if (path.is_symlink() or not path.is_file() or path.stat().st_size != size
                    or existing.get(name) != [digest, *model_stamp(path)]):
                checked_download(f"https://huggingface.co/{profile.repo}/resolve/{profile.revision}/{quote(name)}",
                                 path, digest, size)
            stamp[name] = [digest, *model_stamp(path)]
        json_write(directory / "verified.json", stamp)


def ensure_model(root: Path, profile: Profile) -> Path:
    directory = model_dir(root, profile)
    verified = directory / "verified.json"
    if not verified.is_file():
        raise RuntimeError("Model setup is not verified; run the install stage.")
    stamp = json_read(verified)
    for name, digest, size in profile.files:
        path = directory / name
        if (path.is_symlink() or not path.is_file() or path.stat().st_size != size
                or stamp.get(name) != [digest, *model_stamp(path)]):
            raise RuntimeError(f"Model file changed or is missing: {path}; rerun install to verify it.")
    return directory / profile.files[0][0]


def command(server: Path, profile: Profile, model: Path, devices: list[str]) -> list[str]:
    args = [str(server), "--model", str(model), "--alias", profile.alias, "--host", HOST,
            "--port", str(PORT), "--device", ",".join(devices), "--split-mode",
            "layer" if profile.gpu_count > 1 else "none", "--ctx-size", str(profile.context),
            "--parallel", "1", "--gpu-layers", "all", "--fit", "off", "--flash-attn", "on",
            "--cache-type-k", "q8_0", "--cache-type-v", "q8_0", "--load-mode", "none",
            "--lazy-mode", "off", "--jinja", "--no-ui"]
    if profile.alias == QFN[0]:
        args += ["--override-tensor", r"^per_layer_token_embd\.weight$=CPU",
                 "--n-cpu-moe", str(DUAL_CPU_MOE_LAYERS)]
    else:
        args += ["--cpu-moe"]
    return args


def memory_bytes() -> tuple[int, int]:
    if os.name == "nt":
        import ctypes

        class MemoryStatus(ctypes.Structure):
            _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [
                (name, ctypes.c_ulonglong) for name in
                ("total", "available", "page_total", "page_available", "virtual_total",
                 "virtual_available", "extended_available")
            ]

        memory = MemoryStatus()
        memory.length = ctypes.sizeof(memory)
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory)):
            raise ctypes.WinError()
        return int(memory.total), int(memory.available)
    meminfo = Path("/proc/meminfo").read_text()
    return tuple(int(re.search(rf"^{key}:\s+(\d+) kB", meminfo, re.M)[1]) * 1024
                 for key in ("MemTotal", "MemAvailable"))


def gguf_tensors(path: Path) -> dict[str, int]:
    """Return each v3 tensor's span, including its alignment padding."""
    file_size = path.stat().st_size
    with path.open("rb") as handle:
        def read(fmt):
            return struct.unpack("<" + fmt, handle.read(struct.calcsize("<" + fmt)))[0]

        def string(capture=False):
            n = read("Q")
            if n > file_size or (capture and n > 4096):
                raise ValueError(f"Invalid GGUF string length in {path}")
            if capture:
                return handle.read(n).decode("utf-8")
            handle.seek(n, os.SEEK_CUR)

        widths = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}

        def metadata(kind):
            if kind in widths:
                handle.seek(widths[kind], os.SEEK_CUR)
            elif kind == 8:
                string()
            elif kind == 9:
                item_kind, count = read("I"), read("Q")
                if item_kind in widths:
                    handle.seek(widths[item_kind] * count, os.SEEK_CUR)
                elif item_kind == 8 and count <= 10_000_000:
                    for _ in range(count):
                        string()
                else:
                    raise ValueError(f"Unsupported GGUF metadata array in {path}")
            else:
                raise ValueError(f"Unsupported GGUF metadata type in {path}")

        if handle.read(4) != b"GGUF" or read("I") != 3:
            raise ValueError(f"Expected GGUF v3: {path}")
        count, kv_count = read("Q"), read("Q")
        if not 0 < count <= 1_000_000 or kv_count > 100_000:
            raise ValueError(f"Invalid GGUF header counters in {path}")
        alignment = 32
        for _ in range(kv_count):
            key, kind = string(True), read("I")
            if key == "general.alignment" and kind == 4:
                alignment = read("I")
            else:
                metadata(kind)
        offsets = []
        for _ in range(count):
            name, ndims = string(True), read("I")
            if not 1 <= ndims <= 4:
                raise ValueError(f"Invalid GGUF tensor rank in {path}")
            handle.seek(8 * ndims + 4, os.SEEK_CUR)
            offsets.append((read("Q"), name))
        if not 0 < alignment <= 4096 or alignment & (alignment - 1):
            raise ValueError(f"Invalid GGUF alignment in {path}")
        start = (handle.tell() + alignment - 1) // alignment * alignment
    offsets.sort()
    bounds = [offset for offset, _ in offsets] + [file_size - start]
    if bounds[0] != 0 or any(a >= b for a, b in zip(bounds, bounds[1:])):
        raise ValueError(f"Invalid GGUF tensor offsets in {path}")
    return {name: end - offset for (offset, name), end in zip(offsets, bounds[1:])}


def expect_ram(profile: Profile, model: Path) -> None:
    # Match b12359's LLM_FFN_EXPS_REGEX and first-N layer override, not dense FFN.
    experts = re.compile(r"^blk\.(\d+)\.ffn_(up|down|gate|gate_up)_(ch|)exps")
    host_tensors = 0
    qfn = profile.alias == QFN[0]
    found_experts = found_ngram = False
    for name, _, _ in profile.files:
        for key, span in gguf_tensors(model.parent / Path(name).name).items():
            expert = experts.match(key)
            if expert and (not qfn or int(expert[1]) < DUAL_CPU_MOE_LAYERS):
                host_tensors += span
                found_experts = True
            if qfn and key == "per_layer_token_embd.weight":
                host_tensors += span
                found_ngram = True
    if not found_experts or (qfn and not found_ngram):
        raise RuntimeError("GGUF tensors did not match the pinned host placement rules.")
    target = host_tensors + HOST_RUNTIME_ALLOWANCE_GIB * GIB
    total, available = memory_bytes()
    budget = total - WINDOWS_RESERVE_GIB * GIB if os.name == "nt" else total
    if min(budget, available) < target:
        extra = f", keeping {WINDOWS_RESERVE_GIB} GiB outside the model budget" if os.name == "nt" else ""
        raise RuntimeError(f"{profile.alias} needs {target/GIB:.1f} GiB available host RAM for "
                           f"the selected tensor spans plus a {HOST_RUNTIME_ALLOWANCE_GIB} GiB runtime allowance{extra}; "
                           f"system reports {available/GIB:.1f} GiB available of {total/GIB:.1f} GiB. "
                           "Close other large apps; no SSD streaming fallback is enabled.")


def process_identity(pid: int) -> tuple[str, str] | None:
    if os.name == "nt":
        with win_process(pid, 0x1000) as (api, handle):
            return win_identity(api, handle) if handle else None
    try:
        proc = Path("/proc") / str(pid)
        fields = (proc / "stat").read_text().rsplit(")", 1)[1].split()
        if fields[0] == "Z":
            return None
        return os.readlink(proc / "exe"), fields[19]
    except (FileNotFoundError, ProcessLookupError):
        return None


@contextmanager
def win_process(pid: int, access: int):
    import ctypes
    from ctypes import wintypes
    api = ctypes.WinDLL("kernel32", use_last_error=True)
    api.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    api.OpenProcess.restype = wintypes.HANDLE
    api.CloseHandle.argtypes = (wintypes.HANDLE,)
    handle = api.OpenProcess(access, False, pid)
    if not handle and ctypes.get_last_error() not in (87, 1168):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        yield api, handle
    finally:
        if handle:
            api.CloseHandle(handle)


def win_identity(api, handle) -> tuple[str, str] | None:
    import ctypes
    from ctypes import wintypes as w
    api.GetExitCodeProcess.argtypes = (w.HANDLE, ctypes.POINTER(w.DWORD))
    api.QueryFullProcessImageNameW.argtypes = (w.HANDLE, w.DWORD, w.LPWSTR, ctypes.POINTER(w.DWORD))
    api.GetProcessTimes.argtypes = (w.HANDLE, *(ctypes.POINTER(w.FILETIME),) * 4)
    code, size = w.DWORD(), w.DWORD(32768)
    buf, times = ctypes.create_unicode_buffer(size.value), [w.FILETIME() for _ in range(4)]
    if not api.GetExitCodeProcess(handle, ctypes.byref(code)):
        raise ctypes.WinError(ctypes.get_last_error())
    if code.value != 259:  # STILL_ACTIVE
        return None
    if not (api.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size))
            and api.GetProcessTimes(handle, *(ctypes.byref(t) for t in times))):
        raise ctypes.WinError(ctypes.get_last_error())
    return buf.value, str((times[0].dwHighDateTime << 32) | times[0].dwLowDateTime)


def matches(info: dict, identity: tuple[str, str] | None) -> bool:
    return bool(identity and os.path.normcase(identity[0]) == os.path.normcase(info["binary"])
                and identity[1] == info["born"])


def alive_state(state: Path) -> dict | None:
    track = state / "process.json"
    if not track.is_file():
        return None
    info = json_read(track)
    if matches(info, process_identity(info["pid"])):
        return info
    return None


def health() -> bool:
    conn = HTTPConnection(HOST, PORT, timeout=1)
    try:
        conn.request("GET", "/health")
        response = conn.getresponse()
        return response.status == 200 and json.loads(response.read(8192)).get("status") == "ok"
    except (OSError, ValueError):
        return False
    finally:
        conn.close()


def ensure_port_free() -> None:
    with socket.socket() as listener:
        if os.name == "nt":
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            listener.bind((HOST, PORT))
        except OSError as error:
            raise RuntimeError(f"Port {PORT} is already occupied; no other process was stopped.") from error


def launch(root: Path, hardware: str) -> dict:
    with state_lock(root) as state:
        existing = alive_state(state)
        if existing:
            if existing["profile"] != hardware:
                raise RuntimeError("Another setup-owned model is running; stop it explicitly first.")
            return existing
        ensure_port_free()
        profile = PROFILES[hardware]
        model, server = ensure_model(root, profile), binary(root, profile)
        expect_ram(profile, model)
        devices = get_devices(root, profile, server)
        args = command(server, profile, model, devices)
        detach = ({"creationflags": subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP}
                  if os.name == "nt" else {"start_new_session": True})
        fd, log_name = tempfile.mkstemp(prefix="llama-", suffix=".log", dir=state)
        with os.fdopen(fd, "wb") as log:
            proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                    cwd=server.parent, env=engine_env(root, profile, server), **detach)
        try:
            identity = process_identity(proc.pid)
            if identity is None or os.path.normcase(identity[0]) != os.path.normcase(str(server)):
                raise RuntimeError(f"llama.cpp exited before startup; see {log_name}")
            info = {"pid": proc.pid, "binary": identity[0], "born": identity[1], "profile": hardware,
                    "model": profile.alias, "context": profile.context, "log": log_name, "base_url": BASE_URL}
            json_write(state / "process.json", info)
        except BaseException:
            if proc.poll() is None:
                proc.terminate()
            raise
        return info


def start(root: Path, hardware: str, *, wait_seconds: int = 900) -> dict:
    info = launch(root, hardware)
    end = time.monotonic() + wait_seconds
    while time.monotonic() < end:
        if not matches(info, process_identity(info["pid"])):
            raise RuntimeError(f"llama.cpp exited before reaching readiness; see {info['log']}")
        if health() and matches(info, process_identity(info["pid"])):
            return {**info, "status": "ready"}
        time.sleep(2)
    return {**info, "status": "starting"}


def stop(root: Path) -> bool:
    with state_lock(root) as state:
        info = alive_state(state)
        if not info:
            return False
        pid = info["pid"]
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes as w
            with win_process(pid, 0x1000 | 0x0001) as (api, handle):
                if not handle or not matches(info, win_identity(api, handle)):
                    return False
                api.TerminateProcess.argtypes = (w.HANDLE, w.UINT)
                if not api.TerminateProcess(handle, 0):
                    raise ctypes.WinError(ctypes.get_last_error())
        else:
            try:
                fd = os.pidfd_open(pid)
            except ProcessLookupError:
                return False
            try:
                if not matches(info, process_identity(pid)):
                    return False
                signal.pidfd_send_signal(fd, signal.SIGTERM)
            finally:
                os.close(fd)
        # Keep ownership state until the process actually exits; restart must not race it.
        return True


def status(root: Path) -> dict:
    info = alive_state(root / "engine")
    if not info:
        return {"status": "stopped", "base_url": BASE_URL}
    return {**info, "status": "ready" if health() else "starting"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "start", "stop", "status"))
    parser.add_argument("--profile", choices=PROFILES)
    parser.add_argument("--root", type=Path, default=default_root())
    parser.add_argument("--wait-seconds", type=int, default=900)
    args = parser.parse_args()
    if args.action in {"install", "start"} and not args.profile:
        parser.error("--profile is required for install and start")
    if args.wait_seconds < 0:
        parser.error("--wait-seconds must be nonnegative")
    root = args.root.expanduser().resolve()
    try:
        if args.action == "install":
            install(root, args.profile)
        elif args.action == "start":
            info = start(root, args.profile, wait_seconds=args.wait_seconds)
            print(json.dumps(info))
            if args.wait_seconds and info["status"] != "ready":
                return 1
        elif args.action == "stop":
            print(json.dumps({"stop_requested": stop(root)}))
        else:
            print(json.dumps(status(root)))
    except (OSError, RuntimeError, ValueError, struct.error, subprocess.SubprocessError) as error:
        print(f"llama.cpp: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
