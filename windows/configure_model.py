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


def load_config(agent_dir):
    """Follow OMP's YAML precedence without hiding a legacy JSON config."""
    yml = agent_dir / "models.yml"
    alternate = agent_dir / "models.yaml"
    legacy = agent_dir / "models.json"
    path = yml if yml.exists() or not alternate.exists() else alternate
    if path.exists():
        data = yaml.safe_load(path.read_text(encoding="utf-8-sig"))
        data = {} if data is None else data
    elif legacy.exists():
        # OMP migrates JSON only while both YAML files are absent. Preserve its
        # providers before creating YAML; leave the original JSON untouched.
        data = json.loads(legacy.read_text(encoding="utf-8-sig"))
    else:
        data = {}
    if not isinstance(data, dict):
        raise ValueError("Existing model configuration must be a mapping")
    return path, data


def model_id_from_response(body):
    if not isinstance(body, dict) or not isinstance(body.get("data"), list) or not body["data"]:
        raise ValueError("Local endpoint did not return any models")
    first = body["data"][0]
    model = first.get("id") if isinstance(first, dict) else None
    if not isinstance(model, str) or not model.strip() or any(c in model for c in "\r\n"):
        raise ValueError("Local endpoint did not return a valid model ID")
    return model


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--agent-dir", required=True, type=Path)
    p.add_argument("--port", required=True, choices=["8000", "8080", "8095"])
    args = p.parse_args()
    with urllib.request.urlopen(f"http://127.0.0.1:{args.port}/v1/models", timeout=10) as r:
        body = json.load(r)
    model = model_id_from_response(body)
    path, data = load_config(args.agent_dir)
    save(path, merge(data, model, args.port))
    print("local-inference/" + model)


if __name__ == "__main__":
    main()
