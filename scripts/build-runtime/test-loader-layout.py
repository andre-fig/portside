#!/usr/bin/env python3
"""Isolate the Darwin loader layout from Wine, Steam, prefixes and signatures.

Optionally set PORTSIDE_CODESIGN_IDENTITY for a second Developer ID comparison.
Only newly compiled disposable binaries are signed; no security policy is changed.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def run():
    identity = os.environ.get("PORTSIDE_CODESIGN_IDENTITY")
    if identity == "-":
        raise RuntimeError("Developer ID comparison requires a Developer ID identity")
    with tempfile.TemporaryDirectory(prefix="portside-loader-layout-") as temporary:
        root = Path(temporary)
        source = root / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        for architecture in ("arm64", "x86_64"):
            for layout, flags in [
                ("default", []),
                ("wine", ["-Wl,-pagezero_size,0x1000,-segalign,0x1000"]),
            ]:
                binary = root / (architecture + "-" + layout)
                subprocess.run(["clang", "-arch", architecture, str(source), *flags, "-o", str(binary)],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                # Explicitly sign both variants so static validation is a control.
                for signing in (["adhoc", "developer-id"] if identity else ["adhoc"]):
                    options = ["--options", "runtime", "--timestamp"] if signing == "developer-id" else []
                    subprocess.run(["codesign", "--force", "--sign", identity if signing == "developer-id" else "-",
                                    *options, str(binary)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    verify = subprocess.run(["codesign", "--verify", "--strict", str(binary)],
                                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
                    status = subprocess.run([str(binary)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
                    print(json.dumps({"architecture": architecture, "layout": layout, "signing": signing,
                                      "staticVerification": verify, "terminationStatus": abs(status),
                                      "terminationReason": "uncaughtSignal" if status < 0 else "exit"}), flush=True)
                    if verify or (architecture == "x86_64" or layout == "default") and status:
                        raise RuntimeError("a loader control failed")


if __name__ == "__main__":
    try:
        run()
    except (OSError, subprocess.CalledProcessError, RuntimeError):
        raise SystemExit("Loader comparison failed; no installed runtime was modified.")
