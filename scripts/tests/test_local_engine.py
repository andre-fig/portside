import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from test_validate_publication import SHA, WINE, engine_fixture, write

spec = importlib.util.spec_from_file_location("engine_input", Path(__file__).parents[1] / "build-runtime/engine-input.py")
engine_input = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine_input)
publication = engine_input.publication
prepare_spec = importlib.util.spec_from_file_location("prepare_engine_push", Path(__file__).parents[1] / "build-runtime/prepare-engine-push.py")
prepare_engine = importlib.util.module_from_spec(prepare_spec)
prepare_spec.loader.exec_module(prepare_engine)
privacy_spec = importlib.util.spec_from_file_location("engine_privacy", Path(__file__).parents[1] / "build-runtime/validate-engine-privacy.py")
privacy = importlib.util.module_from_spec(privacy_spec)
privacy_spec.loader.exec_module(privacy)



def local_fixture(root):
    metadata = engine_fixture(root)
    metadata["build"].update(producer="local-pre-push", id="local-" + SHA + "-1")
    metadata["source"]["snapshotChecksum"] = "d" * 64
    metadata["artifact"]["storageKey"] = "runtime/engines/validated/fixture/engine.tar.xz"
    write(root, "engine-metadata.json", metadata)
    provenance = json.loads((root / "engine-provenance.json").read_text())
    provenance.update(buildId=metadata["build"]["id"], source=metadata["source"])
    write(root, "engine-provenance.json", provenance)
    return {"engineVersion": metadata["engineVersion"], "sourceCommit": WINE,
            "sourceSnapshotChecksum": "d" * 64, "archiveName": metadata["artifact"]["fileName"],
            "archiveKey": metadata["artifact"]["storageKey"]}


def proof(root, expected):
    metadata = json.loads((root / "engine-metadata.json").read_text())
    write(root, "engine-validation.json", {
        "kind": "PortsideEngineNativeValidation", "portsideCommit": SHA, "buildId": "42-1",
        "engineVersion": expected["engineVersion"], "archiveSha256": metadata["artifact"]["sha256"],
        "engineMetadataSha256": hashlib.sha256((root / "engine-metadata.json").read_bytes()).hexdigest(),
        "engineProvenanceSha256": hashlib.sha256((root / "engine-provenance.json").read_bytes()).hexdigest(),
    })


