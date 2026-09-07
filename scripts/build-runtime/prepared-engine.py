#!/usr/bin/env python3
"""Bind Linux runtime-engine preparation to its native consumer in the same run."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("publication", Path(__file__).with_name("validate-publication.py"))
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def source_metadata(root, expected):
    value = publication.read_json(root, "engine-input.json")
    publication.require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1 and value["kind"] == "PortsideRuntimeEngine"
                        and value["engineVersion"] == expected["engineVersion"]
                        and value["source"]["commit"] == expected["sourceCommit"]
                        and value["source"]["snapshotChecksum"] == expected["sourceSnapshotChecksum"]
                        and value["artifact"]["fileName"] == expected["archiveName"]
                        and value["artifact"]["storageKey"] == expected["archiveKey"]
                        and re.fullmatch(r"[0-9a-f]{64}", value["artifact"]["sha256"])
                        and type(value["artifact"]["size"]) is int and value["artifact"]["size"] > 0
                        and isinstance(value["build"]["id"], str) and bool(value["build"]["id"]),
                        "Prepared engine does not match the recipe-selected published input")


def record(root, version, sha, run_id, attempt, expected):
    source_metadata(root, expected)
    name = "PortsideWineEngine-" + version + ".tar.xz"
    archive = root / name
    publication.require(archive.is_file() and not archive.is_symlink(), "Missing regular prepared engine archive")
    receipt = {"kind": "PortsidePreparedRuntimeEngine", "portsideCommit": sha, "buildId": run_id + "-" + attempt,
               "runtimeVersion": version, "engineInputSha256": digest(root / "engine-input.json"),
               "artifact": {"fileName": name, "size": archive.stat().st_size, "sha256": digest(archive)}}
    publication.check_build(sha, receipt["buildId"], sha, run_id)
    publication.check_archive(root, name, receipt["artifact"])
    path = root / "prepared-engine.json"
    publication.require(not path.is_symlink(), "Prepared engine receipt must not replace a symlink")
    path.write_text(json.dumps(receipt, indent=2) + "\n")


def verify(root, version, sha, run_id, expected):
    source_metadata(root, expected)
    receipt = publication.read_json(root, "prepared-engine.json")
    publication.check_build(receipt["portsideCommit"], receipt["buildId"], sha, run_id)
    name = "PortsideWineEngine-" + version + ".tar.xz"
    publication.require(receipt["kind"] == "PortsidePreparedRuntimeEngine" and receipt["runtimeVersion"] == version
                        and receipt["artifact"]["fileName"] == name
                        and receipt["engineInputSha256"] == digest(root / "engine-input.json"),
                        "Prepared engine metadata/version changed after Linux validation")
    publication.check_archive(root, name, receipt["artifact"])
    checksum = root / ("PortsideWineEngine-" + version + ".sha256")
    publication.require(not checksum.is_symlink(), "Prepared engine checksum must not replace a symlink")
    checksum.write_text(receipt["artifact"]["sha256"] + "  " + name + "\n")


def main():
    publication.require(len(sys.argv) == 4 and sys.argv[1] in ("record", "verify"),
                        "Usage: prepared-engine.py record|verify DIRECTORY RUNTIME_VERSION")
    operation, directory, version = sys.argv[1:]
    root = Path(directory).absolute()
    publication.require(root.resolve() == root and root.is_relative_to(ROOT), "Prepared engine directory must stay in its checkout")
    publication.require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+_-]*", version), "Invalid prepared runtime version")
    sha = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    expected = json.loads(subprocess.check_output([str(ROOT / "scripts/build-runtime/resolve-engine.sh")], text=True))
    if operation == "record":
        record(root, version, sha, os.environ["GITHUB_RUN_ID"], os.environ["GITHUB_RUN_ATTEMPT"], expected)
    else:
        verify(root, version, sha, os.environ["GITHUB_RUN_ID"], expected)
    print("Prepared runtime engine " + operation + " passed; source, workflow, version and bytes match.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Prepared runtime engine validation failed", file=sys.stderr)
        sys.exit(1)
