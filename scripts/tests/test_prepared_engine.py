import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

from test_local_engine import local_fixture
from test_validate_publication import SHA, WINE, archive, write

spec = importlib.util.spec_from_file_location("prepared_engine", Path(__file__).parents[1] / "build-runtime/prepared-engine.py")
prepared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepared)
VERSION = "0.1.34"


def fixture(root):
    expected = local_fixture(root)
    metadata = json.loads((root / "engine-metadata.json").read_text())
    metadata["schemaVersion"] = 1
    metadata["build"].update(portsideCommit=WINE, id="local-" + WINE + "-1")
    write(root, "engine-input.json", metadata)
    archive(root, "PortsideWineEngine-" + VERSION + ".tar.xz")
    prepared.record(root, VERSION, SHA, "43", "1", expected)
    return expected


class PreparedEngineTests(unittest.TestCase):
    def test_native_fetch_consumes_prepared_input_without_storage_credentials(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            scripts = root / "scripts/build-runtime"
            scripts.mkdir(parents=True)
            build = root / "build/runtime"
            build.mkdir(parents=True)
            expected = fixture(build)
            original = Path(__file__).parents[1] / "build-runtime"
            for name in ("fetch-engine.sh", "prepared-engine.py", "validate-publication.py"):
                shutil.copy2(original / name, scripts / name)
            resolver = scripts / "resolve-engine.sh"
            resolver.write_text("#!/bin/sh\nprintf '%s\\n' " + shlex.quote(json.dumps(expected)) + "\n")
            resolver.chmod(0o755)
            commands = root / "commands"
            commands.mkdir()
            git = commands / "git"
            git.write_text("#!/bin/sh\nprintf '%s\\n' " + SHA + "\n")
            git.chmod(0o755)
            environment = {"PATH": str(commands) + os.pathsep + os.environ["PATH"],
                           "PORTSIDE_RUNTIME_VERSION": VERSION, "PORTSIDE_USE_PREPARED_ENGINE": "true",
                           "GITHUB_RUN_ID": "43"}
            result = subprocess.run([str(scripts / "fetch-engine.sh")], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Prepared runtime engine verify passed", result.stdout)

    def test_matching_prepared_archive_from_an_older_published_engine_is_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = fixture(root)
            prepared.verify(root, VERSION, SHA, "43", expected)
            self.assertIn("  PortsideWineEngine-" + VERSION, (root / ("PortsideWineEngine-" + VERSION + ".sha256")).read_text())

    def test_wrong_workflow_source_or_runtime_version_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = fixture(root)
            for version, sha, run in [(VERSION, WINE, "43"), (VERSION, SHA, "44"), ("0.1.35", SHA, "43")]:
                with self.subTest(version=version, sha=sha, run=run), self.assertRaises(RuntimeError):
                    prepared.verify(root, version, sha, run, expected)

    def test_changed_archive_or_metadata_is_rejected(self):
        for name in ("engine-input.json", "PortsideWineEngine-" + VERSION + ".tar.xz"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                expected = fixture(root)
                with (root / name).open("ab") as handle:
                    handle.write(b" ")
                with self.assertRaises(RuntimeError):
                    prepared.verify(root, VERSION, SHA, "43", expected)

    def test_missing_receipt_wrong_recipe_and_symlink_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = fixture(root)
            with self.assertRaises(RuntimeError):
                prepared.verify(root, VERSION, SHA, "43", dict(expected, engineVersion="wrong"))
            receipt = root / "prepared-engine.json"
            saved = root / "saved.json"
            receipt.rename(saved)
            with self.assertRaises(RuntimeError):
                prepared.verify(root, VERSION, SHA, "43", expected)
            receipt.symlink_to(saved)
            with self.assertRaises(RuntimeError):
                prepared.verify(root, VERSION, SHA, "43", expected)
