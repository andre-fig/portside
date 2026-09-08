import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sikarugir_candidate", Path(__file__).parents[1] / "build-runtime/build-sikarugir-candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class SikarugirCandidateTests(unittest.TestCase):
    def fixture(self, root):
        inputs = root / "inputs"
        inputs.mkdir()
        def archive(name, members):
            with tarfile.open(inputs / name, "w:xz") as handle:
                for name, data, mode in members:
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    entry.mode = mode
                    handle.addfile(entry, io.BytesIO(data))
        launcher = b"original launcher bytes"
        sdk = b"original SDK bytes"
        archive("template.tar.xz", [
            ("Template.app/Contents/Info.plist", plistlib.dumps({"CFBundleExecutable": "Sikarugir", "Program Flags": "obsolete"}), 0o644),
            ("Template.app/Contents/MacOS/Sikarugir", launcher, 0o755),
            ("Template.app/Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk", sdk, 0o755),
            ("Template.app/Contents/Resources/NOTICE", b"retain original notice", 0o644),
        ])
        archive("engine.tar.xz", [("wine.bundle/bin/wine", b"original engine", 0o755), ("wine.bundle/bin/wineserver", b"original server", 0o755)])
        (inputs / "winetricks").write_bytes(b"original source script")
        components = []
        for name, file, archive_root in [("template", "template.tar.xz", "Template.app"), ("engine", "engine.tar.xz", "wine.bundle"), ("winetricks", "winetricks", None)]:
            data = (inputs / file).read_bytes()
            value = {"id": name, "fileName": file, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "producer": "Sikarugir"}
            if archive_root: value["archiveRoot"] = archive_root
            components.append(value)
        specification = {"schemaVersion": 1, "kind": "PortsideApprovedSikarugirInputs", "engineVersion": "original-engine", "components": components}
        host = root / "compiled-host"
        host.write_bytes(b"locally compiled host")
        host.chmod(0o755)
        source = root / "apps/runtime-host/Sources/PortsideRuntimeHost/main.swift"
        source.parent.mkdir(parents=True)
        source.write_text("fixture source")
        return inputs, specification, host

    def test_candidate_keeps_upstream_bytes_notices_and_accurate_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs, specification, host = self.fixture(root)
            output = root / "build/candidate"
            with patch.object(candidate.subprocess, "run") as verify:
                wrapper = candidate.assemble(inputs, output, host, "0.1.35", specification, checkout=root)
            self.assertEqual(verify.call_count, 2)
            for call in verify.call_args_list:
                self.assertEqual(call.args[0][:3], ["codesign", "--verify", "--strict"])
            self.assertEqual((wrapper / "Contents/MacOS/Sikarugir").read_bytes(), b"original launcher bytes")
            self.assertEqual((wrapper / "Contents/Resources/NOTICE").read_bytes(), b"retain original notice")
            info = plistlib.loads((wrapper / "Contents/Info.plist").read_bytes())
            self.assertEqual(info["CFBundleExecutable"], "Sikarugir")
            self.assertEqual(info["CFBundleIdentifier"], "com.portside.runtime")
            self.assertEqual(info["Program Flags"], "")
            config = json.loads((wrapper / "Contents/Resources/portside-runtime.json").read_text())
            self.assertEqual(config["integration"], "sikarugir")
            self.assertFalse((wrapper / config["prefixRelativePath"]).exists())
            provenance = json.loads((output / "provenance.json").read_text())
            self.assertEqual(provenance["inputs"], specification["components"])
            self.assertFalse(provenance["distributionReady"])
            self.assertEqual(provenance["launcherSha256"], hashlib.sha256(b"original launcher bytes").hexdigest())

    def test_changed_missing_and_symlinked_inputs_fail_before_assembly(self):
        for change in ["bytes", "size", "missing", "symlink", "filename", "duplicate"]:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                inputs, specification, host = self.fixture(root)
                value = specification["components"][0]
                file = inputs / value["fileName"]
                if change == "bytes": value["sha256"] = "0" * 64
                elif change == "size": value["size"] += 1
                elif change == "missing": file.unlink()
                elif change == "symlink":
                    original = root / "original"
                    file.rename(original)
                    file.symlink_to(original)
                elif change == "filename": value["fileName"] = "../escape"
                else: specification["components"].append(value)
                with self.assertRaises(RuntimeError):
                    candidate.assemble(inputs, root / "build/candidate", host, "0.1.35", specification, checkout=root)
                self.assertFalse((root / "build/candidate").exists())

    def test_existing_and_external_destinations_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs, specification, host = self.fixture(root)
            existing = root / "build/existing"
            existing.mkdir(parents=True)
            marker = existing / "preserve"
            marker.write_text("keep")
            for output in [existing, root / "outside-build", root / "build"]:
                with self.assertRaisesRegex(RuntimeError, "new directory"):
                    candidate.assemble(inputs, output, host, "0.1.35", specification, checkout=root)
            self.assertEqual(marker.read_text(), "keep")

    def test_component_signature_failure_cannot_produce_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs, specification, host = self.fixture(root)
            output = root / "build/candidate"
            with patch.object(candidate.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "codesign")):
                with self.assertRaises(subprocess.CalledProcessError):
                    candidate.assemble(inputs, output, host, "0.1.35", specification, checkout=root)
            self.assertFalse(output.exists())

    def test_extraction_rejects_escape_links_paths_and_duplicate_members(self):
        for variant in ["path", "link", "duplicate"]:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = root / "archive.tar.xz"
                with tarfile.open(archive, "w:xz") as handle:
                    entry = tarfile.TarInfo("Root/../../escape" if variant == "path" else "Root/file")
                    if variant == "link":
                        entry.type = tarfile.SYMTYPE
                        entry.linkname = "../../outside"
                    handle.addfile(entry)
                    if variant == "duplicate": handle.addfile(entry)
                with self.assertRaises((RuntimeError, tarfile.TarError)):
                    candidate.extract(archive, root / "extracted", "Root")
                self.assertFalse((root / "escape").exists())

    def test_contained_hardlinks_are_not_mistaken_for_duplicate_archive_members(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "archive.tar.xz"
            with tarfile.open(archive, "w:xz") as handle:
                entry = tarfile.TarInfo("Root/original")
                entry.size = 8
                handle.addfile(entry, io.BytesIO(b"preserve"))
                link = tarfile.TarInfo("Root/link")
                link.type = tarfile.LNKTYPE
                link.linkname = "Root/original"
                handle.addfile(link)
            candidate.extract(archive, root / "extracted", "Root")
            self.assertEqual((root / "extracted/Root/link").read_bytes(), b"preserve")

    def test_contained_executable_rejects_escape_and_missing_execute_permission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wrapper = root / "Wrapper"
            wrapper.mkdir()
            outside = root / "outside"
            outside.write_text("unrelated")
            outside.chmod(0o755)
            (wrapper / "launcher").symlink_to(outside)
            with self.assertRaises(RuntimeError): candidate.contained_executable(wrapper, "launcher")
            (wrapper / "launcher").unlink()
            (wrapper / "launcher").write_text("not executable")
            with self.assertRaises(RuntimeError): candidate.contained_executable(wrapper, "launcher")
