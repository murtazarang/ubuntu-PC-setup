#!/usr/bin/env python3
"""Merge requested Firefox policies, preserving all unrelated policy settings."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def merge(policy, release=False):
    path = Path(__file__).with_name("firefox-policy.py")
    command = [sys.executable, str(path)] + (["--release"] if release else [])
    old = policy.read_text(encoding="utf-8-sig") if policy.exists() else "{}"
    result = subprocess.run(command, input=old, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not merge Firefox policy")
    policy.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".policies-", dir=policy.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(result.stdout)
        os.replace(name, policy)
    finally:
        if os.path.exists(name):
            os.unlink(name)


if __name__ == "__main__":
    cli = argparse.ArgumentParser()
    cli.add_argument("policy", type=Path, help="Firefox distribution/policies.json path")
    cli.add_argument("--release", action="store_true")
    args = cli.parse_args()
    merge(args.policy, args.release)
