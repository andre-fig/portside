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

[The template](../../runtime/wrapper-template/Contents/Resources/portside-runtime.json)
defines relative engine/prefix/winetricks paths. The host resolves its own bundle
and resource through Foundation, independent of cwd. Production assembly uses
[`build-wrapper.sh`](../../scripts/build-runtime/build-wrapper.sh); installed
prefix persistence is owned by the desktop installer.

From repository root:

```sh
swift test --package-path apps/runtime-host
swift build --package-path apps/runtime-host
```

Tests include a relocated compiled host with dummy Wine and a disposable home.
They do not validate Steam or a real graphical window. Signing diagnostics are
informational, and the entitlements resource is not applied by the current
wrapper builder. See [local agent rules](AGENTS.md),
[runtime lifecycle](../../docs/RUNTIME.md), and
[security limits](../../docs/SECURITY.md).
