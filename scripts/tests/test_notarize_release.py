import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).parents[2]


class NotarizationTests(unittest.TestCase):
    def run_release(self, scenario):
        with tempfile.TemporaryDirectory(prefix="portside-notarization-test-") as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            for name in ["notarize_release.sh", "staple_release.sh"]:
                shutil.copy2(ROOT / "scripts" / name, scripts / name)
            build = root / "artifacts with spaces"
            build.mkdir()
            (build / "Portside.app").mkdir()
            (build / "Portside-0.1.40.zip").write_bytes(b"synthetic signed archive")
            tools = root / "tools"
            tools.mkdir()
            mock = tools / "mock"
            mock.write_text("#!" + sys.executable + "\n" + r'''
import json, os, sys
from pathlib import Path
root = Path(os.environ["FIXTURE_ROOT"])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as file:
    file.write(json.dumps([name] + args) + "\n")
scenario = json.loads(os.environ["FIXTURE_SCENARIO"])
if name == "xcrun":
    if args[:2] == ["notarytool", "submit"]:
        print("status: Accepted" if not scenario.get("submissionFailure") else "status: Invalid")
        sys.exit(scenario.get("submissionFailure", 0))
    if args[:2] == ["stapler", "validate"]:
        sys.exit(scenario.get("validationFailure", 0))
    if args[:2] != ["stapler", "staple"]:
        raise RuntimeError("Unexpected xcrun command")
    target = Path(args[2]).suffix
    counter = root / (target + ".attempts")
    attempt = int(counter.read_text()) if counter.exists() else 0
    counter.write_text(str(attempt + 1))
    outcomes = scenario.get(target, [0])
    status = outcomes[min(attempt, len(outcomes) - 1)]
    if status:
        if scenario.get("unrelatedFailure"):
            print("Could not validate ticket")
        else:
            print('CloudKit query for Portside.app failed due to "(null)".')
            print("Could not find base64 encoded ticket in response for fixture")
    sys.exit(status)
if name == "create_dmg.sh":
    Path(args[1]).write_bytes(b"synthetic DMG")
elif name == "ditto":
    Path(args[-1]).write_bytes(b"synthetic notarized ZIP")
elif name not in ["codesign", "spctl", "sleep"]:
    raise RuntimeError("Unexpected tool")
''')
            mock.chmod(0o755)
            for name in ["xcrun", "codesign", "spctl", "sleep", "ditto"]:
                (tools / name).symlink_to(mock)
            (scripts / "create_dmg.sh").symlink_to(mock)
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       FIXTURE_ROOT=str(root), FIXTURE_SCENARIO=json.dumps(scenario), TMPDIR=str(root),
                       PORTSIDE_BUILD_DIR=str(build), PORTSIDE_VERSION="0.1.40", PORTSIDE_NOTARY_PROFILE="fixture")
            for key in ["PORTSIDE_NOTARY_KEY_ID", "PORTSIDE_NOTARY_ISSUER_ID", "PORTSIDE_NOTARY_KEY_PATH"]:
                env.pop(key, None)
            result = subprocess.run([str(scripts / "notarize_release.sh")], env=env, capture_output=True, text=True, timeout=15)
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
            self.assertFalse(list(root.glob("portside-stapler.*")), "Temporary attempt logs must be cleaned up")
            return result.returncode, calls, (build / "Portside-0.1.40-notarized.zip").exists()

    def test_ticket_lookup_recovers_without_resubmitting_and_keeps_validation(self):
        status, calls, archive = self.run_release({".app": [65, 65, 0], ".dmg": [65, 0]})
        self.assertEqual(status, 0)
        self.assertTrue(archive)
        self.assertEqual([c for c in calls if c[0] == "sleep"], [["sleep", "5"], ["sleep", "10"], ["sleep", "5"]])
        self.assertEqual(len([c for c in calls if c[:3] == ["xcrun", "notarytool", "submit"]]), 2)
        self.assertEqual(len([c for c in calls if c[:3] == ["xcrun", "stapler", "validate"]]), 2)
        self.assertTrue(any(c[0] == "codesign" and "--strict" in c for c in calls))
        self.assertTrue(any(c[:2] == ["spctl", "--assess"] for c in calls))

    def test_persistent_lookup_failure_stops_at_five_attempts(self):
        status, calls, archive = self.run_release({".app": [65]})
        self.assertEqual(status, 65)
        self.assertFalse(archive)
        self.assertEqual(len([c for c in calls if c[:3] == ["xcrun", "stapler", "staple"]]), 5)
        self.assertEqual([c[1] for c in calls if c[0] == "sleep"], ["5", "10", "20", "40"])
        self.assertFalse(any(c[0] in ["create_dmg.sh", "ditto", "spctl", "codesign"] for c in calls))

    def test_other_failures_do_not_retry(self):
        for scenario in [{".app": [65], "unrelatedFailure": True}, {".app": [68]}]:
            with self.subTest(scenario=scenario):
                status, calls, archive = self.run_release(scenario)
                self.assertEqual(status, scenario[".app"][0])
                self.assertFalse(archive)
                self.assertFalse(any(c[0] == "sleep" for c in calls))
                self.assertEqual(len([c for c in calls if c[:3] == ["xcrun", "stapler", "staple"]]), 1)

    def test_rejected_submission_never_reaches_stapling(self):
        status, calls, archive = self.run_release({"submissionFailure": 65})
        self.assertEqual(status, 65)
        self.assertFalse(archive)
        self.assertFalse(any(c[:2] == ["xcrun", "stapler"] or c[0] == "sleep" for c in calls))

    def test_failed_ticket_validation_still_blocks_release(self):
        status, calls, archive = self.run_release({"validationFailure": 65})
        self.assertEqual(status, 65)
        self.assertFalse(archive)
        self.assertFalse(any(c[0] in ["sleep", "codesign", "spctl", "create_dmg.sh", "ditto"] for c in calls))
