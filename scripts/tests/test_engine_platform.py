import importlib.util
from pathlib import Path
import unittest
import tempfile

spec = importlib.util.spec_from_file_location("engine_execution", Path(__file__).parents[1] / "build-runtime/validate-engine-execution.py")
execution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(execution)


class EnginePlatformTests(unittest.TestCase):
    def command_fixture(self, root):
        paths = []
        for arch in ("i386", "x86_64"):
            path = root / "lib/wine" / (arch + "-windows") / "kernelbase.dll"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"synthetic kernelbase")
            paths.append(path)
        return paths

    def test_command_guard_accepts_both_clean_architectures(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.command_fixture(root)
            execution.check_steam_command_policy(root)

    def test_command_guard_rejects_legacy_injection_in_either_architecture_and_encoding(self):
        for arch in (0, 1):
            for encoding in ("ascii", "utf-16le"):
                with self.subTest(arch=arch, encoding=encoding), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    paths = self.command_fixture(root)
                    paths[arch].write_bytes("steamwebhelper.exe\0 --no-sandbox --in-process-gpu --disable-gpu\0".encode(encoding))
                    with self.assertRaisesRegex(RuntimeError, "sandbox-disabling"):
                        execution.check_steam_command_policy(root)

    def test_command_guard_rejects_missing_architecture_and_external_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "engine"
            paths = self.command_fixture(root)
            paths[0].unlink()
            with self.assertRaisesRegex(RuntimeError, "contained kernelbase"):
                execution.check_steam_command_policy(root)
            outside = Path(temporary) / "external.dll"
            outside.write_bytes(b"synthetic")
            paths[0].symlink_to(outside)
            with self.assertRaisesRegex(RuntimeError, "contained kernelbase"):
                execution.check_steam_command_policy(root)

    def test_accepts_supported_floor_with_a_newer_sdk_and_linker(self):
        execution.check_deployment("cmd LC_BUILD_VERSION\nplatform MACOS\nminos 13.0\nsdk 26.2\nversion 1267.0")
        execution.check_deployment("cmd LC_VERSION_MIN_MACOSX\ncmdsize 16\nversion 10.15\nsdk 26.2")

    def test_rejects_newer_local_sdk_default_or_one_incompatible_slice(self):
        for output in ("minos 26.0\nsdk 26.2", "minos 13.0\nminos 14.0", "minos 13.0.1"):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                execution.check_deployment(output)

    def test_missing_deployment_evidence_fails_closed(self):
        with self.assertRaises(RuntimeError):
            execution.check_deployment("sdk 26.2\nversion 1267.0")
