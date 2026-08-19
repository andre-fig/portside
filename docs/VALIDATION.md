# Validation plan and current status

The current environment is an Apple silicon Mac (`arm64`) with Xcode 26.2, so native compilation and unit tests are available. Steam and game execution were not claimed because no authorized compatibility runtime is bundled or detected by the repository build.

## Automated status

`swift test` covers architecture/storage checks, secret redaction, HTTPS installer origin, numeric App ID path safety, and the intentional absence of an allowlist/profile requirement.

## Real Steam validation

Pending on a configured test Mac with a licensed runtime:

- first-run setup and cancel/retry;
- Steam installation, login persistence, update, window focus, and safe termination;
- full-library access and install/update/validate/uninstall of an unprofiled Windows game;
- diagnostic export and repair without deleting game files.

## GunZ: The Duel — App ID 3139440

No result is declared yet. Record each of the 30 requested checkpoints separately with status (`success`, `failure`, `not applicable`, or `not tested`), evidence, duration, exit code, and sanitized observation. If anti-cheat prevents a valid session, do not bypass it; classify the result as `Blocked by anti-cheat` only after observing that real failure.

## Control game

Select and document a small, legal, free or demo Windows-only Steam title without kernel-level anti-cheat only if GunZ blocks before graphics/input/audio can be evaluated. The control title must be chosen during the real test run based on current Steam availability; it is not embedded in Portside.
