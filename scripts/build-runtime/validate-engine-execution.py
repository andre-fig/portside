#!/usr/bin/env python3
"""Exercise the real loader and both PE architectures in a disposable prefix.

No Steam, network installation, existing prefix, or global process termination.
Version output alone does not execute Wine's nested Darwin loader.
"""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time


def check_steam_command_policy(engine):
    """Reject the observed legacy kernelbase sandbox-disabling workaround.

    This narrow binary guard runs before executing the engine, including on
    cached installs and extracted CI inputs. It is not proof of browser sandbox
    implementation or a substitute for the CreateProcess/graphical controls.
    """
    for architecture in ("i386", "x86_64"):
        binary = engine / "lib/wine" / (architecture + "-windows") / "kernelbase.dll"
        if not binary.is_file() or not binary.resolve().is_relative_to(engine.resolve()):
            raise RuntimeError("Engine lacks a contained kernelbase for both Windows architectures")
        data = binary.read_bytes()
        for encoding in ("ascii", "utf-16le"):
            if "--no-sandbox".encode(encoding) in data:
                raise RuntimeError("Engine kernelbase contains a sandbox-disabling command workaround (" + architecture + ")")
    print(json.dumps({"probe": "steam-command-policy", "knownSandboxDisablingWorkaround": False}), flush=True)


def check_deployment(output):
    versions = re.findall(r"\bminos\s+(\d+(?:\.\d+){0,2})", output)
    versions += re.findall(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize\s+\d+\s+version\s+(\d+(?:\.\d+){0,2})", output)
    if not versions or any(tuple(map(int, value.split("."))) + (0,) * (3 - len(value.split("."))) > (13, 0, 0) for value in versions):
        raise RuntimeError("Engine Mach-O requires a newer macOS than the supported 13.0 floor or lacks deployment metadata")


def check_platform(engine):
    magics = {bytes.fromhex(value) for value in ("feedface", "feedfacf", "cefaedfe", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
    inspected = 0
    for binary in engine.rglob("*"):
        if binary.is_symlink() or not binary.is_file():
            continue
        with binary.open("rb") as handle:
            if handle.read(4) not in magics:
                continue
        architecture = subprocess.run(["/usr/bin/lipo", "-archs", str(binary)], capture_output=True, text=True)
        if architecture.returncode or architecture.stdout.strip() != "x86_64":
            raise RuntimeError("Every engine Mach-O must target x86_64, including nested libraries")
        deployment = subprocess.run(["xcrun", "vtool", "-show-build", str(binary)], capture_output=True, text=True)
        if deployment.returncode:
            raise RuntimeError("Cannot inspect engine Mach-O deployment metadata")
        check_deployment(deployment.stdout)
        inspected += 1
    if not inspected:
        raise RuntimeError("Engine contains no Mach-O binaries")
    print(json.dumps({"probe": "macho-platform", "files": inspected, "architecture": "x86_64", "maximumMinimumMacOS": "13.0"}), flush=True)


def validate(engine):
    check_steam_command_policy(engine)
    wine = engine / "bin/wine"
    loader = engine / "lib/wine/x86_64-unix/wine"
    for binary in (wine, loader, engine / "lib/wine/x86_64-unix/ntdll.so"):
        result = subprocess.run(["/usr/bin/lipo", "-archs", str(binary)], capture_output=True, text=True)
        if result.returncode or result.stdout.strip() != "x86_64":
            raise RuntimeError("Steam requires an x86_64 Darwin engine, including its nested loader and ntdll")
    check_platform(engine)
    with tempfile.TemporaryDirectory(prefix="portside-engine-probe-") as temporary:
        root = Path(temporary)
        (root / "home").mkdir()
        (root / "prefix").mkdir()
        (root / "prefix-link").symlink_to(root / "prefix", target_is_directory=True)
        environment = {
            "PATH": str(engine / "bin") + ":/usr/bin:/bin", "HOME": str(root / "home"),
            "CFFIXED_USER_HOME": str(root / "home"), "WINEPREFIX": str(root / "prefix-link"),
            "WINEARCH": "win64", "WINEDEBUG": "-all", "WINEMSYNC": "1", "WINEESYNC": "1",
            "WINE": str(wine), "WINELOADER": str(wine), "WINESERVER": str(engine / "bin/wineserver"),
            # No optional installer dialogs or desktop integration during this probe.
            "WINEDLLOVERRIDES": "winemenubuilder.exe,mscoree,mshtml=",
        }
        try:
            for label, arguments, expected in [
                ("version", ["--version"], 0),
                ("windows-x64", ["cmd", "/c", "exit", "37"], 37),
                ("windows-x86", [r"C:\windows\syswow64\cmd.exe", "/c", "exit", "23"], 23),
            ]:
                started = time.monotonic()
                process = subprocess.Popen([str(wine), *arguments], env=environment,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                           start_new_session=True)
                try:
                    status = process.wait(timeout=60)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)  # Only this disposable probe's group.
                    process.wait()
                    raise RuntimeError(label + " timed out") from None
                print(json.dumps({"probe": label, "terminationStatus": abs(status),
                                  "terminationReason": "uncaughtSignal" if status < 0 else "exit",
                                  "duration": round(time.monotonic() - started, 3)}), flush=True)
                if status != expected:
                    raise RuntimeError(label + " failed; the engine is not ready to package")
        finally:
            # The Wine server may detach from the loader. Its explicit disposable
            # WINEPREFIX is the ownership boundary; never use a process-name kill.
            subprocess.run([str(engine / "bin/wineserver"), "-k"], env=environment,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            subprocess.run([str(engine / "bin/wineserver"), "-w"], env=environment,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise RuntimeError("usage: validate-engine-execution.py ENGINE_ROOT")
        validate(Path(sys.argv[1]).resolve(strict=True))
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        # Do not print third-party output, environment, or exception paths.
        print(str(error) if isinstance(error, RuntimeError) else type(error).__name__, file=sys.stderr)
        sys.exit(1)
