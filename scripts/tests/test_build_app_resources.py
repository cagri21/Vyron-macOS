"""Offline packaging regression for both SwiftPM bundle layouts."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "build-app.sh"


class BuildAppResourceTests(unittest.TestCase):
    def test_packaging_copies_the_current_palette_chrome_host_and_office_helper(self):
        for native_metadata in (False, True):
            with self.subTest(native_metadata=native_metadata), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                project = root / "Project"
                scripts = project / "scripts"
                scripts.mkdir(parents=True)
                script = scripts / "build-app.sh"
                script.write_bytes(SCRIPT.read_bytes())
                binary = project / ".build/mock-debug"
                bundle = binary / "Vyron_Vyron.bundle"
                bundle.mkdir(parents=True)
                (binary / "Vyron").write_bytes(b"fixture executable; never launched")
                chrome_host = binary / "VyronChromeHost"
                chrome_host.write_bytes(b"fixture Chrome host; never launched")
                chrome_host.chmod(0o755)
                core_bundle = binary / "Vyron_VyronCore.bundle"
                core_resources = core_bundle / "Contents/Resources" if native_metadata else core_bundle
                core_resources.mkdir(parents=True)
                office_helper = core_resources / "vyron_office.py"
                office_helper.write_bytes(b"# fixture Office helper")
                shared_bundle = binary / "Vyron_VyronLocalization.bundle"
                shared_resources = shared_bundle / "Contents/Resources" if native_metadata else shared_bundle
                shared_strings = shared_resources / "tr.lproj/Localizable.strings"
                shared_strings.parent.mkdir(parents=True)
                shared_strings.write_text('"projectApprovalDefaultReviewReason" = "İnceleyin.";')
                if native_metadata:
                    (bundle / "Contents").mkdir()
                    (bundle / "Contents/Info.plist").write_text("fixture bundle metadata")
                    (core_bundle / "Contents/Info.plist").write_text("fixture Core bundle metadata")
                    (shared_bundle / "Contents/Info.plist").write_text("fixture localization bundle metadata")
                compiled_asset = bundle / "Theme.xcassets/EffortAccent.colorset/Contents.json"
                compiled_asset.parent.mkdir(parents=True)
                compiled_asset.write_bytes(b"old compiled palette")
                canonical = project / "Apps/Vyron/Resources/Theme.xcassets"
                canonical_asset = canonical / "EffortAccent.colorset/Contents.json"
                canonical_asset.parent.mkdir(parents=True)
                canonical_asset.write_bytes(b"current sampled purple palette")
                (project / "Resources").mkdir()
                (project / "Resources/Info.plist").write_text("fixture app metadata")
                for language in ("en", "tr", "uk"):
                    localization = canonical.parent / f"{language}.lproj"
                    localization.mkdir()
                    (localization / "InfoPlist.strings").write_text("fixture localization")
                tools = root / "mock-tools"
                tools.mkdir()
                for name, content in {
                    "python3": "#!/bin/zsh\nexit 0\n",
                    "swift": (
                        '#!/bin/zsh\nif [[ "$*" == *"--show-bin-path"* ]]; then\n'
                        '    print -r -- "$VYRON_TEST_BINARY"\nfi\n'
                    ),
                    "codesign": "#!/bin/zsh\nexit 0\n",
                }.items():
                    tool = tools / name
                    tool.write_text(content)
                    tool.chmod(0o755)
                environment = dict(os.environ)
                environment["PATH"] = str(tools) + ":/usr/bin:/bin"
                environment["VYRON_TEST_BINARY"] = str(binary)
                app = project / ".build/review/Vyron.app"
                result = subprocess.run(
                    ["/bin/zsh", str(script), "debug", str(app)], cwd=project,
                    capture_output=True, text=True, env=environment, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                packaged = app / "Contents/Resources/Vyron_Vyron.bundle"
                active = packaged / "Contents/Resources" if native_metadata else packaged
                self.assertEqual(
                    (active / "Theme.xcassets/EffortAccent.colorset/Contents.json").read_bytes(),
                    canonical_asset.read_bytes(),
                )
                self.assertEqual(compiled_asset.read_bytes(), b"old compiled palette")
                packaged_host = app / "Contents/MacOS/VyronChromeHost"
                self.assertEqual(packaged_host.read_bytes(), chrome_host.read_bytes())
                self.assertTrue(os.access(packaged_host, os.X_OK))
                packaged_helper = app / "Contents/Resources" / office_helper.relative_to(binary)
                self.assertEqual(packaged_helper.read_bytes(), office_helper.read_bytes())
                packaged_strings = app / "Contents/Resources" / shared_strings.relative_to(binary)
                self.assertEqual(packaged_strings.read_bytes(), shared_strings.read_bytes())


if __name__ == "__main__":
    unittest.main()
