import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("engine_execution", Path(__file__).parents[1] / "build-runtime/validate-engine-execution.py")
execution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(execution)


class EnginePlatformTests(unittest.TestCase):
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
