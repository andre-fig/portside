import importlib.util
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import test_sikarugir_candidate as fixtures

ROOT = Path(__file__).parents[2]

def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts/build-runtime" / file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

runtime = module("sikarugir_package", "package-sikarugir-runtime.py")
publication = module("sikarugir_publication", "validate-publication.py")
transfer = module("sikarugir_transfer", "sikarugir-inputs.py")
SHA = "a" * 40


class SikarugirRuntimeTests(unittest.TestCase):
    def fixture(self, root):
        inputs, approved, _ = fixtures.SikarugirCandidateTests().fixture(root)
        for item in approved["components"]:
            item["url"] = "https://github.com/Sikarugir-App/Fixture/releases/download/v1/" + item["fileName"]
        (root / "upstream").mkdir()
        (root / "upstream/sikarugir-runtime.json").write_text(json.dumps(approved))
        real_run = subprocess.run
        def execute(command, **kwargs):
            if command[0] == "swiftc":
                host = Path(command[-1])
                host.write_bytes(b"compiled fixture maintenance helper")
                host.chmod(0o755)
                return subprocess.CompletedProcess(command, 0)
            if command[0] == "codesign":
                if "-R" in command:
                    self.assertTrue(command[command.index("-R") + 1].startswith("="), "Inline requirements must not be interpreted as filenames")
                return subprocess.CompletedProcess(command, 0, stdout="", stderr="Signature=adhoc")
            if command[0].endswith("create-archive.sh"):
                _, archive, directory, item = command
                return real_run(["tar", "-cJf", archive, "-C", directory, item], check=True, capture_output=True)
            raise AssertionError("Unexpected command: " + str(command))
        with patch.object(runtime.subprocess, "run", side_effect=execute):
            result = runtime.package(inputs, root / "build/result", "0.1.36", "https://portside.test/v1/runtime/artifacts/production/", SHA, "42-1", checkout=root)
        return inputs, approved, result

    def test_packaged_engine_preserves_original_archive_bytes_and_timestamps(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs, _, output = self.fixture(root)
            self.assertEqual((output / "PortsideWineEngine-0.1.36.tar.xz").read_bytes(), (inputs / "engine.tar.xz").read_bytes())
            with tarfile.open(output / "PortsideWrapper-0.1.36.tar.xz") as archive:
                prefix = archive.getmember("PortsideBaseline.app/Contents/SharedSupport/prefix")
                self.assertTrue(prefix.issym())
                self.assertEqual(prefix.linkname, "../../../../Prefixes/PortsideBaseline")
                self.assertFalse(any(name.startswith("PortsideBaseline.app/Contents/SharedSupport/wine/") for name in archive.getnames()))
            with tarfile.open(output / "PortsideWinetricks-0.1.36.tar.xz") as archive:
                self.assertEqual(archive.extractfile("PortsideWinetricks-0.1.36/src/winetricks").read(), b"original source script")

    def test_publication_requires_native_archive_binding_and_distribution_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, _, output = self.fixture(root)
            manifest = json.loads((output / "runtime-manifest-unsigned.json").read_text())
            native = {"kind": "PortsideSikarugirInstallationProbe", "portsideCommit": SHA, "buildId": "42-1",
                      "legacyMetadataReplacementVerified": True,
                      "syntheticDataPreserved": True, "startupSkipped": True, "wrapperMetadataPreserved": True,
                      "windowsX64Exit": 37, "windowsX86Exit": 23,
                      "archiveChecksums": {v["component"]: v["sha256"] for v in manifest["components"]}}
            def write_report(): (output / "native-validation.json").write_text(json.dumps(native))
            write_report()
            with patch.object(publication, "__file__", str(root / "scripts/build-runtime/validate-publication.py")):
                with self.assertRaisesRegex(RuntimeError, "distribution signing acceptance is pending"):
                    publication.validate_runtime(output, SHA, "42")
                native["legacyMetadataReplacementVerified"] = False
                write_report()
                with self.assertRaisesRegex(RuntimeError, "native installation acceptance"):
                    publication.validate_runtime(output, SHA, "42")
                native["legacyMetadataReplacementVerified"] = True
                write_report()
                provenance_path = output / "provenance.json"
                provenance = json.loads(provenance_path.read_text())
                provenance.update(distributionReady=True, signatureKind="Developer ID entry points")
                provenance_path.write_text(json.dumps(provenance))
                native.update(componentSignaturesVerified=True, distributionSignatureVerified=True,
                              nativeComponentChecksums=provenance["nativeComponentChecksums"])
                write_report()
                publication.validate_runtime(output, SHA, "42")
                native["nativeComponentChecksums"] = dict(provenance["nativeComponentChecksums"], sdk="0" * 64)
                write_report()
                with self.assertRaisesRegex(RuntimeError, "distribution signing acceptance is pending"):
                    publication.validate_runtime(output, SHA, "42")
                native["nativeComponentChecksums"] = provenance["nativeComponentChecksums"]
                native["archiveChecksums"]["engine"] = "0" * 64
                write_report()
                with self.assertRaisesRegex(RuntimeError, "native installation acceptance"):
                    publication.validate_runtime(output, SHA, "42")
                with self.assertRaisesRegex(RuntimeError, "another workflow"):
                    publication.validate_runtime(output, SHA, "99")
                with (output / "PortsideWineEngine-0.1.36.tar.xz").open("ab") as handle: handle.write(b"changed")
                with self.assertRaisesRegex(RuntimeError, "size mismatch"):
                    publication.validate_runtime(output, SHA, "42")

    def test_input_transfer_rejects_other_source_run_changed_bytes_and_symlink_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs, _, _ = self.fixture(root)
            with patch.object(transfer, "ROOT", root):
                file = inputs / "sikarugir-inputs.json"
                file.write_text(json.dumps(transfer.receipt(SHA, "42-1")))
                transfer.verify(inputs, SHA, "42-1")
                for sha, run in [("b" * 40, "42-1"), (SHA, "43-1")]:
                    with self.assertRaisesRegex(RuntimeError, "source revision and build"):
                        transfer.verify(inputs, sha, run)
                original = root / "original-receipt"
                file.rename(original)
                file.symlink_to(original)
                with self.assertRaises(RuntimeError): transfer.verify(inputs, SHA, "42-1")
                file.unlink(); original.rename(file)
                (inputs / "winetricks").write_bytes(b"changed")
                with self.assertRaises(RuntimeError): transfer.verify(inputs, SHA, "42-1")

    def test_workflow_keeps_source_bound_inputs_native_installation_and_publication_gate(self):
        workflow = (ROOT / ".github/workflows/build-runtime.yml").read_text()
        self.assertIn("sikarugir-inputs.py prepare", workflow)
        self.assertIn("sikarugir-inputs.py verify", workflow)
        self.assertIn("validate-publication.py runtime", workflow)
        self.assertIn("build/runtime/native-validation.json", workflow)
        self.assertNotIn("build-wine-engine.sh", workflow)
        self.assertNotIn("fetch-engine.sh", workflow)
        # Engine completion used to create an extra no-op run and consume a
        # runtime version even though Sikarugir assembly has no engine dependency.
        self.assertNotIn("workflow_run", workflow)
        self.assertNotIn("ENGINE_RUN_ID", workflow)
        self.assertIn("  push:", workflow)
        self.assertIn("  workflow_dispatch:", workflow)
        self.assertIn("run-name: Runtime production ${{ github.sha }}", workflow)
        script = (ROOT / "scripts/build-runtime/build.sh").read_text()
        self.assertIn("package-sikarugir-runtime.py", script)
        self.assertIn("validate-sikarugir-installation.py", script)
