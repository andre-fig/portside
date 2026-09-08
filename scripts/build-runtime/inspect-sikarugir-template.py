#!/usr/bin/env python3
"""Inspect a pinned upstream reference without extracting, executing or installing it.

This is not a runtime builder, source authentication substitute or release gate.
An upstream binary inventory cannot establish a Portside source-built integration.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import sys
import tarfile


def inspect_template(archive, reference):
    if reference.get("purpose") != "inspection-only; never a commercial build input or download fallback":
        raise ValueError("Expected an inspection-only reference")
    if archive.is_symlink() or not archive.is_file():
        raise ValueError("Reference archive must be a regular file")
    if archive.stat().st_size != reference["size"]:
        raise ValueError("Reference archive size mismatch")
    digest = hashlib.sha256()
    with archive.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
        if digest.hexdigest() != reference["sha256"]:
            raise ValueError("Reference archive checksum mismatch")
        handle.seek(0)
        with tarfile.open(fileobj=handle, mode="r:xz") as bundle:
            root = reference["archiveRoot"]
            members = {}
            for member in bundle:
                path = PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts or "\\" in member.name or not path.parts or path.parts[0] != root:
                    raise ValueError("Unexpected reference archive path")
                name = str(path)
                if name in members:
                    raise ValueError("Duplicate reference archive member")
                members[name] = member

            def regular(relative):
                member = members.get(root + "/" + relative)
                if member is None or not member.isfile():
                    raise ValueError("Missing regular reference component: " + relative)
                return member

            def read(relative):
                member = regular(relative)
                if member.size > 1024 * 1024:
                    raise ValueError("Reference metadata exceeds read limit")
                return bundle.extractfile(member).read()

            info = plistlib.loads(read("Contents/Info.plist"))
            components = {
                "launcher": "Contents/MacOS/Sikarugir",
                "sdk": "Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk",
                "dxmtD3D11x64": "Contents/Frameworks/renderer/dxmt/wine/x86_64-windows/d3d11.dll",
                "dxmtD3D11x86": "Contents/Frameworks/renderer/dxmt/wine/i386-windows/d3d11.dll",
                "dxmtMetalBridge": "Contents/Frameworks/renderer/dxmt/wine/x86_64-unix/winemetal.so",
                "d9vk": "Contents/Frameworks/renderer/d9vk/wine/x86_64-windows/d3d9.dll",
                "moltenVK": "Contents/Frameworks/libMoltenVK.dylib",
                "kosmicKrisp": "Contents/Frameworks/libvulkan_kosmickrisp.dylib",
            }
            for relative in components.values():
                regular(relative)
            icds = {}
            for name in ("MoltenVK_icd.json", "kosmickrisp_mesa_icd.json"):
                value = json.loads(read("Contents/Resources/vulkan/icd.d/" + name))["ICD"]
                icds[name] = {key: value[key] for key in ("api_version", "library_path")}
            return {
                "kind": "SikarugirReferenceInspection",
                "sha256": digest.hexdigest(),
                "templateVersion": info["CFBundleVersion"],
                "minimumMacOS": info["LSMinimumSystemVersion"],
                "entryPoint": info["CFBundleExecutable"],
                "components": components,
                "dxmtVersion": read("Contents/Frameworks/renderer/dxmt/version").decode().strip(),
                "d9vkVersion": read("Contents/Frameworks/renderer/d9vk/version").decode().strip(),
                "configuration": {key: info[key] for key in ("D9VK", "DXVK", "D3DMETAL", "MOLTENVKCX", "Skip Mono", "Skip Gecko")},
                "vulkanICDs": icds,
                "sourceBuildVerified": False,
                "graphicalAcceptance": "not tested",
            }


def main():
    if len(sys.argv) != 2:
        raise ValueError("Usage: inspect-sikarugir-template.py REFERENCE_ARCHIVE")
    root = Path(__file__).resolve().parents[2]
    reference = json.loads((root / "upstream/sikarugir-reference.json").read_text())
    print(json.dumps(inspect_template(Path(sys.argv[1]), reference), indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, tarfile.TarError, plistlib.InvalidFileException):
        sys.exit("Sikarugir reference inspection failed; check the pinned archive and required component layout.")
