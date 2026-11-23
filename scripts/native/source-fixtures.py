#!/usr/bin/env python3
"""Snapshot native source-test inputs outside macOS protected folders."""
import hashlib
import json
from pathlib import Path
import shutil
import sys


def inventory(root):
    sources = root / "yen-terminal/ghostty/macos/Sources"
    swift = sorted(sources.rglob("*.swift"))
    if not swift:
        raise ValueError("native source inventory is empty")
    # YEN's own sources, for lints that must not read upstream engine files.
    swift += sorted((root / "yen-terminal/overlays/macos/Sources").rglob("*.swift"))
    paths = swift + [root / name for name in (
        "_docs/12-commands.md", "_docs/13-desktop-features.md",
        "yen-terminal/ghostty/src/config/Config.zig",
    )]
    result = {}
    for path in paths:
        data = path.read_bytes()
        if not data:
            raise ValueError(f"empty source fixture: {path.relative_to(root)}")
        result[str(path.relative_to(root))] = hashlib.sha256(data).hexdigest()
    return result


def run(mode, root, destination):
    expected = inventory(root)
    manifest = destination / "manifest.json"
    if mode == "prepare":
        if any(destination.iterdir()):
            raise ValueError("fixture destination must be empty")
        for relative in expected:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / relative, target)
        manifest.write_text(json.dumps(expected, sort_keys=True))
    elif mode != "verify":
        raise ValueError("expected prepare or verify")
    if json.loads(manifest.read_text()) != expected or inventory(destination) != expected:
        raise ValueError("native source fixtures differ from the current checkout")
    print(f"RECEIPT gate=native-source-fixtures mode={mode} files={len(expected)} result=PASS")


if __name__ == "__main__":
    try:
        run(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]))
    except (OSError, ValueError, IndexError) as error:
        print(f"native source fixtures: {error}", file=sys.stderr)
        sys.exit(1)
