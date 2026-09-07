#!/usr/bin/env python3
"""Transfer unpublished local engine inputs; CI alone publishes validated engines."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("publication", Path(__file__).with_name("validate-publication.py"))
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


def engine_info():
    return json.loads(subprocess.check_output([str(ROOT / "scripts/build-runtime/resolve-engine.sh")], text=True))


def railway_storage():
    """Read only the linked repository's production API storage configuration."""
    def read(arguments, cwd=ROOT):
        result = subprocess.run(arguments, cwd=cwd, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError("Cannot read the configured Railway storage provider; push blocked")
        return result.stdout

    origin = read(["git", "remote", "get-url", "origin"]).strip()
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?", origin)
    if not match:
        raise RuntimeError("Railway storage requires an identifiable GitHub origin")
    project = json.loads(read(["railway", "status", "--json"], ROOT / "apps/backend"))
    candidates = []
    for edge in project["environments"]["edges"]:
        environment = edge["node"]
        if environment["name"] != "production" or not environment["canAccess"]:
            continue
        for service_edge in environment["serviceInstances"]["edges"]:
            service = service_edge["node"]
            if service["serviceName"] == "api" and (service.get("source") or {}).get("repo") == match[1]:
                candidates.append((environment["id"], service["serviceId"]))
    if len(candidates) != 1:
        raise RuntimeError("Railway storage must match exactly one production API for this repository")
    environment_id, service_id = candidates[0]
    values = json.loads(read(["railway", "variable", "list", "--project", project["id"],
                             "--environment", environment_id, "--service", service_id, "--json"], ROOT / "apps/backend"))
    mapping = {"PORTSIDE_PUBLIC_BUCKET": "S3_BUCKET", "PORTSIDE_S3_ACCESS_KEY_ID": "S3_ACCESS_KEY_ID",
               "PORTSIDE_S3_SECRET_ACCESS_KEY": "S3_SECRET_ACCESS_KEY", "PORTSIDE_S3_REGION": "S3_REGION",
               "PORTSIDE_S3_ENDPOINT": "S3_ENDPOINT"}
    if any(not isinstance(values.get(key), str) or not values[key] for key in mapping.values()):
        raise RuntimeError("Railway production API storage configuration is incomplete")
    return {destination: values[source] for destination, source in mapping.items()}


def storage_environment():
    required = ("PORTSIDE_PUBLIC_BUCKET", "PORTSIDE_S3_ACCESS_KEY_ID", "PORTSIDE_S3_SECRET_ACCESS_KEY",
                "PORTSIDE_S3_REGION", "PORTSIDE_S3_ENDPOINT")
    environment = dict(os.environ)
    missing = [name for name in required if not environment.get(name)]
    if len(missing) == len(required) and sys.platform == "darwin":
        provider = subprocess.run(["git", "-C", str(ROOT), "config", "--get", "portside.engineStorageProvider"],
                                  capture_output=True, text=True, timeout=5)
        if provider.returncode == 0 and provider.stdout.strip() == "railway":
            environment.update(railway_storage())
            missing = []
    if missing:
        raise RuntimeError("Local engine transfer configuration is missing: " + ", ".join(missing))
    if not shutil.which("aws"):
        raise RuntimeError("AWS CLI is required for local engine transfer; install awscli before pushing")
    for name in ("AWS_PROFILE", "AWS_SESSION_TOKEN", "AWS_SECURITY_TOKEN"):
        environment.pop(name, None)
    for destination, source in {
        "AWS_ACCESS_KEY_ID": "PORTSIDE_S3_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY": "PORTSIDE_S3_SECRET_ACCESS_KEY",
        "AWS_REGION": "PORTSIDE_S3_REGION", "AWS_DEFAULT_REGION": "PORTSIDE_S3_REGION", "AWS_ENDPOINT_URL": "PORTSIDE_S3_ENDPOINT",
    }.items():
        environment[destination] = environment[source]
    return environment


def transfer(operation, directory, sha, expected):
    environment = storage_environment()
    bucket = environment["PORTSIDE_PUBLIC_BUCKET"]
    prefix = f"runtime/build-inputs/engines/{sha}/{expected['engineVersion']}"
    # Metadata is written last. This namespace is never a client download route
    # or a validated engine key; upload is not production publication.
    names = [expected["archiveName"], "engine-provenance.json", "engine-metadata.json"]
    if operation == "upload":
        publication.validate_local_engine(directory, sha, expected)
    directory.mkdir(parents=True, exist_ok=True)
    for name in names:
        local = str(directory / name)
        if (directory / name).is_symlink():
            raise RuntimeError("Engine input transfer cannot overwrite or upload a symlink")
        remote = f"s3://{bucket}/{prefix}/{name}"
        arguments = [local, remote] if operation == "upload" else [remote, local]
        result = subprocess.run(["aws", "s3", "cp", *arguments, "--only-show-errors"], env=environment,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
        if result.returncode:
            raise RuntimeError("Unpublished engine input transfer failed; no runner will wait or compile a replacement")
    if operation == "download":
        publication.validate_local_engine(directory, sha, expected)
    metadata = publication.read_json(directory, "engine-metadata.json")
    # The publisher expects the short checksum filename. Generate it from the
    # verified archive metadata instead of transferring a machine-specific path.
    (directory / ("PortsideWineEngine-" + expected["engineVersion"] + ".sha256")).write_text(
        metadata["artifact"]["sha256"] + "  " + expected["archiveName"] + "\n")


def extract_engine(archive, destination, root_name):
    if not hasattr(tarfile, "data_filter"):
        raise RuntimeError("Python with tarfile.data_filter is required for safe engine extraction (use Python 3.12+)")
    with tarfile.open(archive, "r:xz") as handle:
        def filtered(member, target):
            if member.name.split("/")[0] != root_name:
                raise RuntimeError("Unexpected engine archive root")
            return tarfile.data_filter(member, target)
        handle.extractall(destination, filter=filtered)


def validate_native(directory, sha, expected):
    publication.validate_local_engine(directory, sha, expected)
    if sys.platform != "darwin":
        raise RuntimeError("Native engine execution requires macOS")
    with tempfile.TemporaryDirectory(prefix="portside-local-engine-check-") as temporary:
        destination = Path(temporary)
        root_name = "PortsideWineEngine-" + expected["engineVersion"]
        extract_engine(directory / expected["archiveName"], destination, root_name)
        engine = destination / root_name
        subprocess.run([sys.executable, str(ROOT / "scripts/build-runtime/validate-engine-privacy.py"), str(engine)], check=True)
        (engine / "share").mkdir()
        (engine / "share-wine").rename(engine / "share/wine")
        subprocess.run([sys.executable, str(ROOT / "scripts/build-runtime/validate-engine-execution.py"), str(engine)], check=True)
    metadata = publication.read_json(directory, "engine-metadata.json")
    receipt = {
        "kind": "PortsideEngineNativeValidation", "portsideCommit": sha,
        "buildId": os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"],
        "engineVersion": expected["engineVersion"], "archiveSha256": metadata["artifact"]["sha256"],
        "engineMetadataSha256": hashlib.sha256((directory / "engine-metadata.json").read_bytes()).hexdigest(),
        "engineProvenanceSha256": hashlib.sha256((directory / "engine-provenance.json").read_bytes()).hexdigest(),
    }
    (directory / "engine-validation.json").write_text(json.dumps(receipt, indent=2) + "\n")


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("upload", "download", "validate-native"):
        raise RuntimeError("Usage: engine-input.py upload|download|validate-native DIRECTORY SOURCE_SHA")
    operation, directory, sha = sys.argv[1:]
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise RuntimeError("Invalid local engine source revision")
    expected = engine_info()
    if operation == "validate-native":
        validate_native(Path(directory), sha, expected)
    else:
        transfer(operation, Path(directory), sha, expected)
    print("Local engine input " + operation + " completed.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError, OSError, tarfile.TarError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Local engine input operation failed", file=sys.stderr)
        sys.exit(1)
