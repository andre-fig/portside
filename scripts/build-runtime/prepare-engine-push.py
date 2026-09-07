#!/usr/bin/env python3
"""Build the outgoing committed engine locally, before pushing main.

Uncommitted work and everyday Portside state are never build inputs. A clean
Git export and the existing source/toolchain-qualified Wine cache are used.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("engine_input", Path(__file__).with_name("engine-input.py"))
engine_input = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine_input)


def build_engine(source, output, environment):
    log = output / "build.log"
    if log.is_symlink():
        raise RuntimeError("Local engine build log must not replace a symlink")
    print("Local compiler output: " + str(log.relative_to(ROOT)), flush=True)
    substitutions = ((str(source), "$SOURCE"), (str(ROOT), "$CHECKOUT"), (str(Path.home()), "$HOME"))
    with log.open("w") as handle:
        with subprocess.Popen([str(source / "scripts/build-runtime/build-engine.sh")], env=environment,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace") as process:
            for line in process.stdout:
                for path, replacement in substitutions:
                    line = line.replace(path, replacement)
                handle.write(line)
                if line.startswith(("Built ", "Reusing ", "Engine personal-path audit", '{"probe":')):
                    print(line.rstrip(), flush=True)
            if process.wait():
                raise RuntimeError("Local engine compilation failed; review the sanitized build.log. Push blocked.")


def prepare(base, sha, upload=True):
    if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (base, sha)):
        raise RuntimeError("Invalid outgoing engine revision")
    changed = subprocess.run([str(ROOT / "scripts/build-runtime/changed-components.sh"), "engine", base, sha], cwd=ROOT)
    if changed.returncode == 1:
        return False
    if changed.returncode:
        raise RuntimeError("Cannot determine outgoing engine inputs")
    if sys.platform != "darwin":
        raise RuntimeError("Engine-changing pushes require a local macOS source build")
    # Fail before expensive work if the final handoff cannot be completed.
    if upload:
        engine_input.storage_environment()
    output = ROOT / "build/local-engine-inputs" / sha
    export_parent = ROOT / "build/local-engine-sources"
    cache = ROOT / ".cache/portside-wine"
    for path in (output, export_parent, cache):
        if path.resolve() != path or not path.is_relative_to(ROOT):
            raise RuntimeError("Local engine build/cache path must stay in its owned checkout directory")
    output.mkdir(parents=True, exist_ok=True)
    export_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="source-", dir=export_parent) as temporary:
        source = Path(temporary)
        # Git produces this archive from the exact outgoing commit. No worktree
        # file is copied, and no generated binary is added to Git.
        archive = subprocess.Popen(["git", "-C", str(ROOT), "archive", sha], stdout=subprocess.PIPE)
        extraction = subprocess.run(["tar", "-xf", "-", "-C", str(source)], stdin=archive.stdout)
        archive.stdout.close()
        if archive.wait() or extraction.returncode:
            raise RuntimeError("Cannot export the outgoing engine source")
        expected = json.loads(subprocess.check_output([str(source / "scripts/build-runtime/resolve-engine.sh")], text=True))
        try:
            engine_input.publication.validate_local_engine(output, sha, expected)
            print("Reusing the completed local engine input for this outgoing commit.", flush=True)
        except (RuntimeError, KeyError, ValueError, OSError):
            print("Preparing the engine locally before push; compatible Wine compilation cache will be reused.", flush=True)
            # Compilation needs no publication credentials or production keys.
            build_variables = {"PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "TMP", "TEMP", "LANG",
                               "SDKROOT", "DEVELOPER_DIR", "MACOSX_DEPLOYMENT_TARGET", "CC", "CXX", "CFLAGS",
                               "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "CROSSCFLAGS", "PORTSIDE_BUILD_JOBS"}
            environment = {key: value for key, value in os.environ.items()
                           if key in build_variables or key.startswith(("LC_", "PORTSIDE_WINE_"))}
            environment.update(PORTSIDE_COMMIT=sha, GITHUB_RUN_ID="local-" + sha, GITHUB_RUN_ATTEMPT="1",
                               PORTSIDE_ENGINE_PRODUCER="local-pre-push", PORTSIDE_ENGINE_BUILD_DIR=str(source / "build/engine"),
                               PORTSIDE_WINE_CACHE_DIR=str(cache))
            build_engine(source, output, environment)
            built = source / "build/engine"
            engine_input.publication.validate_local_engine(built, sha, expected)
            for name in (expected["archiveName"], "engine-metadata.json", "engine-provenance.json"):
                if (output / name).is_symlink():
                    raise RuntimeError("Local engine output must not replace a symlink")
                (built / name).replace(output / name)
        if upload:
            engine_input.transfer("upload", output, sha, expected)
    print("Local engine input is ready" + (" and uploaded for CI." if upload else "; no external upload was performed."), flush=True)
    return True


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        build_only = arguments[:1] == ["--build-only"]
        if build_only:
            arguments = arguments[1:]
        if len(arguments) != 2:
            raise RuntimeError("Usage: prepare-engine-push.py [--build-only] BASE_SHA OUTGOING_SHA")
        prepare(*arguments, upload=not build_only)
    except (RuntimeError, KeyError, ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Local engine preparation failed; push blocked", file=sys.stderr)
        sys.exit(1)