class LocalEngineTests(unittest.TestCase):
    def test_failed_compilation_preserves_a_sanitized_log_and_blocks_push(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "source", root / "output"
            script = source / "scripts/build-runtime/build-engine.sh"
            script.parent.mkdir(parents=True)
            output.mkdir()
            script.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$HOME/private-example"\nexit 7\n')
            script.chmod(0o700)
            with patch.object(prepare_engine, "ROOT", root), self.assertRaisesRegex(RuntimeError, "Push blocked"):
                prepare_engine.build_engine(source, output, os.environ.copy())
            log = (output / "build.log").read_text()
            self.assertNotIn(str(root), log)
            self.assertNotIn(str(Path.home()), log)
            self.assertIn("$SOURCE/scripts/", log)
            self.assertIn("$HOME/private-example", log)

    def test_embedded_personal_paths_are_rejected_without_echoing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for private in (b"/Users/fixture-user/build/wine", b"/home/fixture-user/build/wine"):
                (root / "binary").write_bytes(b"header\0" + private + b"\0tail")
                with self.assertRaises(RuntimeError) as failure:
                    privacy.validate(root)
                self.assertNotIn("fixture-user", str(failure.exception))

    def test_virtual_build_prefix_and_shared_system_path_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "binary").write_bytes(b"/opt/portside-wine/lib\0/portside-source/dlls\0/Users/Shared/library")
            privacy.validate(root)

    def test_ordinary_push_does_not_require_storage_or_start_compilation(self):
        with patch.object(prepare_engine.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)) as run, \
                patch.object(prepare_engine.engine_input, "storage_environment") as storage:
            self.assertFalse(prepare_engine.prepare("b" * 40, SHA))
            storage.assert_not_called()
            self.assertEqual(run.call_count, 1)

    def test_missing_transfer_configuration_blocks_before_local_build(self):
        with patch.object(prepare_engine.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run, \
                patch.object(prepare_engine.engine_input, "storage_environment", side_effect=RuntimeError("missing configuration")), \
                patch.object(prepare_engine.sys, "platform", "darwin"), \
                patch.object(prepare_engine.subprocess, "Popen") as export:
            with self.assertRaisesRegex(RuntimeError, "missing configuration"):
                prepare_engine.prepare("b" * 40, SHA)
            self.assertEqual(run.call_count, 1)
            export.assert_not_called()

    def test_local_source_proof_cannot_publish_without_native_ci_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = local_fixture(root)
            publication.validate_local_engine(root, SHA, expected)
            with self.assertRaises(RuntimeError):
                publication.validate_engine(root, SHA, "42")
            proof(root, expected)
            publication.validate_engine(root, SHA, "42")

    def test_native_proof_from_another_run_or_before_metadata_change_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = local_fixture(root)
            proof(root, expected)
            with self.assertRaises(RuntimeError):
                publication.validate_engine(root, SHA, "43")
            path = root / "engine-metadata.json"
            metadata = json.loads(path.read_text())
            metadata["build"]["clang"] = "changed after native check"
            write(root, path.name, metadata)
            with self.assertRaises(RuntimeError):
                publication.validate_engine(root, SHA, "42")

    def test_local_input_must_match_current_wine_and_recipe(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = local_fixture(root)
            for key in ("engineVersion", "sourceCommit", "sourceSnapshotChecksum", "archiveKey"):
                with self.subTest(key=key), self.assertRaises(RuntimeError):
                    publication.validate_local_engine(root, SHA, dict(expected, **{key: "wrong"}))

    def test_upload_only_uses_unpublished_build_input_namespace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = local_fixture(root)
            with patch.object(engine_input, "storage_environment", return_value={}), \
                    patch.dict(engine_input.os.environ, {"PORTSIDE_PUBLIC_BUCKET": "fixture-bucket"}), \
                    patch.object(engine_input.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
                engine_input.transfer("upload", root, SHA, expected)
                self.assertEqual(run.call_count, 3)
                for call in run.call_args_list:
                    self.assertIn("/runtime/build-inputs/engines/" + SHA + "/", call.args[0][4])
                    self.assertNotIn("/runtime/engines/validated/", call.args[0][4])

    def test_missing_input_fails_on_first_download_without_wait_or_compilation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = local_fixture(root)
            with patch.object(engine_input, "storage_environment", return_value={}), \
                    patch.dict(engine_input.os.environ, {"PORTSIDE_PUBLIC_BUCKET": "fixture-bucket"}), \
                    patch.object(engine_input.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)) as run:
                with self.assertRaisesRegex(RuntimeError, "no runner will wait or compile"):
                    engine_input.transfer("download", root, SHA, expected)
                self.assertEqual(run.call_count, 1)

    @unittest.skipUnless(hasattr(tarfile, "data_filter"), "safe extraction requires Python 3.12+ in the native CI job")
    def test_extraction_rejects_traversal_and_external_symlinks(self):
        for name, link in [("../escape", None), ("engine/link", "/tmp/escape")]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = root / "fixture.tar.xz"
                with tarfile.open(archive, "w:xz") as handle:
                    member = tarfile.TarInfo(name)
                    if link:
                        member.type = tarfile.SYMTYPE
                        member.linkname = link
                        handle.addfile(member)
                    else:
                        member.size = 1
                        handle.addfile(member, io.BytesIO(b"x"))
                with self.assertRaises((RuntimeError, tarfile.TarError)):
                    engine_input.extract_engine(archive, root / "extracted", "engine")


if __name__ == "__main__":
    unittest.main()
