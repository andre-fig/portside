# Portside Runtime Host

`PortsideRuntimeHost` is the Portside-owned native executable inside the generated
`PortsideBaseline.app` wrapper. It launches installed Wine or winetricks using
`Foundation.Process` and argument arrays. The host does not download an engine;
winetricks may download its requested component, including Steam from Valve.

The host accepts:

- no arguments: launch the configured Steam executable;
- `--version`: invoke the installed Wine version command;
- `--create-prefix`: initialize the configured prefix with `wineboot`;
- `--winetricks steam`: invoke the vendored Winetricks `steam` verb;
- `--program <windows-path> [arguments...]`: run an explicit Windows program.
- `--launch-id <UUID>` before a command: consume a desktop diagnostic identifier;
  it is never forwarded to Wine or Steam. The template advertises protocol version 1.

[The template](../../runtime/wrapper-template/Contents/Resources/portside-runtime.json)
defines relative engine/prefix/winetricks paths. The host resolves its own bundle
and resource through Foundation, independent of cwd. Production assembly uses
[`build-wrapper.sh`](../../scripts/build-runtime/build-wrapper.sh); installed
prefix persistence is owned by the desktop installer.

Each launch records a sanitized executable/argument summary, monotonic duration,
`terminationStatus`, `terminationReason` (`exit` or `uncaughtSignal`) and signal
number when applicable. Execution errors retain error domain/code, without raw
paths or environment. Signal exits are propagated as `128 + signal`; the receipt
retains the original signal/status. A Wine SIGKILL is therefore distinguishable
from `exit(9)`. The canonical symlink destination supplies `WINEPREFIX`.

For desktop launches, atomic JSON receipts live under the disposable/test or real
home's `Library/Application Support/Portside/Logs/RuntimeLaunches/<UUID>.json`.
The schema matches `PortsideCore.RuntimeLaunchReceipt`. Event-driven output capture
and process termination notifications use no periodic polling. The terminal
receipt precedes a maximum two-second grace period for inherited output. A
`SO_NOSIGPIPE` socket prevents closing capture from signalling descendants; later
writes receive `EPIPE`. These receipts are diagnostics, not runtime authorization.
Arbitrary arguments are redacted; capture is bounded to 64 KiB. Retention keeps
100 historical UUID JSON files for seven days, protecting the current UUID and
the last five minutes for concurrent readers. Symlinks/directories/unrelated files
are excluded. The separate host text log still lacks rotation.

`--create-prefix` defers optional Mono/Gecko registration only in the bootstrap
subprocess, avoiding their modal installers before WoW64 initialization finishes.
No DLL override is persisted or applied to Steam/game launches. The official
Steam verb uses `--winetricks -q steam`; checksums and normal Steam flags remain
unchanged. The production bootstrap probe exercises this host policy directly.

From repository root:

```sh
swift test --package-path apps/runtime-host
swift build --package-path apps/runtime-host
```

Tests include a relocated compiled host with dummy Wine and a disposable home,
immediate zero/nonzero exits, SIGKILL, execution failure, symlinked prefixes,
argument/output redaction and inherited output after the loader exits.
They do not validate Steam or a real graphical window. Signing diagnostics are
informational, and the entitlements resource is not applied by the current
wrapper builder. See [local agent rules](AGENTS.md),
[runtime lifecycle](../../docs/RUNTIME.md), and
[security limits](../../docs/SECURITY.md).
