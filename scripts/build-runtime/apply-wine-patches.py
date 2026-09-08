#!/usr/bin/env python3
"""Verify Portside's patch series and apply it only to a disposable source copy."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def verified_series(root=ROOT):
    directory = root / "upstream/patches/wine"
    series = json.loads((directory / "series.json").read_text())
    lock = json.loads((root / "upstream/lock.json").read_text())
    source = next(item for item in lock["repositories"] if item["name"] == "wine")
    if series["schemaVersion"] != 1 or series["sourceCommit"] != source["commit"]:
        raise RuntimeError("Wine patch series does not match the locked source")
    names = set()
    for item in series["patches"]:
        name = item["file"]
        if not re.fullmatch(r"[0-9]{4}-[a-z0-9-]+\.patch", name) or name in names:
            raise RuntimeError("Invalid or duplicate Wine patch name")
        names.add(name)
        path = directory / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
            raise RuntimeError("Wine patch checksum mismatch")
    if names != {p.name for p in directory.glob("*.patch")}:
        raise RuntimeError("Unlisted Wine patch")
    return series


def apply(source, root=ROOT):
    series = verified_series(root)
    source = source.resolve(strict=True)
    if (not source.is_relative_to(root.resolve()) or
            source.parts[-3:] != ("work", "wine", "source") or
            source.is_relative_to((root / "vendor").resolve())):
        raise RuntimeError("Wine patches require a disposable work/wine/source copy inside the checkout")
    # Patches are checksum-pinned, reviewed source inputs. Never patch vendor or
    # silently accept an already-patched/different source tree.
    for item in series["patches"]:
        patch = root / "upstream/patches/wine" / item["file"]
        command = ["patch", "--batch", "--forward", "--fuzz=0", "-p1", "-d", str(source), "-i", str(patch)]
        for arguments in ([*command, "--dry-run"], command):
            result = subprocess.run(arguments, capture_output=True, timeout=30)
            if result.returncode:
                raise RuntimeError("Wine patch did not apply cleanly: " + item["file"])
    return series


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise RuntimeError("Usage: apply-wine-patches.py --verify|SOURCE_COPY")
        result = verified_series() if sys.argv[1] == "--verify" else apply(Path(sys.argv[1]))
        print(json.dumps(result, sort_keys=True))
    except (OSError, ValueError, KeyError, StopIteration, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Wine patch validation failed", file=sys.stderr)
        sys.exit(1)
