#!/usr/bin/env python3
"""Wait for successful runtime assembly of the tested revision; never reuse latest.

Read-only GitHub operations. workflow_run's head_sha can describe the default
branch rather than its explicitly checked-out engine revision, so the runtime's
run-name also carries that revision. Downloaded provenance is checked separately.
"""
import json
import os
import re
import subprocess
import sys
import time


def select_runtime(runs, target_sha, api):
    pending = False
    failures = []
    for run in sorted(runs, key=lambda value: value["id"], reverse=True):
        if run["head_branch"] != "main" or run.get("event") not in ("push", "workflow_dispatch", "workflow_run"):
            continue
        title = run.get("display_title", "")
        if title.startswith("Runtime production "):
            if title != "Runtime production " + target_sha:
                continue
        elif run["head_sha"] != target_sha:
            continue
        if run["status"] != "completed":
            pending = True
            continue
        jobs = api(f"actions/runs/{run['id']}/jobs?filter=latest&per_page=100")["jobs"]
        assembly = [job for job in jobs if job["name"] == "Build and publish production runtime"]
        if run["conclusion"] != "success":
            failures.append(run["id"])
            continue
        if len(assembly) != 1 or assembly[0]["conclusion"] == "skipped":
            # An engine-changing push intentionally defers assembly to workflow_run.
            continue
        if assembly[0]["conclusion"] != "success":
            failures.append(run["id"])
            continue
        artifacts = api(f"actions/runs/{run['id']}/artifacts?per_page=100")["artifacts"]
        for prefix, kind in [("portside-runtime-metadata-production-", "metadata"), ("portside-runtime-production-", "full")]:
            matches = [a for a in artifacts if not a["expired"] and a["name"].startswith(prefix)]
            if len(matches) == 1:
                return {"runtime_run_id": str(run["id"]), "runtime_artifact_name": matches[0]["name"], "runtime_artifact_kind": kind}
            if len(matches) > 1:
                raise RuntimeError("Ambiguous runtime evidence for the tested revision")
        failures.append(run["id"])
    if failures and not pending:
        raise RuntimeError("Runtime build failed, was cancelled, or has no retained evidence for the tested revision")
    return None


def validate_evidence(directory, target_sha, run_id):
    from pathlib import Path
    root = Path(directory)
    provenance = json.loads((root / "provenance.json").read_text())
    manifest = json.loads((root / "runtime-manifest-unsigned.json").read_text())
    if provenance.get("portsideCommit") != target_sha or provenance.get("sourceCommits", {}).get("portside") != target_sha:
        raise RuntimeError("Runtime provenance does not belong to the tested revision")
    if not re.fullmatch(re.escape(str(run_id)) + r"-[1-9][0-9]*", provenance.get("buildId", "")):
        raise RuntimeError("Runtime provenance does not belong to the selected workflow run")
    if manifest.get("portsideCommit") != target_sha or manifest.get("buildId") != provenance["buildId"]:
        raise RuntimeError("Runtime manifest does not match the selected source and build")
    wrappers = [a for a in manifest.get("components", []) if a.get("component") == "wrapper"]
    if len(wrappers) != 1 or wrappers[0].get("sourceCommit") != target_sha:
        raise RuntimeError("Runtime wrapper does not belong to the tested revision")
    signed = json.loads((root / "runtime-manifest.json").read_text())
    for value in (manifest, signed):
        value.pop("signature", None)
        value.pop("signatureKeyId", None)
    if signed != manifest:
        raise RuntimeError("Signed and unsigned runtime evidence differ")


def main():
    sha = os.environ["TARGET_SHA"]
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise RuntimeError("Invalid tested revision")
    if len(sys.argv) == 3 and sys.argv[1] == "--validate-evidence":
        validate_evidence(sys.argv[2], sha, os.environ["RUNTIME_RUN_ID"])
        return
    repo = os.environ["GITHUB_REPOSITORY"]

    def api(path):
        result = subprocess.run(["gh", "api", f"repos/{repo}/{path}"], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError("GitHub runtime evidence request failed")
        return json.loads(result.stdout)

    deadline = time.monotonic() + 5 * 60 * 60
    while time.monotonic() < deadline:
        runs = api("actions/workflows/build-runtime.yml/runs?branch=main&per_page=100")["workflow_runs"]
        selected = select_runtime(runs, sha, api)
        if selected:
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                for key, value in selected.items():
                    output.write(f"{key}={value}\n")
            print(f"Using runtime run {selected['runtime_run_id']} for tested revision {sha}", flush=True)
            return
        engines = api(f"actions/workflows/build-engine.yml/runs?head_sha={sha}&branch=main&per_page=100")["workflow_runs"]
        if engines and all(r["status"] == "completed" and r["conclusion"] != "success" for r in engines):
            raise RuntimeError("Engine build failed or was cancelled for the tested revision")
        print(f"Waiting for runtime assembly of tested revision {sha}", flush=True)
        time.sleep(30)
    raise RuntimeError("Timed out waiting for runtime evidence of the tested revision")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, RuntimeError) else type(error).__name__, file=sys.stderr)
        sys.exit(1)
