import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("inspect_sikarugir", Path(__file__).parents[1] / "build-runtime/inspect-sikarugir-template.py")
inspection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspection)


class ReferenceInspectionTests(unittest.TestCase):
    def fixture(self, root, omit=None, extra=None):
        # Synthetic bytes only; never copy an installed wrapper or user prefix.
        info = {"CFBundleVersion": "1.0.15", "LSMinimumSystemVersion": "14.0", "CFBundleExecutable": "launcher",
                "D9VK": 1, "DXVK": 0, "D3DMETAL": 0, "MOLTENVKCX": 1, "Skip Mono": 0, "Skip Gecko": 0}
        files = {"Contents/Info.plist": plistlib.dumps(info)}
        for name in (
            "Contents/MacOS/Sikarugir",
            "Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk",
            "Contents/Frameworks/renderer/dxmt/wine/x86_64-windows/d3d11.dll",
            "Contents/Frameworks/renderer/dxmt/wine/i386-windows/d3d11.dll",
            "Contents/Frameworks/renderer/dxmt/wine/x86_64-unix/winemetal.so",
            "Contents/Frameworks/renderer/d9vk/wine/x86_64-windows/d3d9.dll",
            "Contents/Frameworks/libMoltenVK.dylib",
            "Contents/Frameworks/libvulkan_kosmickrisp.dylib",
        ):
            files[name] = b"synthetic component"
        for renderer in ("dxmt", "d9vk"):
            files[f"Contents/Frameworks/renderer/{renderer}/version"] = b"synthetic version"
        for name in ("MoltenVK_icd.json", "kosmickrisp_mesa_icd.json"):
            files["Contents/Resources/vulkan/icd.d/" + name] = json.dumps({"ICD": {"api_version": "1.4.0", "library_path": "synthetic"}}).encode()
        files.pop(omit, None)
        archive = root / "reference.tar.xz"
        with tarfile.open(archive, "w:xz") as bundle:
            for name, data in files.items():
                member = tarfile.TarInfo("Reference.app/" + name)
                member.size = len(data)
                bundle.addfile(member, io.BytesIO(data))
            if extra is not None:
                bundle.addfile(extra)
        reference = {"purpose": "inspection-only; never a commercial build input or download fallback",
                     "archiveRoot": "Reference.app", "size": archive.stat().st_size,
                     "sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}
        return archive, reference

    def test_inventory_never_claims_build_or_graphical_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, reference = self.fixture(root)
            result = inspection.inspect_template(archive, reference)
            self.assertEqual(result["minimumMacOS"], "14.0")
            self.assertFalse(result["sourceBuildVerified"])
            self.assertEqual(result["graphicalAcceptance"], "not tested")
            self.assertEqual(list(root.iterdir()), [archive])  # No extraction.

    def test_changed_size_or_same_size_content_rejected(self):
        for same_size in (True, False):
            with self.subTest(same_size=same_size), tempfile.TemporaryDirectory() as directory:
                archive, reference = self.fixture(Path(directory))
                data = archive.read_bytes()
                archive.write_bytes(bytes([data[0] ^ 1]) + data[1:] if same_size else data + b"x")
                with self.assertRaisesRegex(ValueError, "mismatch"):
                    inspection.inspect_template(archive, reference)

    def test_metadata_only_wrapper_or_missing_renderer_is_not_integration(self):
        for omitted in ("Contents/MacOS/Sikarugir", "Contents/Frameworks/renderer/dxmt/wine/x86_64-unix/winemetal.so"):
            with self.subTest(omitted=omitted), tempfile.TemporaryDirectory() as directory:
                archive, reference = self.fixture(Path(directory), omit=omitted)
                with self.assertRaisesRegex(ValueError, "Missing regular"):
                    inspection.inspect_template(archive, reference)

    def test_duplicate_traversal_and_symlink_components_rejected(self):
        for name, symlink in (("Reference.app/Contents/Info.plist", False), ("Reference.app/../outside", False),
                              ("Reference.app/Contents/MacOS/Sikarugir", True)):
            with self.subTest(name=name, symlink=symlink), tempfile.TemporaryDirectory() as directory:
                member = tarfile.TarInfo(name)
                if symlink:
                    member.type = tarfile.SYMTYPE
                    member.linkname = "/outside"
                archive, reference = self.fixture(Path(directory), omit="Contents/MacOS/Sikarugir" if symlink else None, extra=member)
                with self.assertRaises(ValueError):
                    inspection.inspect_template(archive, reference)

    def test_archive_symlink_and_production_relabel_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, reference = self.fixture(root)
            link = root / "link"
            link.symlink_to(archive)
            with self.assertRaisesRegex(ValueError, "regular file"):
                inspection.inspect_template(link, reference)
            reference["purpose"] = "production"
            with self.assertRaisesRegex(ValueError, "inspection-only"):
                inspection.inspect_template(archive, reference)


if __name__ == "__main__":
    unittest.main()
