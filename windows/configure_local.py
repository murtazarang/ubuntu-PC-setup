#!/usr/bin/env python3
"""Prepare native Oh My Pi/Paseo JSON settings without disturbing other entries.

Only Kiwix MCP and Paseo provider are configured here. Installers and inference
startup are deliberately handled elsewhere. Never enables cloud model providers.
"""
import argparse
import json
import os
from pathlib import Path
import tempfile


def read_map(path):
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".setup-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def merge_mcp(data, bridge, zim_dir, legacy_uvx=None):
    servers = data.setdefault("mcpServers", {})
    if not isinstance(servers, dict):
        raise ValueError("mcpServers must be an object")
    entry = {"type": "stdio", "command": str(bridge),
             "args": [str(zim_dir)]}
    existing = servers.get("openzim")
    legacy = {"type": "stdio", "command": str(legacy_uvx),
              "args": ["--offline", "openzim-mcp==3.4.0", str(zim_dir)]}
    if existing is not None and existing != entry and not (legacy_uvx and existing == legacy):
        raise ValueError("An openzim entry already exists and differs; no changes made")
    servers["openzim"] = entry
    return data


def merge_paseo(data, omp):
    agents = data.setdefault("agents", {})
    providers = agents.setdefault("providers", {})
    provider = providers.setdefault("omp", {})
    if not isinstance(provider, dict):
        raise ValueError("Paseo OMP provider must be an object")
    command = [str(omp)]
    if "command" in provider and provider["command"] != command:
        raise ValueError("Existing Paseo OMP command differs; no changes made")
    provider["enabled"] = True
    provider["command"] = command
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent-dir", required=True, type=Path)
    parser.add_argument("--paseo-config", required=True, type=Path)
    parser.add_argument("--bridge", required=True, type=Path)
    parser.add_argument("--legacy-uvx", type=Path)
    parser.add_argument("--omp", required=True, type=Path)
    parser.add_argument("--zim-dir", required=True, type=Path)
    args = parser.parse_args()
    # Validate both merges before writing either file.
    mcp_path = args.agent_dir / "mcp.json"
    mcp = merge_mcp(read_map(mcp_path), args.bridge, args.zim_dir, args.legacy_uvx)
    paseo = merge_paseo(read_map(args.paseo_config), args.omp)
    atomic_json(mcp_path, mcp)
    atomic_json(args.paseo_config, paseo)


if __name__ == "__main__":
    main()
