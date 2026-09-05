# Contributing to Portside

Read [AGENTS.md](AGENTS.md), the applicable local instructions and
[the development guide](docs/DEVELOPER_GUIDE.md). Preserve existing work and
use the smallest coherent change to satisfy the task.

## Change review

- Put reusable desktop behavior in PortsideCore, UI orchestration in Portside,
  backend use cases in services and DTOs/specs beside their modules.
- Schema changes require a reviewed Prisma migration. Upstream changes require
  lock, source/license checksum and notice review; never patch vendor by hand.
- Preserve user data and trust checks. Do not turn a passing checksum, process
  or CI run into a claim of approved release or graphical compatibility.
- Update relevant documentation with code, STATUS when evidence changes and
  DECISIONS when architecture changes. Keep Portside UI and docs in English.

Use [TESTING](docs/TESTING.md) for the exact checks. A reviewable change records
the problem, resulting behavior, modified areas, commands/results, risks and
remaining manual validation. Check `git diff` and `git diff --check`, including
the absence of credentials, user data and generated outputs.

## Authority

Commit, push, merge, deploy, external writes, release and promotion need explicit
task authorization. Agents must not independently promote releases. Existing
automatic workflows and their limitations are documented in [RELEASE](docs/RELEASE.md).
Legal and graphical acceptance cannot be inferred from workflow configuration.

Keep vulnerability evidence sanitized; do not publish credentials, account data
or an exploit report to a public issue. Use an authorized private reporting path.
