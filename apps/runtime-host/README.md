# Portside Runtime Host

`PortsideRuntimeHost` is the Portside-owned native executable placed inside
each generated wrapper. It launches the locally installed Wine engine and
Winetricks using `Foundation.Process` and argument arrays. It never invokes a
shell command string and never downloads an executable.

The host accepts:

- no arguments: launch the configured Steam executable;
- `--create-prefix`: initialize the configured prefix with `wineboot`;
- `--winetricks steam`: invoke the vendored Winetricks `steam` verb;
- `--program <windows-path> [arguments...]`: run an explicit Windows program.

`runtime/wrapper-template` contains only the versioned app skeleton and
configuration. The Wine engine, winetricks source and prefix are supplied by
the Portside build/installation pipeline.
