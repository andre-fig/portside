#!/usr/bin/env python3
"""Reject embedded personal build paths without printing the matched values."""
import mmap
from pathlib import Path
import re
import sys

# /Users/Shared is a system-wide macOS location, not a developer home.
PERSONAL_PATH = re.compile(rb"/(?:Users|home)/(?!Shared/)[^/\x00\r\n]+/")


def validate(root):
    if not root.is_dir():
        raise RuntimeError("Engine personal-path audit requires a directory")
    for path in root.rglob("*"):
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            continue
        with path.open("rb") as handle:
            with mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) as data:
                if PERSONAL_PATH.search(data):
                    raise RuntimeError("Engine contains an embedded personal build path; fix compiler/install prefixes before packaging")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise RuntimeError("Usage: validate-engine-privacy.py ENGINE_ROOT")
        validate(Path(sys.argv[1]).resolve(strict=True))
        print("Engine personal-path audit passed.")
    except (RuntimeError, OSError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Engine personal-path audit failed", file=sys.stderr)
        sys.exit(1)
