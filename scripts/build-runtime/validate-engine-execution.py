#!/usr/bin/env python3
"""Exercise the real loader and both PE architectures in a disposable prefix.

No Steam, network installation, existing prefix, or global process termination.
Version output alone does not execute Wine's nested Darwin loader.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def validate(engine):
    wine = engine / "bin/wine"
    loader = engine / "lib/wine/x86_64-unix/wine"
    for binary in (wine, loader, engine / "lib/wine/x86_64-unix/ntdll.so"):
        result = subprocess.run(["/usr/bin/lipo", "-archs", str(binary)], capture_output=True, text=True)
        if result.returncode or result.stdout.strip() != "x86_64":
            raise RuntimeError("Steam requires an x86_64 Darwin engine, including its nested loader and ntdll")
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
