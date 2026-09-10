#!/usr/bin/env python3
"""Assemble an isolated integration candidate from approved local upstream inputs.

No downloads, installed prefixes, signing overrides or publication. The current
commercial workflows are not silently switched by this development entry point.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def verify_launcher_privacy(launcher):
    details = subprocess.run(["codesign", "-dv", str(launcher)], check=True, capture_output=True, text=True).stderr
    flags = re.search(r"flags=0x([0-9a-fA-F]+)", details)
    if not flags or not int(flags.group(1), 16) & 0x10000:
        raise RuntimeError("Sikarugir launcher must enable Hardened Runtime")
    data = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(launcher)], check=True, capture_output=True).stdout
    if plistlib.loads(data) != {"com.apple.security.cs.disable-library-validation": True}:
        raise RuntimeError("Sikarugir launcher resource-access entitlements do not match the privacy policy")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_inputs(directory, specification):
    if specification.get("schemaVersion") != 1 or specification.get("kind") != "PortsideApprovedSikarugirInputs":
        raise RuntimeError("Unrecognized Sikarugir input contract")
    components = specification["components"]
    if len(components) != 3 or {item["id"] for item in components} != {"template", "engine", "winetricks"}:
        raise RuntimeError("Expected exactly the approved template, engine and winetricks")
    result = {}
    for item in components:
        name = item["fileName"]
        if PurePosixPath(name).name != name or name in ("", ".", "..") or "\\" in name:
            raise RuntimeError("Unsafe input filename")
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size != item["size"] or sha256(path) != item["sha256"]:
            raise RuntimeError("Sikarugir input size/checksum mismatch: " + item["id"])
        result[item["id"]] = path
    return result


def extract(archive, destination, root_name):
    if not hasattr(tarfile, "data_filter"):
        raise RuntimeError("Python 3.12+ is required for safe extraction")
    seen = set()
    with tarfile.open(archive, "r:xz") as handle:
        # Preflight the actual archive inventory once. tarfile may reapply its
        # extraction filter to a hardlink's target; that is not a duplicate entry.
        for member in handle.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name or not path.parts or path.parts[0] != root_name or str(path) in seen:
                raise RuntimeError("Unexpected or duplicate archive member")
            seen.add(str(path))
        handle.extractall(destination, filter=tarfile.data_filter)


def contained_executable(root, relative):
    path = root / relative
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()) or not path.stat().st_mode & 0o111:
        raise RuntimeError("Missing contained runtime executable: " + relative)
    return path


def assemble(inputs, output, host, version, specification, checkout=ROOT):
    checkout = checkout.resolve()
    output = output.resolve()
    if not output.is_relative_to(checkout / "build") or output == checkout / "build" or output.exists():
        raise RuntimeError("Candidate output must be a new directory under this checkout's build directory")
    verified = verify_inputs(inputs, specification)
    if host.is_symlink() or not host.is_file() or not host.stat().st_mode & 0o111:
        raise RuntimeError("A locally built PortsideRuntimeHost is required")
    by_id = {item["id"]: item for item in specification["components"]}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".sikarugir-candidate-", dir=output.parent) as temporary:
        work = Path(temporary)
        extract(verified["template"], work / "template", by_id["template"]["archiveRoot"])
        extract(verified["engine"], work / "engine", by_id["engine"]["archiveRoot"])
        stage = work / "result"
        stage.mkdir()
        wrapper = stage / "PortsideBaseline.app"
        (work / "template" / by_id["template"]["archiveRoot"]).rename(wrapper)
        engine = wrapper / "Contents/SharedSupport/wine"
        if engine.exists() or engine.is_symlink():
            raise RuntimeError("The approved template unexpectedly contains an engine")
        engine.parent.mkdir(parents=True, exist_ok=True)
        (work / "engine" / by_id["engine"]["archiveRoot"]).rename(engine)
        launcher = contained_executable(wrapper, "Contents/MacOS/Sikarugir")
        sdk = contained_executable(wrapper, "Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk")
        contained_executable(engine, "bin/wine")
        contained_executable(engine, "bin/wineserver")
        for component in (launcher, sdk):
            subprocess.run(["codesign", "--verify", "--strict", str(component)], check=True, capture_output=True)
        target_host = wrapper / "Contents/MacOS/PortsideRuntimeHost"
        if target_host.exists() or target_host.is_symlink():
            raise RuntimeError("The template unexpectedly contains a Portside host")
        shutil.copy2(host, target_host)
        winetricks = wrapper / "Contents/SharedSupport/winetricks"
        if winetricks.is_symlink() or winetricks.is_dir():
            raise RuntimeError("Unexpected winetricks destination")
        shutil.copy2(verified["winetricks"], winetricks)
        winetricks.chmod(0o755)
        info_path = wrapper / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info.update({"CFBundleIdentifier": "com.portside.runtime",
                     "CFBundleName": "PortsideBaseline", "CFBundleDisplayName": "Portside",
                     "CFBundleShortVersionString": version, "CFBundleVersion": version,
                     "Program Name and Path": "/Program Files (x86)/Steam/steam.exe", "Program Flags": "-preventsteamdiscovery",
                     "D3DMETAL": 0, "DXMT": 0, "DXVK": 0, "WINEMSYNC": 1, "WINEESYNC": 1,
                     "Skip Mono": 0, "Skip Gecko": 0, "Winetricks silent": 1,
                     "PortsideRuntime": True, "PortsideIntegration": "sikarugir",
                     "PortsideRenderer": "WineD3D", "PortsideD3DMetal": 0, "PortsideDXMT": 0, "PortsideDXVK": 0})
        info.pop("NSMicrophoneUsageDescription", None)
        info_path.write_bytes(plistlib.dumps(info))
        resource = wrapper / "Contents/Resources/portside-runtime.json"
        configuration = {"integration": "sikarugir", "version": version, "launchDiagnosticsVersion": 0,
                         "wineRelativePath": "Contents/SharedSupport/wine", "prefixRelativePath": "Contents/SharedSupport/prefix",
                         "winetricksRelativePath": "Contents/SharedSupport/winetricks",
                         "steamExecutable": "C:\\Program Files (x86)\\Steam\\steam.exe", "wineDebug": "-all",
                         "environment": {"WINEMSYNC": "1", "WINEESYNC": "1"}}
        resource.write_text(json.dumps(configuration, indent=2) + "\n")
        provenance = {"schemaVersion": 1, "kind": "PortsideSikarugirIntegrationCandidate", "assembledBy": "Portside",
                      "distributionReady": False, "engineVersion": specification["engineVersion"],
                      "inputs": specification["components"], "hostSha256": sha256(host),
                      "launcherSha256": sha256(launcher), "sdkSha256": sha256(sdk),
                      "hostSourceSha256": sha256(checkout / "apps/runtime-host/Sources/PortsideRuntimeHost/main.swift")}
        (stage / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
        # The caller must use a new disposable external prefix for execution.
        # No prefix is created, migrated or linked by this assembly operation.
        stage.rename(output)
    return output / "PortsideBaseline.app"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--version", default="0.1.35")
    args = parser.parse_args()
    specification = json.loads((ROOT / "upstream/sikarugir-runtime.json").read_text())
    assemble(args.inputs, args.output, args.host, args.version, specification)
    print("Sikarugir integration candidate assembled from verified inputs; distribution acceptance remains pending.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, tarfile.TarError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Sikarugir candidate assembly failed", file=sys.stderr)
        sys.exit(1)
