#!/usr/bin/env python3
"""Build the approved Sikarugir composition as Portside's three install archives.

Uses only checksum-pinned local inputs. No Wine compilation or publication.
Developer ID signing requests an Apple timestamp. Distribution remains gated by native acceptance.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sikarugir_candidate", ROOT / "scripts/build-runtime/build-sikarugir-candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)
PREFIX_LINK = "../../../../Prefixes/PortsideBaseline"


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def package(inputs, output, version, download_prefix, commit, build_id, checkout=ROOT, signing_identity="-"):
    checkout = checkout.resolve()
    output = output.resolve()
    if not output.is_relative_to(checkout / "build") or output == checkout / "build" or output.exists():
        raise RuntimeError("Runtime output must be a new directory below checkout/build")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", version) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError("Invalid runtime version or source revision")
    if not re.fullmatch(r"(?:local|[0-9]+)-[0-9]+", build_id):
        raise RuntimeError("Invalid runtime build identity")
    if not re.fullmatch(r"https://[^/?#@]+/v1/runtime/artifacts/production/", download_prefix):
        raise RuntimeError("Runtime URLs must use the Portside production artifact route")
    pin_path = checkout / "upstream/sikarugir-runtime.json"
    approved = json.loads(pin_path.read_text())
    candidate.verify_inputs(inputs, approved)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".sikarugir-package-", dir=output.parent) as temporary:
        work = Path(temporary)
        host = work / "PortsideRuntimeHost"
        # Only Portside's small native helper is compiled. The original engine,
        # launcher and SDK come from the explicitly approved archive set.
        subprocess.run(["swiftc", "-O", "-parse-as-library", "-whole-module-optimization",
                        str(checkout / "apps/runtime-host/Sources/PortsideRuntimeHost/main.swift"), "-o", str(host)], check=True)
        wrapper = candidate.assemble(inputs, work / "candidate", host, version, approved, checkout)
        provenance = json.loads((wrapper.parent / "provenance.json").read_text())
        shared = wrapper / "Contents/SharedSupport"
        link = shared / "prefix"
        if link.exists() or link.is_symlink():
            raise RuntimeError("Approved template unexpectedly contains a prefix")
        link.symlink_to(PREFIX_LINK)
        # The external user prefix makes the configured wrapper mutable. Keep
        # its archive authenticated by the manifest and sign immutable native
        # entry points individually; do not pretend it has a whole-bundle seal.
        native_components = {
            "host": wrapper / "Contents/MacOS/PortsideRuntimeHost",
            "launcher": wrapper / "Contents/MacOS/Sikarugir",
            "sdk": wrapper / "Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk",
            "wine": shared / "wine/bin/wine",
            "wineserver": shared / "wine/bin/wineserver",
        }
        developer_id = signing_identity != "-"
        try:
            for name in ["host", "launcher"]:
                command = ["codesign", "--force", "--sign", signing_identity,
                           "--identifier", "com.portside.runtime." + name]
                if name == "launcher":
                    command += ["--options", "runtime", "--entitlements",
                                str(checkout / "scripts/build-runtime/sikarugir-launcher.entitlements")]
                if signing_identity != "-": command.append("--timestamp")
                subprocess.run(command + [str(native_components[name])], check=True, capture_output=True)
            for component in native_components.values():
                subprocess.run(["codesign", "--verify", "--strict", str(component)], check=True, capture_output=True)
            candidate.verify_launcher_privacy(native_components["launcher"])
            for name in ["host", "launcher"]:
                requirement = 'anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and identifier "com.portside.runtime.' + name + '"'
                result = subprocess.run(["codesign", "--verify", "--strict", "-R", "=" + requirement, str(native_components[name])], capture_output=True)
                developer_id = developer_id and result.returncode == 0
        except subprocess.CalledProcessError as error:
            details = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
            raise RuntimeError("Sikarugir component signature validation failed: " + details.replace(str(work), "$BUILD").replace(str(checkout), "$SOURCE")) from None
        provenance["distributionReady"] = developer_id
        provenance["signatureKind"] = "Developer ID entry points" if developer_id else "local-ad-hoc"
        provenance["wrapperResourceSeal"] = "Not applicable: the configured wrapper references an external mutable user prefix"
        provenance["compiledHostSha256"] = provenance["hostSha256"]
        provenance["hostSha256"] = candidate.sha256(native_components["host"])
        provenance["signedLauncherSha256"] = candidate.sha256(native_components["launcher"])
        provenance["nativeComponentChecksums"] = {name: candidate.sha256(path) for name, path in native_components.items()}
        staged = work / "archives"
        staged.mkdir()
        engine_name = "PortsideWineEngine-" + version
        script_name = "PortsideWinetricks-" + version
        (shared / "wine").rename(staged / engine_name)
        (staged / script_name / "src").mkdir(parents=True)
        (shared / "winetricks").rename(staged / script_name / "src/winetricks")
        wrapper.rename(staged / "PortsideBaseline.app")
        result = work / "result"
        result.mkdir()
        names = {"wrapper": ("PortsideWrapper-" + version, "PortsideBaseline.app"),
                 "engine": (engine_name, engine_name), "winetricks": (script_name, script_name)}
        components = []
        pin_hash = candidate.sha256(pin_path)
        for kind, (name, item) in names.items():
            filename = name + ".tar.xz"
            archive = result / filename
            if kind == "engine":
                # The engine is unchanged. Retain the authenticated original
                # archive bytes instead of recompressing hundreds of megabytes.
                original = next(value for value in approved["components"] if value["id"] == "engine")
                shutil.copyfile(inputs / original["fileName"], archive)
            else:
                subprocess.run([str(checkout / "scripts/build-runtime/create-archive.sh"), str(archive), str(staged), item], check=True)
            digest = candidate.sha256(archive)
            (result / (name + ".sha256")).write_text(digest + "  " + filename + "\n")
            components.append({"id": kind, "component": kind, "version": approved["engineVersion"] if kind == "engine" else version,
                               "downloadURL": download_prefix + filename, "sha256": digest, "size": archive.stat().st_size,
                               "critical": True, "rollbackVersion": None, "builtBy": "Portside",
                               "sourcePath": "upstream/sikarugir-runtime.json" + (" + apps/runtime-host" if kind == "wrapper" else ""),
                               "sourceCommit": commit, "sourceSnapshotChecksum": pin_hash,
                               "upstreamProducer": "Sikarugir", "buildOperation": "assembly",
                               "license": "Preserved Sikarugir component notices; see runtime SBOM"})
        provenance.update(kind="PortsideSikarugirRuntime", integration="sikarugir", portsideCommit=commit,
                          sourceCommits={"portside": commit}, buildId=build_id, channel="production", version=version,
                          approvedInputsSha256=pin_hash, prefixLink=PREFIX_LINK,
                          artifacts=[pair[0] + ".tar.xz" for pair in names.values()],
                          sourcePolicy="Portside assembly of approved original Sikarugir binaries and source-built maintenance helper; upstream binary source builds are not claimed")
        write(result / "provenance.json", provenance)
        write(result / "engine-input.json", {"kind": "PortsideApprovedSikarugirEngine", "engineVersion": approved["engineVersion"],
                                            "input": next(item for item in approved["components"] if item["id"] == "engine"),
                                            "approvedInputsSha256": pin_hash})
        write(result / "runtime-manifest-unsigned.json", {
            "schemaVersion": 2, "integration": "sikarugir", "channel": "production", "manifestVersion": version,
            "minimumPortsideVersion": version, "publishedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "buildStatus": "production", "builtBy": "Portside", "buildId": build_id, "portsideCommit": commit,
            "components": components, "rendererDefaults": {"renderer": "wineD3D", "D3DMETAL": 0, "DXMT": 0, "DXVK": 0, "WINEMSYNC": 1, "WINEESYNC": 1},
            "compatibilityRules": [], "critical": True, "rollbackVersion": None, "signatureKeyId": "", "signature": None})
        packages = [{"SPDXID": "SPDXRef-" + item["id"], "name": "Sikarugir " + item["id"],
                     "downloadLocation": item["url"], "supplier": "Organization: Sikarugir", "licenseConcluded": "NOASSERTION",
                     "checksums": [{"algorithm": "SHA256", "checksumValue": item["sha256"]}],
                     "sourceInfo": "Original approved input; binary source compilation is not claimed"} for item in approved["components"]]
        packages.append({"SPDXID": "SPDXRef-portside-host", "name": "PortsideRuntimeHost", "supplier": "Organization: Portside",
                         "downloadLocation": "NOASSERTION", "licenseConcluded": "NOASSERTION",
                         "checksums": [{"algorithm": "SHA256", "checksumValue": provenance["hostSha256"]}], "sourceInfo": commit})
        write(result / "sbom.spdx.json", {"spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
                                         "name": "Portside Sikarugir runtime " + version,
                                         "documentNamespace": "https://portside.app/sbom/" + commit + "/" + build_id,
                                         "packages": packages})
        result.rename(output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--download-prefix", required=True)
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    build_id = os.environ.get("GITHUB_RUN_ID", "local") + "-" + os.environ.get("GITHUB_RUN_ATTEMPT", "0")
    package(args.inputs, args.output, args.version, args.download_prefix, commit, build_id, signing_identity=os.environ.get("PORTSIDE_CODESIGN_IDENTITY", "-"))
    print("Packaged original Sikarugir components for the Portside installer; distribution acceptance remains pending.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Sikarugir runtime packaging failed", file=sys.stderr)
        sys.exit(1)
