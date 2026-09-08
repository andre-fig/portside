#!/usr/bin/env python3
"""Recheck transferred archives before Linux signing/publication, without extraction.

Native execution/layout checks remain mandatory in the preceding macOS job.
These checks bind its archived bytes to this checkout and workflow run.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_json(root, name):
    path = root / name
    require(not path.is_symlink() and path.is_file(), "Missing regular publication metadata")
    return json.loads(path.read_text())


def check_build(commit, build_id, expected_sha, run_id):
    require(commit == expected_sha, "Publication source does not match checkout")
    require(re.fullmatch(re.escape(str(run_id)) + r"-[1-9][0-9]*", build_id),
            "Publication evidence belongs to another workflow run")


def check_archive(root, name, metadata):
    require(re.fullmatch(r"Portside(?:Wrapper|WineEngine|Winetricks)-[A-Za-z0-9][A-Za-z0-9.+_-]*\.tar\.xz", name),
            "Invalid publication archive name")
    path = root / name
    require(not path.is_symlink() and path.is_file(), "Missing regular publication archive")
    require(type(metadata["size"]) is int and metadata["size"] > 0 and path.stat().st_size == metadata["size"],
            "Publication archive size mismatch")
    require(re.fullmatch(r"[0-9a-f]{64}", metadata["sha256"]), "Invalid archive checksum")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    require(digest.hexdigest() == metadata["sha256"], "Publication archive checksum mismatch")


def validate_engine_metadata(root, sha, run_id):
    metadata = read_json(root, "engine-metadata.json")
    provenance = read_json(root, "engine-provenance.json")
    check_build(metadata["build"]["portsideCommit"], metadata["build"]["id"], sha, run_id)
    require(metadata["build"]["targetArchitecture"] == "x86_64", "Unexpected Wine target architecture")
    require(provenance["portsideCommit"] == sha and provenance["buildId"] == metadata["build"]["id"],
            "Engine provenance does not match build")
    for key in ("kind", "engineVersion", "source", "dependencies"):
        require(provenance[key] == metadata[key], "Engine provenance and metadata disagree")
    require(metadata["kind"] == "PortsideRuntimeEngine", "Unexpected engine kind")
    artifact = metadata["artifact"]
    name = "PortsideWineEngine-" + metadata["engineVersion"] + ".tar.xz"
    require(artifact["fileName"] == name, "Engine archive does not match version")
    require(provenance["artifact"] == {key: artifact[key] for key in ("fileName", "size", "sha256")},
            "Engine archive provenance mismatch")
    check_archive(root, name, artifact)


def validate_local_engine(root, sha, expected):
    validate_engine_metadata(root, sha, "local-" + sha)
    metadata = read_json(root, "engine-metadata.json")
    require(metadata["build"].get("producer") == "local-pre-push", "Expected a local source build")
    require(metadata["engineVersion"] == expected["engineVersion"]
            and metadata["source"]["commit"] == expected["sourceCommit"]
            and metadata["source"]["snapshotChecksum"] == expected["sourceSnapshotChecksum"]
            and metadata["artifact"]["fileName"] == expected["archiveName"]
            and metadata["artifact"]["storageKey"] == expected["archiveKey"],
            "Local engine does not match the checked-out Wine source and recipe")


def validate_engine(root, sha, run_id):
    metadata = read_json(root, "engine-metadata.json")
    if metadata["build"].get("producer") != "local-pre-push":
        validate_engine_metadata(root, sha, run_id)
        return
    validate_engine_metadata(root, sha, "local-" + sha)
    receipt = read_json(root, "engine-validation.json")
    check_build(receipt["portsideCommit"], receipt["buildId"], sha, run_id)
    require(receipt["kind"] == "PortsideEngineNativeValidation"
            and receipt["engineVersion"] == metadata["engineVersion"]
            and receipt["archiveSha256"] == metadata["artifact"]["sha256"]
            and receipt["engineMetadataSha256"] == hashlib.sha256((root / "engine-metadata.json").read_bytes()).hexdigest()
            and receipt["engineProvenanceSha256"] == hashlib.sha256((root / "engine-provenance.json").read_bytes()).hexdigest(),
            "Local engine lacks matching native validation from this workflow run")


def validate_runtime(root, sha, run_id):
    manifest = read_json(root, "runtime-manifest-unsigned.json")
    provenance = read_json(root, "provenance.json")
    if manifest.get("integration") == "sikarugir":
        validate_sikarugir_runtime(root, manifest, provenance, sha, run_id)
        return
    require(manifest.get("integration", "directWine") == "directWine", "Unsupported runtime integration")
    engine = read_json(root, "engine-input.json")
    sbom = read_json(root, "sbom.spdx.json")
    patches = engine["source"].get("patches", [])
    require(provenance["engine"].get("patches", []) == patches, "Runtime patch provenance mismatch")
    if patches:
        wine_packages = [item for item in sbom.get("packages", []) if item.get("SPDXID") == "SPDXRef-wine"]
        require(len(wine_packages) == 1 and
                json.loads(wine_packages[0].get("sourceInfo", "{}")).get("portsidePatches") == patches,
                "Runtime SBOM patch inventory mismatch")
    check_build(manifest["portsideCommit"], manifest["buildId"], sha, run_id)
    require(provenance["portsideCommit"] == sha and provenance["sourceCommits"]["portside"] == sha
            and provenance["buildId"] == manifest["buildId"], "Runtime source/build provenance mismatch")
    require(manifest["channel"] == provenance["channel"] == "production", "Unexpected runtime channel")
    version = manifest["manifestVersion"]
    require(version == provenance["version"], "Runtime version provenance mismatch")
    components = manifest["components"]
    names = {"wrapper": "Wrapper", "engine": "WineEngine", "winetricks": "Winetricks"}
    require(len(components) == 3 and {value["component"] for value in components} == names.keys(),
            "Runtime must contain exactly its three components")
    files = []
    for component in components:
        kind = component["component"]
        name = "Portside" + names[kind] + "-" + version + ".tar.xz"
        check_archive(root, name, component)
        files.append(name)
        source = {"wrapper": "portside", "engine": "wine", "winetricks": "winetricks"}[kind]
        require(component["sourceCommit"] == provenance["sourceCommits"][source],
                "Runtime component source provenance mismatch")
        if kind == "engine":
            require(component["version"] == engine["engineVersion"] == provenance["engine"]["version"]
                    and component["sha256"] == provenance["engine"]["runtimeArchiveSha256"]
                    and engine["artifact"]["sha256"] == provenance["engine"]["sourceArchiveSha256"]
                    and engine["build"]["id"] == provenance["engine"]["buildId"]
                    and engine["source"]["commit"] == component["sourceCommit"],
                    "Runtime engine input provenance mismatch")
    require(sorted(files) == sorted(provenance["artifacts"]), "Runtime archive inventory mismatch")


def validate_sikarugir_runtime(root, manifest, provenance, sha, run_id):
    checkout = Path(__file__).resolve().parents[2]
    pins = checkout / "upstream/sikarugir-runtime.json"
    approved = json.loads(pins.read_text())
    pin_sha = hashlib.sha256(pins.read_bytes()).hexdigest()
    check_build(manifest["portsideCommit"], manifest["buildId"], sha, run_id)
    require(provenance.get("kind") == "PortsideSikarugirRuntime" and provenance.get("integration") == "sikarugir"
            and provenance.get("portsideCommit") == sha and provenance.get("sourceCommits") == {"portside": sha}
            and provenance.get("buildId") == manifest["buildId"] and provenance.get("version") == manifest["manifestVersion"]
            and manifest["channel"] == provenance.get("channel") == "production", "Sikarugir runtime source/build mismatch")
    require(provenance.get("approvedInputsSha256") == pin_sha and provenance.get("inputs") == approved["components"],
            "Sikarugir original input provenance mismatch")
    engine = read_json(root, "engine-input.json")
    require(engine.get("kind") == "PortsideApprovedSikarugirEngine" and engine.get("approvedInputsSha256") == pin_sha
            and engine.get("input") == next(value for value in approved["components"] if value["id"] == "engine"),
            "Sikarugir engine input mismatch")
    names = {"wrapper": "Wrapper", "engine": "WineEngine", "winetricks": "Winetricks"}
    components = manifest["components"]
    require(len(components) == 3 and {item["component"] for item in components} == names.keys(), "Invalid Sikarugir component set")
    files = []
    for item in components:
        name = "Portside" + names[item["component"]] + "-" + manifest["manifestVersion"] + ".tar.xz"
        check_archive(root, name, item)
        files.append(name)
        require(item.get("sourceCommit") == sha and item.get("sourceSnapshotChecksum") == pin_sha
                and item.get("builtBy") == "Portside" and item.get("buildOperation") == "assembly"
                and item.get("upstreamProducer") == "Sikarugir", "Sikarugir component producer/source mismatch")
    require(sorted(files) == sorted(provenance["artifacts"]), "Sikarugir archive inventory mismatch")
    sbom = read_json(root, "sbom.spdx.json")
    for item in approved["components"]:
        packages = [p for p in sbom.get("packages", []) if p.get("SPDXID") == "SPDXRef-" + item["id"]]
        require(len(packages) == 1 and packages[0].get("supplier") == "Organization: Sikarugir"
                and packages[0].get("checksums") == [{"algorithm": "SHA256", "checksumValue": item["sha256"]}],
                "Sikarugir SBOM original input mismatch")
    native = read_json(root, "native-validation.json")
    require(native.get("kind") == "PortsideSikarugirInstallationProbe" and native.get("portsideCommit") == sha
            and native.get("buildId") == manifest["buildId"] and native.get("syntheticDataPreserved") is True
            and native.get("startupSkipped") is True and native.get("wrapperMetadataPreserved") is True
            and native.get("windowsX64Exit") == 37 and native.get("windowsX86Exit") == 23
            and native.get("archiveChecksums") == {item["component"]: item["sha256"] for item in components},
            "Sikarugir native installation acceptance is missing")
    require(provenance.get("distributionReady") is True and provenance.get("signatureKind") == "Developer ID entry points"
            and native.get("componentSignaturesVerified") is True
            and set(native.get("nativeComponentChecksums", {})) == {"host", "launcher", "sdk", "wine", "wineserver"}
            and native.get("nativeComponentChecksums") == provenance.get("nativeComponentChecksums") and native.get("distributionSignatureVerified") is True,
            "Sikarugir distribution signing acceptance is pending; local candidates cannot be published")


def main():
    require(len(sys.argv) == 3 and sys.argv[1] in ("engine", "runtime"),
            "Usage: validate-publication.py engine|runtime DIRECTORY")
    checkout = Path(__file__).resolve().parents[2]
    sha = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    validator = validate_engine if sys.argv[1] == "engine" else validate_runtime
    validator(Path(sys.argv[2]), sha, os.environ["GITHUB_RUN_ID"])
    print("Transferred publication archives match source, workflow run, sizes and checksums.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Invalid publication evidence", file=sys.stderr)
        sys.exit(1)
