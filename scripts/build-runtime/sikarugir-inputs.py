#!/usr/bin/env python3
"""Prepare and authenticate the approved upstream input transfer for one build."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sikarugir_candidate", ROOT / "scripts/build-runtime/build-sikarugir-candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


def receipt(commit, build_id):
    pin = ROOT / "upstream/sikarugir-runtime.json"
    return {"kind": "PortsideSikarugirInputTransfer", "portsideCommit": commit, "buildId": build_id,
            "approvedInputsSha256": candidate.sha256(pin)}


def verify(directory, commit, build_id):
    file = directory / "sikarugir-inputs.json"
    if file.is_symlink() or not file.is_file() or json.loads(file.read_text()) != receipt(commit, build_id):
        raise RuntimeError("Sikarugir inputs do not belong to this source revision and build")
    candidate.verify_inputs(directory, json.loads((ROOT / "upstream/sikarugir-runtime.json").read_text()))


def prepare(directory, commit, build_id):
    if directory.exists():
        raise RuntimeError("Input download directory must be new")
    approved = json.loads((ROOT / "upstream/sikarugir-runtime.json").read_text())
    directory.mkdir(parents=True)
    for item in approved["components"]:
        # URLs are source-controlled pins, never remote discovery or a fallback.
        if not re.fullmatch(r"https://(?:github.com/Sikarugir-App/[^?#]+|raw.githubusercontent.com/Sikarugir-App/[^?#]+)", item["url"]):
            raise RuntimeError("Unapproved input source")
        name = item["fileName"]
        if Path(name).name != name or name in ("", ".", ".."):
            raise RuntimeError("Unsafe input name")
        subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https",
                        "--connect-timeout", "30", "--max-time", "600", "--output", str(directory / name), item["url"]], check=True)
    candidate.verify_inputs(directory, approved)
    (directory / "sikarugir-inputs.json").write_text(json.dumps(receipt(commit, build_id), indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "verify"])
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    build_id = os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
    (prepare if args.action == "prepare" else verify)(args.directory, commit, build_id)
    print("Approved Sikarugir inputs verified for this source revision and workflow run.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Sikarugir input transfer failed", file=sys.stderr)
        sys.exit(1)
