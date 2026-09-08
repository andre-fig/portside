import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[2]
spec = importlib.util.spec_from_file_location("wine_patches", ROOT / "scripts/build-runtime/apply-wine-patches.py")
patches = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patches)


class WinePatchTests(unittest.TestCase):
    def fixture(self, root):
        shutil.copytree(ROOT / "upstream/patches/wine", root / "upstream/patches/wine")
        shutil.copyfile(ROOT / "upstream/lock.json", root / "upstream/lock.json")
        source = root / "build/control/work/wine/source"
        target = source / "dlls/ntdll/unix/loader.c"
        target.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "vendor/wine/dlls/ntdll/unix/loader.c", target)
        return source, target

    def test_verified_patch_applies_once_without_changing_vendor(self):
        vendor = ROOT / "vendor/wine/dlls/ntdll/unix/loader.c"
        before = hashlib.sha256(vendor.read_bytes()).digest()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, target = self.fixture(root)
            patches.apply(source, root)
            self.assertIn('getenv( "WINEDLLPATH_PREPEND" )', target.read_text())
            with self.assertRaisesRegex(RuntimeError, "apply cleanly"):
                patches.apply(source, root)
        self.assertEqual(before, hashlib.sha256(vendor.read_bytes()).digest())

    def test_source_identity_patch_bytes_and_unlisted_files_fail_closed(self):
        for change in ("source", "checksum", "extra", "traversal", "duplicate"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root)
                directory = root / "upstream/patches/wine"
                manifest = directory / "series.json"
                value = json.loads(manifest.read_text())
                if change == "source": value["sourceCommit"] = "0" * 40
                elif change == "checksum": (directory / value["patches"][0]["file"]).write_text("altered")
                elif change == "extra": (directory / "9999-unlisted.patch").write_text("unlisted")
                elif change == "traversal": value["patches"][0]["file"] = "../escape.patch"
                else: value["patches"].append(value["patches"][0])
                manifest.write_text(json.dumps(value))
                with self.assertRaises(RuntimeError): patches.verified_series(root)

    def test_vendor_and_external_source_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, _ = self.fixture(root)
            vendor = root / "vendor/work/wine/source"
            vendor.mkdir(parents=True)
            for path in (vendor, root.parent):
                with self.assertRaisesRegex(RuntimeError, "disposable"):
                    patches.apply(path, root)

    @unittest.skipUnless(shutil.which("cc"), "A native C compiler is needed for the loader function control")
    def test_actual_patched_function_preserves_defaults_and_orders_absolute_overlays(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, target = self.fixture(root)
            patches.apply(source, root)
            text = target.read_text()
            function = text[text.index("static void set_dll_path(void)"):text.index("static void set_system_dll_path(void)")]
            control = root / "control.c"
            control.write_text('''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define max(a,b) ((a) > (b) ? (a) : (b))
static const char **dll_paths, *dll_dir = "/engine", *build_dir;
static size_t dll_path_maxlen;
''' + function + '\nint main(void) { set_dll_path(); for (int i=0; dll_paths[i]; i++) puts(dll_paths[i]); return 0; }\n')
            executable = root / "control"
            subprocess.run(["cc", "-Wall", "-Wextra", str(control), "-o", str(executable)], check=True, capture_output=True)
            cases = [
                ({}, ["/engine"]),
                ({"WINEDLLPATH_PREPEND": "", "WINEDLLPATH": "/after"}, ["/engine", "/after"]),
                ({"WINEDLLPATH_PREPEND": "/dxmt:/extra", "WINEDLLPATH": "/after:/last"}, ["/dxmt", "/extra", "/engine", "/after", "/last"]),
                ({"WINEDLLPATH_PREPEND": ":/has spaces::relative:.:/last:"}, ["/has spaces", "/last", "/engine"]),
                ({"WINEDLLPATH_PREPEND": ":::"}, ["/engine"]),
            ]
            for variables, expected in cases:
                env = {key: value for key, value in os.environ.items() if key not in ("WINEDLLPATH", "WINEDLLPATH_PREPEND")}
                env.update(variables)
                with self.subTest(variables=variables):
                    result = subprocess.run([str(executable)], env=env, capture_output=True, text=True, check=True)
                    self.assertEqual(result.stdout.splitlines(), expected)
