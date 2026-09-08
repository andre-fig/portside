#!/usr/bin/env python3
"""Exercise the production host bootstrap in a fresh, disposable wrapper/home.

No test-only DLL overrides. --install-steam explicitly enables the official
winetricks Steam download (and its checksum checks); never authenticates Steam.
The default verifies prefix bootstrap and both PE command architectures offline.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import uuid


def validate(wrapper, engine, winetricks, install_steam=False, observe_steam=False):
    with tempfile.TemporaryDirectory(prefix="portside-host-bootstrap-") as temporary:
        root = Path(temporary)
        home = root / "home"
        home.mkdir()
        prefix = root / "prefix"
        prefix.mkdir()
        fixture = root / "PortsideBaseline.app"
        # The source must be an unassembled wrapper; never copy a user's prefix.
        shared = wrapper / "Contents/SharedSupport"
        if any((shared / name).exists() or (shared / name).is_symlink() for name in ("engine", "winetricks")):
            raise RuntimeError("Probe requires an unassembled build wrapper without prefix or engine")
        template_prefix = shared / "prefix"
        if template_prefix.is_symlink() or (template_prefix.exists() and
                (not template_prefix.is_dir() or any(p.name != ".gitkeep" or not p.is_file() or p.is_symlink() or p.stat().st_size != 0 for p in template_prefix.iterdir()))):
            raise RuntimeError("Probe refuses an existing prefix")
        shutil.copytree(wrapper, fixture, symlinks=True)
        shared = fixture / "Contents/SharedSupport"
        shared.mkdir(exist_ok=True)
        if (shared / "prefix").exists():
            shutil.rmtree(shared / "prefix")  # Only the copied, checked empty template.
        for name, target in [("prefix", prefix), ("engine", engine), ("winetricks", winetricks)]:
            (shared / name).symlink_to(target, target_is_directory=True)
        host = fixture / "Contents/MacOS/PortsideRuntimeHost"
        environment = {"HOME": str(home), "CFFIXED_USER_HOME": str(home), "PATH": str(engine / "bin") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"}
        server_environment = dict(environment, WINEPREFIX=str(prefix))
        log_directory = home / "Library/Application Support/Portside/Logs"
        checks = [("prefix-bootstrap", ["--create-prefix"], 0, 90),
                  ("synthetic-autostart-registration", ["--program", "reg", "add", r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "/v", "PortsideSyntheticProbe", "/t", "REG_SZ", "/d", r"cmd /c echo unexpected > C:\portside-autostart.txt", "/f"], 0, 30),
                  ("existing-prefix-upgrade", ["--create-prefix"], 0, 90),
                  ("synthetic-autostart-removal", ["--program", "reg", "delete", r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "/v", "PortsideSyntheticProbe", "/f"], 0, 30),
                  ("cef-loader-policy", ["--program", "reg", "query", r"HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides", "/v", "vulkan-1"], 0, 30),
                  ("windows-x64", ["--program", "cmd", "/c", "exit", "37"], 37, 30),
                  ("windows-x86", ["--program", r"C:\windows\syswow64\cmd.exe", "/c", "exit", "23"], 23, 30)]
        if install_steam:
            checks.append(("official-steam-install", ["--winetricks", "-q", "steam"], 0, 600))
        hosts = []
        try:
            for label, arguments, expected, timeout in checks:
                launch_id = str(uuid.uuid4()).upper()
                started = time.monotonic()
                process = subprocess.Popen([str(host), "--launch-id", launch_id, *arguments], env=environment,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                hosts.append(process)
                try:
                    status = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    raise RuntimeError(label + " timed out") from None
                receipt = json.loads((log_directory / "RuntimeLaunches" / (launch_id + ".json")).read_text())
                print(json.dumps({"probe": label, "status": status, "terminationReason": receipt.get("terminationReason"),
                                  "duration": round(time.monotonic() - started, 3)}), flush=True)
                if status != expected:
                    raise RuntimeError(label + " failed")
                if label == "prefix-bootstrap":
                    for directory in ("system32", "syswow64"):
                        if not (prefix / "drive_c/windows" / directory / "kernel32.dll").is_file():
                            raise RuntimeError("Bootstrap did not complete both Windows architectures")
                    (prefix / "synthetic-preservation-marker").write_text("preserve synthetic data\n")
                if label == "existing-prefix-upgrade":
                    if (prefix / "drive_c/portside-autostart.txt").exists():
                        raise RuntimeError("Prefix upgrade unexpectedly ran a startup program")
                    if (prefix / "synthetic-preservation-marker").read_text() != "preserve synthetic data\n":
                        raise RuntimeError("Existing-prefix preparation changed the preservation marker")
                    print("Existing-prefix upgrade preserved synthetic data; no everyday prefix was used.", flush=True)
            if install_steam:
                if not (prefix / "drive_c/Program Files (x86)/Steam/steam.exe").is_file():
                    raise RuntimeError("Valve installer did not produce steam.exe")
                print("Official Steam installation verified; graphical launch is a separate acceptance test.", flush=True)
            if observe_steam:
                # An operator may inspect only this fixture's windows during the
                # observation interval. This is not an automated GUI success gate.
                process = subprocess.Popen([str(host)], env=environment, stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL, start_new_session=True)
                hosts.append(process)
                print(json.dumps({"probe": "steam-observation-started", "hostPID": process.pid, "seconds": 120}), flush=True)
                time.sleep(120)
                print(json.dumps({"probe": "steam-observation-ended", "hostStatus": process.poll(), "graphicalAcceptance": "unverified"}), flush=True)
        finally:
            # Only the server associated with this newly-created disposable prefix.
            subprocess.run([str(engine / "bin/wineserver"), "-k"], env=server_environment,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            subprocess.run([str(engine / "bin/wineserver"), "-w"], env=server_environment,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            for host_process in hosts:
                try:
                    host_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    host_process.terminate()
                    host_process.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wrapper", type=Path)
    parser.add_argument("engine", type=Path)
    parser.add_argument("winetricks", type=Path)
    parser.add_argument("--install-steam", action="store_true")
    parser.add_argument("--observe-steam", action="store_true", help="launch without Steam flags for 120 seconds after installation; manual GUI observation only")
    args = parser.parse_args()
    if args.observe_steam and not args.install_steam:
        parser.error("--observe-steam requires --install-steam")
    try:
        validate(args.wrapper.resolve(strict=True), args.engine.resolve(strict=True), args.winetricks.resolve(strict=True), args.install_steam, args.observe_steam)
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, RuntimeError) else type(error).__name__)
        raise SystemExit(1)
