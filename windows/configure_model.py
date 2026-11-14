#!/usr/bin/env python3
"""Add a local OpenAI-compatible model to OMP without changing other providers."""
import argparse
import os
from pathlib import Path
import tempfile
import urllib.request
import json
import yaml


def merge(data, model_id, port):
    if not isinstance(data, dict):
        raise ValueError("models.yml must be a mapping")
    providers = data.setdefault("providers", {})
    if not isinstance(providers, dict):
        raise ValueError("providers must be a mapping")
    entry = {
        "baseUrl": f"http://127.0.0.1:{port}/v1", "api": "openai-completions",
        "auth": "none", "compat": {"supportsDeveloperRole": False},
        "models": [{"id": model_id, "name": "Local " + model_id,
                    "reasoning": True, "input": ["text"],
                    "contextWindow": 32768, "maxTokens": 4096,
                    "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}}],
    }
    old = providers.get("local-inference")
    if old is not None and old != entry:
        raise ValueError("Existing local-inference provider differs; leaving it unchanged")
    providers["local-inference"] = entry
    return data


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".models-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--agent-dir", required=True, type=Path)
    p.add_argument("--port", required=True, choices=["8080", "8095"])
    args = p.parse_args()
    with urllib.request.urlopen(f"http://127.0.0.1:{args.port}/v1/models", timeout=10) as r:
        body = json.load(r)
    model = body["data"][0]["id"]
    if not isinstance(model, str) or not model.strip() or "\n" in model:
        raise ValueError("Local endpoint did not return a valid model ID")
    path = args.agent_dir / "models.yml"
    if not path.exists() and (args.agent_dir / "models.yaml").exists():
        path = args.agent_dir / "models.yaml"
    data = yaml.safe_load(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
    save(path, merge(data or {}, model, args.port))
    print("local-inference/" + model)


if __name__ == "__main__":
    main()
