#!/usr/bin/env python3
"""Merge requested Firefox policies, preserving all unrelated policy settings."""
import argparse
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def existing_ublock(profiles_ini):
    """Inspect Firefox's declared profiles, never infer absence from unreadable data."""
    if not profiles_ini.exists():
        return False
    profiles = configparser.ConfigParser(interpolation=None)
    profiles.read_string(profiles_ini.read_text(encoding="utf-8-sig"))
    for section in profiles.sections():
        if not section.startswith("Profile") or not profiles.has_option(section, "Path"):
            continue
        directory = Path(profiles.get(section, "Path"))
        if profiles.get(section, "IsRelative", fallback="1") == "1":
            directory = profiles_ini.parent / directory
        extension_file = directory / "extensions.json"
        if extension_file.exists():
            data = json.loads(extension_file.read_text(encoding="utf-8-sig"))
            if not isinstance(data, dict) or not isinstance(data.get("addons", []), list):
                raise ValueError("Invalid Firefox extensions metadata; cannot safely initialize uBlock")
            if any(addon.get("id") == "uBlock0@raymondhill.net" for addon in data.get("addons", [])):
                return True
        if (directory / "extensions" / "uBlock0@raymondhill.net.xpi").exists():
            return True
    return False


def merge(policy, release=False, profiles_ini=None):
    path = Path(__file__).with_name("firefox-policy.py")
    command = [sys.executable, str(path)] + (["--release"] if release else [])
    old = policy.read_text(encoding="utf-8-sig") if policy.exists() else "{}"
    if not release and profiles_ini is not None and existing_ublock(profiles_ini):
        existing = json.loads(old).get("policies", {}).get("3rdparty", {}).get("Extensions", {}).get("uBlock0@raymondhill.net")
        if existing is None:
            raise RuntimeError(
                "Existing uBlock profile detected. Initial managed filters replace personal filters and list choices, "
                "so no Firefox policies were changed. Keep your current profile; add the requested Twitch filter "
                "and lists through uBlock's dashboard instead, or explicitly approve replacing those settings."
            )
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
    cli.add_argument("--profiles", type=Path)
    args = cli.parse_args()
    merge(args.policy, args.release, args.profiles)
