# Update architecture entry point

Two update paths have distinct owners:

- [ARCHITECTURE](ARCHITECTURE.md): installation gate, awaited Sparkle preflight,
  relaunch receipt, licensing/bootstrap, agent handoff and runtime activity lease.
- [RUNTIME](RUNTIME.md): authenticated manifest discovery, artifact preparation,
  prefix lifetime and runtime replacement/recovery limits.

[SECURITY](SECURITY.md) defines signed minimum-version/downgrade rules.
[RELEASE](RELEASE.md) defines appcast/runtime publication.
[BOOTSTRAP_VALIDATION](BOOTSTRAP_VALIDATION.md) retains the concrete validation
protocol and historical installation/probe report.

Former claims of guaranteed atomic runtime recovery, three-version retention
and universal GUI gating are superseded by those code-grounded descriptions.
No staging service, validated rollback or successful update is inferred here.
