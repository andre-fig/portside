import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("wait_for_runtime", Path(__file__).parents[1] / "wait_for_runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
SHA = "a" * 40
OTHER = "b" * 40


def run(id=2, sha=SHA, status="completed", conclusion="success", event="push", **extra):
    return dict(id=id, head_sha=sha, head_branch="main", status=status, conclusion=conclusion, event=event, **extra)


def api(path):
    if "/jobs?" in path:
        return {"jobs": [{"name": "Build and publish production runtime", "conclusion": "success"}]}
    return {"artifacts": [{"name": "portside-runtime-metadata-production-0.1.30", "expired": False}]}


class RuntimeSelectionTests(unittest.TestCase):
    def test_older_success_never_substitutes_for_pending_target(self):
        result = runtime.select_runtime([run(id=1, sha=OTHER), run(status="in_progress", conclusion=None)], SHA, api)
        self.assertIsNone(result)

    def test_successful_target_selected_even_with_newer_other_runtime(self):
        result = runtime.select_runtime([run(id=99, sha=OTHER), run()], SHA, api)
        self.assertEqual(result["runtime_run_id"], "2")

    def test_engine_push_skipped_assembly_waits_for_followup(self):
        def skipped(path):
            return {"jobs": [{"name": "Build and publish production runtime", "conclusion": "skipped"}]}
        self.assertIsNone(runtime.select_runtime([run()], SHA, skipped))

    def test_workflow_run_binds_explicit_checkout_instead_of_default_branch_head(self):
        result = runtime.select_runtime([run(sha=OTHER, event="workflow_run", display_title="Runtime production " + SHA)], SHA, api)
        self.assertEqual(result["runtime_run_id"], "2")

    def test_new_default_branch_head_does_not_adopt_older_workflow_run(self):
        stale = run(event="workflow_run", display_title="Runtime production " + OTHER)
        self.assertIsNone(runtime.select_runtime([stale], SHA, api))

    def test_failure_and_cancellation_stop_release(self):
        for conclusion in ("failure", "cancelled", "timed_out"):
            with self.assertRaises(RuntimeError):
                runtime.select_runtime([run(conclusion=conclusion)], SHA, api)

    def test_expired_artifacts_stop_release(self):
        def expired(path):
            result = api(path)
            for artifact in result.get("artifacts", []):
                artifact["expired"] = True
            return result
        with self.assertRaises(RuntimeError):
            runtime.select_runtime([run()], SHA, expired)

    def test_pull_request_cannot_supply_production_runtime(self):
        self.assertIsNone(runtime.select_runtime([run(event="pull_request")], SHA, api))


class RuntimeEvidenceTests(unittest.TestCase):
    def evidence(self, root):
        provenance = {"portsideCommit": SHA, "sourceCommits": {"portside": SHA}, "buildId": "2-1"}
        manifest = {"portsideCommit": SHA, "buildId": "2-1", "components": [{"component": "wrapper", "sourceCommit": SHA}]}
        (root / "provenance.json").write_text(json.dumps(provenance))
        (root / "runtime-manifest-unsigned.json").write_text(json.dumps(manifest))
        (root / "runtime-manifest.json").write_text(json.dumps(dict(manifest, signature="signed", signatureKeyId="key")))

    def test_matching_source_and_run_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            self.evidence(Path(directory))
            runtime.validate_evidence(directory, SHA, "2")

    def test_wrong_provenance_wrapper_or_workflow_rejected(self):
        for file, key, value in [("provenance.json", "portsideCommit", OTHER),
                                 ("provenance.json", "buildId", "9-1"),
                                 ("runtime-manifest-unsigned.json", "components", [{"component": "wrapper", "sourceCommit": OTHER}])]:
            with self.subTest(file=file, key=key), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.evidence(root)
                data = json.loads((root / file).read_text())
                data[key] = value
                (root / file).write_text(json.dumps(data))
                with self.assertRaises(RuntimeError):
                    runtime.validate_evidence(directory, SHA, "2")

    def test_signed_manifest_cannot_disagree_with_validated_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.evidence(root)
            signed = root / "runtime-manifest.json"
            data = json.loads(signed.read_text())
            data["portsideCommit"] = OTHER
            signed.write_text(json.dumps(data))
            with self.assertRaises(RuntimeError):
                runtime.validate_evidence(directory, SHA, "2")


class RuntimeChangeFilterTests(unittest.TestCase):
    def decisions(self, files):
        # Supply a synthetic diff without making commits or changing this checkout.
        with tempfile.TemporaryDirectory() as directory:
            git = Path(directory) / "git"
            git.write_text('#!/bin/sh\ncase "$3" in cat-file) exit 0 ;; diff) printf "%s\\n" "$TEST_CHANGED_FILES" ;; *) exit 2 ;; esac\n')
            git.chmod(0o755)
            env = dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"], TEST_CHANGED_FILES="\n".join(files))
            script = Path(__file__).parents[1] / "build-runtime/changed-components.sh"
            return tuple(subprocess.run([str(script), component, OTHER, SHA], env=env, capture_output=True).returncode for component in ("engine", "assembly"))

    def test_app_and_release_inputs_assemble_without_rebuilding_wine(self):
        for file in ("apps/desktop/Sources/Portside/PortsideApp.swift", "scripts/sign_release.sh",
                     "scripts/register_runtime_release.sh", "scripts/wait_for_runtime.py"):
            with self.subTest(file=file):
                self.assertEqual(self.decisions([file]), (1, 0))

    def test_recipe_change_requires_engine_before_assembly(self):
        self.assertEqual(self.decisions(["scripts/build-runtime/build-wine-engine.sh",
                                         "apps/desktop/Sources/Portside/PortsideApp.swift"]), (0, 0))


if __name__ == "__main__":
    unittest.main()
