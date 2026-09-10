#!/usr/bin/env python3
"""Build and run the real desktop installer in a new private disposable home."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sikarugir_candidate", ROOT / "scripts/build-runtime/build-sikarugir-candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archives", type=Path)
    parser.add_argument("--install-steam", action="store_true")
    parser.add_argument("--keep-fixture", action="store_true")
    args = parser.parse_args()
    if not (args.archives / "runtime-manifest-unsigned.json").is_file():
        parser.error("Runtime archives must be fully packaged before native validation")
    subprocess.run(["swift", "build", "--package-path", str(ROOT / "apps/desktop"), "--target", "PortsideCore"], check=True)
    debug = ROOT / "apps/desktop/.build/debug"
    with tempfile.TemporaryDirectory(prefix="portside-installer-probe-tool-") as toolroot:
        executable = Path(toolroot) / "probe"
        subprocess.run(["swiftc", "-parse-as-library", "-I", str(debug / "Modules"),
                        str(ROOT / "scripts/build-runtime/SikarugirInstallationProbe.swift"),
                        *map(str, (debug / "PortsideCore.build").glob("*.o")), "-o", str(executable)], check=True)
        command = [str(executable), str(args.archives.resolve())]
        if args.install_steam: command.append("--install-steam")
        result = subprocess.run(command, capture_output=True, text=True)
        roots = [line.removeprefix("Fixture: ") for line in result.stdout.splitlines() if line.startswith("Fixture: ")]
        if len(roots) != 1:
            raise RuntimeError("Native installer probe did not identify its disposable fixture")
        fixture = Path(roots[0]).resolve()
        if fixture.parent != Path(tempfile.gettempdir()).resolve() or not fixture.name.startswith("portside-sikarugir-install-"):
            raise RuntimeError("Native probe returned an unexpected fixture root")
        home = fixture / "home"
        state = home / "Library/Application Support/Portside"
        wrapper = state / "Wrappers/PortsideBaseline.app"
        prefix = state / "Prefixes/PortsideBaseline"
        try:
            if result.returncode != 0:
                # Keep low-level fixture diagnostics local; report the failed
                # stage without publishing Wine output or a crash backtrace.
                (fixture / "probe-error.log").write_text(result.stderr)
                raise RuntimeError("Native Sikarugir installation probe failed; fixture diagnostics were retained")
            report = json.loads((fixture / "result.json").read_text())
            native_components = {
                "host": wrapper / "Contents/MacOS/PortsideRuntimeHost",
                "launcher": wrapper / "Contents/MacOS/Sikarugir",
                "sdk": wrapper / "Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk",
                "wine": wrapper / "Contents/SharedSupport/wine/bin/wine",
                "wineserver": wrapper / "Contents/SharedSupport/wine/bin/wineserver",
            }
            for component in native_components.values():
                subprocess.run(["codesign", "--verify", "--strict", str(component)], check=True, capture_output=True)
            candidate.verify_launcher_privacy(native_components["launcher"])
            report["launcherResourceRestrictionsVerified"] = True
            report["componentSignaturesVerified"] = True
            developer_id = True
            for name in ["host", "launcher"]:
                requirement = 'anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and identifier "com.portside.runtime.' + name + '"'
                check = subprocess.run(["codesign", "--verify", "--strict", "-R", "=" + requirement, str(native_components[name])], capture_output=True)
                developer_id = developer_id and check.returncode == 0
            report["distributionSignatureVerified"] = developer_id
            import hashlib
            report["nativeComponentChecksums"] = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in native_components.items()}
            (args.archives / "native-validation.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(report), flush=True)
        finally:
            # Exact fixture engine and prefix only; never kill global process names.
            server = wrapper / "Contents/SharedSupport/wine/bin/wineserver"
            if server.is_file():
                environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), WINEPREFIX=str(prefix),
                                   DYLD_FALLBACK_LIBRARY_PATH=str(wrapper / "Contents/Frameworks") + ":/usr/lib")
                for flag in ["-k", "-w"]:
                    stopped = subprocess.run([str(server), flag], env=environment, capture_output=True, timeout=30)
                    if stopped.returncode not in ((0, 1) if flag == "-k" else (0,)):
                        raise RuntimeError("Fixture server shutdown failed; fixture was retained")
            if args.keep_fixture:
                print("Retained synthetic fixture: " + str(fixture))
            elif result.returncode == 0:
                shutil.rmtree(fixture)


if __name__ == "__main__":
    main()
