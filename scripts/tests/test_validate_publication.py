import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("validate_publication", Path(__file__).parents[1] / "build-runtime/validate-publication.py")
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)
SHA = "a" * 40
WINE = "b" * 40
WINETRICKS = "c" * 40


def write(root, name, value):
    (root / name).write_text(json.dumps(value))


def archive(root, name):
    data = b"fixture archive bytes; native layout validation belongs to macOS"
    (root / name).write_bytes(data)
    return {"fileName": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def engine_fixture(root):
    version = "11.17-test-x86_64"
    artifact = archive(root, "PortsideWineEngine-" + version + ".tar.xz")
    common = {"kind": "PortsideRuntimeEngine", "engineVersion": version,
              "source": {"commit": WINE}, "dependencies": []}
    metadata = dict(common, artifact=artifact, build={"portsideCommit": SHA, "id": "42-1", "targetArchitecture": "x86_64"})
    write(root, "engine-metadata.json", metadata)
    write(root, "engine-provenance.json", dict(common, portsideCommit=SHA, buildId="42-1", artifact=artifact))
    return metadata


def runtime_fixture(root):
    engine = engine_fixture(root)
    version = "0.1.30"
    components = []
    files = []
    for kind, label, source in [("wrapper", "Wrapper", SHA), ("engine", "WineEngine", WINE), ("winetricks", "Winetricks", WINETRICKS)]:
        name = "Portside" + label + "-" + version + ".tar.xz"
        files.append(name)
        component = dict(archive(root, name), component=kind, sourceCommit=source,
                         version=engine["engineVersion"] if kind == "engine" else version)
        components.append(component)
    write(root, "runtime-manifest-unsigned.json", {
        "manifestVersion": version, "channel": "production", "portsideCommit": SHA, "buildId": "43-1", "components": components})
    write(root, "provenance.json", {
        "version": version, "channel": "production", "portsideCommit": SHA, "buildId": "43-1",
        "sourceCommits": {"portside": SHA, "wine": WINE, "winetricks": WINETRICKS}, "artifacts": files,
        "engine": {"version": engine["engineVersion"], "buildId": engine["build"]["id"],
                   "sourceArchiveSha256": engine["artifact"]["sha256"], "runtimeArchiveSha256": components[1]["sha256"]}})
    write(root, "engine-input.json", engine)
    write(root, "sbom.spdx.json", {"spdxVersion": "SPDX-2.3"})


class PublicationTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("jq"), "Runtime metadata recipe requires jq")
    def test_real_assembly_recipe_emits_patch_inventory(self):
        # Native compilation/extraction is covered by separate macOS controls.
        # Exercise the actual metadata recipe with synthetic component archives.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = root / "build/runtime"
            build.mkdir(parents=True)
            runtime_fixture(build)
            patches = [{"file": "0001-overlay.patch", "sha256": "d" * 64, "license": "LGPL-2.1-or-later"}]
            engine = json.loads((build / "engine-input.json").read_text())
            engine["source"].update(patches=patches, snapshotChecksum="e" * 64)
            engine["artifact"]["storageKey"] = "runtime/engines/test.tar.xz"
            write(build, "engine-input.json", engine)
            recipes = root / "scripts/build-runtime"
            recipes.mkdir(parents=True)
            shutil.copyfile(Path(__file__).parents[1] / "build-runtime/build.sh", recipes / "build.sh")
            for name in ("source-audit.sh", "build-wrapper.sh", "fetch-engine.sh", "build-winetricks.sh", "validate-clean-layout.sh", "validate-manifest.sh"):
                stub = recipes / name
                stub.write_text("#!/bin/sh\nexit 0\n")
                stub.chmod(0o755)
            upstream_script = root / "scripts/upstream/snapshot_checksum.sh"
            upstream_script.parent.mkdir()
            upstream_script.write_text("#!/bin/sh\nprintf '%s\\n' " + "f" * 64 + "\n")
            upstream_script.chmod(0o755)
            for name in ("runtime/wrapper-template", "apps/runtime-host", "upstream"):
                (root / name).mkdir(parents=True)
            write(root / "upstream", "lock.json", {"repositories": [{"name": "winetricks", "commit": WINETRICKS, "snapshotChecksum": "f" * 64}]})
            write(root / "upstream", "dependencies.json", {"dependencies": [{"name": "freetype", "version": "2-test", "sha256": "f" * 64}]})
            env = {"PATH": os.environ["PATH"], "PORTSIDE_RUNTIME_VERSION": "0.1.30", "PORTSIDE_COMMIT": SHA,
                   "PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX": "https://example.invalid/fixtures", "GITHUB_RUN_ID": "43", "GITHUB_RUN_ATTEMPT": "1"}
            subprocess.run(["sh", str(recipes / "build.sh")], env=env, check=True, capture_output=True)
            provenance = json.loads((build / "provenance.json").read_text())
            self.assertEqual(provenance["engine"]["patches"], patches)
            publication.validate_runtime(build, SHA, "43")

    def test_runtime_preserves_patches_in_provenance_and_sbom(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime_fixture(root)
            patches = [{"file": "0001-overlay.patch", "sha256": "d" * 64, "license": "LGPL-2.1-or-later"}]
            engine = json.loads((root / "engine-input.json").read_text())
            engine["source"]["patches"] = patches
            write(root, "engine-input.json", engine)
            with self.assertRaisesRegex(RuntimeError, "patch provenance mismatch"):
                publication.validate_runtime(root, SHA, "43")
            provenance = json.loads((root / "provenance.json").read_text())
            provenance["engine"]["patches"] = patches
            write(root, "provenance.json", provenance)
            with self.assertRaisesRegex(RuntimeError, "SBOM patch inventory mismatch"):
                publication.validate_runtime(root, SHA, "43")
            write(root, "sbom.spdx.json", {"packages": [{"SPDXID": "SPDXRef-wine", "sourceInfo": json.dumps({"portsidePatches": patches})}]})
            publication.validate_runtime(root, SHA, "43")

    def test_patch_provenance_must_match_engine_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = engine_fixture(root)
            metadata["source"]["patches"] = [{"file": "0001-overlay.patch", "sha256": "d" * 64}]
            write(root, "engine-metadata.json", metadata)
            with self.assertRaisesRegex(RuntimeError, "provenance and metadata disagree"):
                publication.validate_engine(root, SHA, "42")
            provenance = json.loads((root / "engine-provenance.json").read_text())
            provenance["source"] = metadata["source"]
            write(root, "engine-provenance.json", provenance)
            publication.validate_engine(root, SHA, "42")

    def test_transferred_engine_and_runtime_accepted_without_running_wine(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime_fixture(root)
            publication.validate_engine(root, SHA, "42")
            publication.validate_runtime(root, SHA, "43")

    def test_changed_archive_bytes_or_size_rejected(self):
        for same_size in (True, False):
            with self.subTest(same_size=same_size), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                metadata = engine_fixture(root)
                (root / metadata["artifact"]["fileName"]).write_bytes(b"x" * (metadata["artifact"]["size"] if same_size else 1))
                with self.assertRaises(RuntimeError):
                    publication.validate_engine(root, SHA, "42")

    def test_source_and_workflow_run_must_match(self):
        for sha, run_id in [(WINE, "42"), (SHA, "99")]:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                engine_fixture(root)
                with self.assertRaises(RuntimeError):
                    publication.validate_engine(root, sha, run_id)

    def test_archive_symlink_and_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = engine_fixture(root)
            path = root / metadata["artifact"]["fileName"]
            path.rename(root / "original")
            path.symlink_to("original")
            with self.assertRaises(RuntimeError):
                publication.validate_engine(root, SHA, "42")
            with self.assertRaises(RuntimeError):
                publication.check_archive(root, "../original", metadata["artifact"])

    def test_runtime_wrong_source_missing_component_or_engine_disagreement_rejected(self):
        cases = [
            ("runtime-manifest-unsigned.json", lambda value: value.update(portsideCommit=WINE)),
            ("runtime-manifest-unsigned.json", lambda value: value["components"].pop()),
            ("runtime-manifest-unsigned.json", lambda value: value["components"][0].update(sourceCommit=WINE)),
            ("provenance.json", lambda value: value["engine"].update(sourceArchiveSha256="0" * 64)),
            ("engine-input.json", lambda value: value["build"].update(id="999-1")),
        ]
        for name, mutate in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                runtime_fixture(root)
                value = json.loads((root / name).read_text())
                mutate(value)
                write(root, name, value)
                with self.assertRaises(RuntimeError):
                    publication.validate_runtime(root, SHA, "43")

    def test_runtime_metadata_and_archives_are_required(self):
        for name in ("sbom.spdx.json", "engine-input.json", "PortsideWrapper-0.1.30.tar.xz"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                runtime_fixture(root)
                (root / name).unlink()
                with self.assertRaises(RuntimeError):
                    publication.validate_runtime(root, SHA, "43")


if __name__ == "__main__":
    unittest.main()
