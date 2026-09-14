#!/usr/bin/env python3
"""Install owned skills with explicit identities and collision checks."""
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

MANIFEST = ".dotskills-manifest.json"
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\Z")


def install(target, sources):
    target = Path(target)
    manifest_path = target / MANIFEST
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"schema_version": 1, "skills": {}}
    if manifest.get("schema_version") != 1 or not isinstance(manifest.get("skills"), dict):
        raise ValueError("unsupported skill identity manifest")
    skills = manifest["skills"]
    owners = {}
    for identity, entry in skills.items():
        path = entry.get("path", "")
        if not NAME.fullmatch(path) or path in owners:
            raise ValueError(f"invalid or duplicate installed path: {path}")
        owners[path] = identity
    pending = {}
    for source, directory in sources:
        directory = Path(directory)
        name, pack = directory.name, source.split("/")[-1]
        if not NAME.fullmatch(name) or not NAME.fullmatch(pack):
            raise ValueError(f"invalid skill identity: {source}:{name}")
        if not (directory / "SKILL.md").is_file():
            continue
        identity = f"{pack}:{name}"
        entry = {"path": name, "source": source}
        if identity in pending or (identity in skills and skills[identity] != entry):
            raise ValueError(f"duplicate skill identity: {identity}")
        owner = owners.get(name)
        dest = target / name
        if owner and owner != identity:
            raise ValueError(f"skill collision: {name} belongs to {owner}, requested by {identity}")
        if dest.is_symlink() or (dest.exists() and owner != identity):
            raise ValueError(f"unmanaged skill collision: {dest}; move it aside before installing {identity}")
        owners[name] = identity
        pending[identity] = (directory, entry)
    # All collisions are checked before any installed skill changes.
    target.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".dotskills-stage-", dir=target) as staging:
        staging = Path(staging)
        for identity, (directory, entry) in pending.items():
            shutil.copytree(directory, staging / entry["path"])
        for identity, (_, entry) in pending.items():
            dest = target / entry["path"]
            if dest.exists():
                shutil.rmtree(dest)
            os.replace(staging / entry["path"], dest)
            skills[identity] = entry
        temporary_manifest = staging / MANIFEST
        temporary_manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        os.replace(temporary_manifest, manifest_path)
    print(f"Installed {len(pending)} owned skills; identities: {manifest_path}")


if __name__ == "__main__":
    try:
        if len(sys.argv) < 2 or len(sys.argv[2:]) % 2:
            raise ValueError("usage: install_owned.py TARGET [SOURCE SKILL_DIRECTORY ...]")
        install(sys.argv[1], zip(sys.argv[2::2], sys.argv[3::2]))
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(f"dotskills: {error}")
