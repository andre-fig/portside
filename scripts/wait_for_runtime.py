#!/usr/bin/env python3
"""Check release prerequisites once; never occupy a runner awaiting another build.

Read-only GitHub operations. workflow_run's head_sha can describe the default
branch rather than its explicitly checked-out engine revision, so the runtime's
run-name also carries that revision. Downloaded provenance is checked separately.
"""
import json
import os
import re
import subprocess
import sys


def resolve_target(event_name, event, sha, ref):
    if event_name == "workflow_run":
        trigger = event["workflow_run"]
        if trigger["head_branch"] != "main":
            raise RuntimeError("Production releases require main")
        if trigger["name"] == "Build Portside Runtime":
            match = re.fullmatch(r"Runtime production ([0-9a-f]{40})", trigger.get("display_title", ""))
            if not match:
                raise RuntimeError("Runtime event has no explicit source revision")
            sha = match[1]
        elif trigger["name"] == "CI":
            sha = trigger["head_sha"]
        else:
            raise RuntimeError("Unexpected release trigger")
        ref = "refs/heads/main"
    elif event_name != "workflow_dispatch":
        raise RuntimeError("Unexpected release event")
    if ref != "refs/heads/main" or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise RuntimeError("Production releases require a valid main revision")
    return {"sha": sha, "ref": ref}


def check_release(sha, api, automatic=True, current_run_id=None):
    if automatic:
        # The workflow-wide concurrency group serializes both completion events.
        # A successful publication prevents the second event from publishing again,
        # including when backend registration subsequently failed. Recovery then
        # requires an explicit manual run, rather than another automatic version.
        releases = api("actions/workflows/release-production.yml/runs?branch=main&per_page=100")["workflow_runs"]
        for run in releases:
            if str(run["id"]) == str(current_run_id) or run["head_branch"] != "main":
                continue
            if run.get("display_title") != "Release / Runtime production " + sha:
                continue
            jobs = api(f"actions/runs/{run['id']}/jobs?filter=latest&per_page=100")["jobs"]
            publication = [job for job in jobs if job["name"] == "Build, notarize and publish production release"]
            if any(job["conclusion"] == "success" or any(
                    step["name"] == "Publish production artifacts to Portside storage" and step.get("conclusion") == "success"
                    for step in job.get("steps", [])) for job in publication):
                return {"ready": "false", "reason": "already_published"}

    ci_runs = api(f"actions/workflows/ci.yml/runs?head_sha={sha}&per_page=100")["workflow_runs"]
    ci_id = None
    for run in sorted(ci_runs, key=lambda value: value["id"], reverse=True):
        if (run["head_sha"] != sha or run["head_branch"] != "main" or run["event"] != "push"
                or run["status"] != "completed" or run["conclusion"] != "success"):
            continue
        jobs = api(f"actions/runs/{run['id']}/jobs?filter=latest&per_page=100")["jobs"]
        required = [job for job in jobs if job["name"] in ("Production source policy", "Backend schema and build")]
        if ({job["name"] for job in required} == {"Production source policy", "Backend schema and build"}
                and len(required) == 2 and all(job["conclusion"] == "success" for job in required)):
            ci_id = str(run["id"])
            break
    if ci_id is None:
        return {"ready": "false", "reason": "ci_not_ready"}
    runs = api("actions/workflows/build-runtime.yml/runs?branch=main&per_page=100")["workflow_runs"]
    selected = select_runtime(runs, sha, api)
    if selected is None:
        return {"ready": "false", "reason": "runtime_not_ready"}
    return {"ready": "true", "ci_run_id": ci_id, **selected}


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
        assembly = [job for job in jobs if job["name"] in (
            "Build and publish production runtime", "Assemble and validate production runtime")]
        if run["conclusion"] != "success":
            failures.append(run["id"])
            continue
        if len(assembly) != 1 or assembly[0]["conclusion"] == "skipped":
            # An engine-changing push intentionally defers assembly to workflow_run.
            continue
        if assembly[0]["conclusion"] != "success":
            failures.append(run["id"])
            continue
        if assembly[0]["name"] == "Assemble and validate production runtime":
            publication = [job for job in jobs if job["name"] == "Sign and publish production runtime on Linux"]
            if len(publication) != 1 or publication[0]["conclusion"] != "success":
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
    def output(values):
        with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
            for key, value in values.items():
                handle.write(f"{key}={value}\n")

    if sys.argv[1:] == ["--resolve-target"]:
        with open(os.environ["GITHUB_EVENT_PATH"]) as handle:
            event = json.load(handle)
        output(resolve_target(os.environ["GITHUB_EVENT_NAME"], event, os.environ["GITHUB_SHA"], os.environ["GITHUB_REF"]))
        return
    sha = os.environ["TARGET_SHA"]
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise RuntimeError("Invalid tested revision")
    if len(sys.argv) == 3 and sys.argv[1] == "--validate-evidence":
        validate_evidence(sys.argv[2], sha, os.environ["RUNTIME_RUN_ID"])
        return
    repo = os.environ["GITHUB_REPOSITORY"]

    def api(path):
        result = subprocess.run(["gh", "api", "--paginate", "--slurp", f"repos/{repo}/{path}"], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError("GitHub runtime evidence request failed")
        pages = json.loads(result.stdout)
        return {key: [item for page in pages for item in page.get(key, [])]
                for key in ("workflow_runs", "jobs", "artifacts")}

    if os.environ["TARGET_REF"] != "refs/heads/main":
        raise RuntimeError("Production releases require main")
    automatic = os.environ["GITHUB_EVENT_NAME"] != "workflow_dispatch"
    selected = check_release(sha, api, automatic, os.environ["GITHUB_RUN_ID"])
    output(selected)
    if selected["ready"] == "false":
        if not automatic:
            raise RuntimeError("CI and matching runtime must finish before a manual release")
        print(f"Release deferred: {selected['reason']}; no runner will wait. Completion events recheck prerequisites.", flush=True)
    else:
        print(f"Using runtime run {selected['runtime_run_id']} and CI run {selected['ci_run_id']} for tested revision {sha}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, RuntimeError) else type(error).__name__, file=sys.stderr)
        sys.exit(1)
