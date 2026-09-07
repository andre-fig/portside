import hashlib
import importlib.util
import json
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
