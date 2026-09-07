import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class HookTests(unittest.TestCase):
    def fixture(self, root):
        source = Path(__file__).parents[1] / "hooks"
        shutil.copytree(source, root / "scripts/hooks")
        (root / "bin").mkdir()
        fake_git = root / "bin/git"
        fake_git.write_text('''#!/bin/sh
case "$1 $2" in
  "diff --check"|"diff --cached")
    case "$*" in *--name-only*) printf '%s\\n' "$FIXTURE_FILES" ;; *) exit 0 ;; esac ;;
  "diff --name-only") printf '%s\\n' "$FIXTURE_FILES" ;;
  "show "*) printf '%s\\n' "$FIXTURE_INDEX" ;;
  *) exit 2 ;;
esac
''')
        fake_git.chmod(0o755)
        for name in ("swift", "actionlint", "python3"):
            tool = root / "bin" / name
            tool.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$FIXTURE_CALLS"\n')
            tool.chmod(0o755)
        policy = root / "scripts/validate-production-policy.sh"
        policy.write_text('#!/bin/sh\nprintf "policy\\n" >> "$FIXTURE_CALLS"\n')
        policy.chmod(0o755)
        return dict(os.environ, PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                    FIXTURE_CALLS=str(root / "calls"))

    def test_precommit_checks_invalid_index_even_when_worktree_is_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self.fixture(root)
            (root / "example.sh").write_text("#!/bin/sh\nexit 0\n")
            env.update(FIXTURE_FILES="example.sh", FIXTURE_INDEX="if then")
            result = subprocess.run(["sh", str(root / "scripts/hooks/pre-commit.sh")], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            env["FIXTURE_INDEX"] = "#!/bin/sh\nexit 0\n"
            result = subprocess.run(["sh", str(root / "scripts/hooks/pre-commit.sh")], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def push(self, files):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self.fixture(root)
            env["FIXTURE_FILES"] = "\n".join(files)
            # Synthetic hook input only: no git push or commit is executed.
            result = subprocess.run(["sh", str(root / "scripts/hooks/pre-push.sh")], env=env,
                                    input="refs/heads/main " + "a" * 40 + " refs/heads/main " + "b" * 40 + "\n",
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            log = root / "calls"
            return log.read_text() if log.exists() else ""

    def test_host_change_runs_both_swift_suites_and_builds(self):
        calls = self.push(["apps/runtime-host/Sources/PortsideRuntimeHost/main.swift"])
        for package in ("desktop", "runtime-host"):
            for command in ("test", "build"):
                self.assertIn("swift " + command + " --package-path apps/" + package, calls)
        self.assertIn("policy", calls)

    def test_workflow_changes_run_local_lint_and_orchestration_tests(self):
        calls = self.push([".github/workflows/build-runtime.yml"])
        self.assertIn("actionlint", calls)
        self.assertIn("python3 -B -m unittest discover -s scripts/tests -v", calls)
        self.assertIn("policy", calls)
        self.assertNotIn("swift", calls)

    def test_docs_and_deleted_json_do_not_start_component_builds(self):
        self.assertEqual(self.push(["docs/RELEASE.md", "deleted.json"]), "")


if __name__ == "__main__":
    unittest.main()
