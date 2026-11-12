"""Offline replacement and rollback tests using disposable app-bundle fixtures."""

import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "replace-app.py"


class ReplaceAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("vyron_replace_app_test", SCRIPT)
        cls.module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.module
        spec.loader.exec_module(cls.module)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vyron-replace-app-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.project = self.base / "Project"
        self.home = self.base / "Home"
        self.applications = self.base / "Applications"
        self.trash = self.base / "Trash"
        for directory in [
            self.project / ".build", self.home / "Desktop", self.home / "Applications", self.applications, self.trash
        ]:
            directory.mkdir(parents=True)
        self.stage = self.project / ".build" / "staging" / "Vyron.app"
        self.target = self.applications / "Vyron.app"

    @staticmethod
    def bundle(path, marker="old", identifier="ai.vyron.desktop", package_type="APPL", executable="Vyron"):
        contents = path / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier,
            "CFBundlePackageType": package_type,
            "CFBundleExecutable": executable,
        }))
        binary = contents / "MacOS" / executable
        binary.write_bytes(b"Disposable test executable; never launched.\n")
        binary.chmod(0o755)
        (path / "fixture-marker.txt").write_text(marker, encoding="utf-8")
        return path

    @staticmethod
    def marker(path):
        return (path / "fixture-marker.txt").read_text(encoding="utf-8")

    def discover(self, **overrides):
        arguments = {
            "project": self.project,
            "home": self.home,
            "applications": self.applications,
            "staged_app": self.stage,
        }
        arguments.update(overrides)
        return self.module.previous_apps(**arguments)

    def test_verified_bundle_and_legal_resource_symlink_are_accepted(self):
        app = self.bundle(self.home / "Desktop" / "Verified.app")
        external = self.base / "resource.txt"
        external.write_text("Preserve this external resource.", encoding="utf-8")
        resources = app / "Contents" / "Resources"
        resources.mkdir()
        (resources / "linked-resource.txt").symlink_to(external)

        self.assertTrue(self.module.is_vyron_app(app))
        self.assertEqual(external.read_text(encoding="utf-8"), "Preserve this external resource.")

    def test_same_name_without_exact_bundle_identity_and_executable_is_rejected(self):
        for name, metadata in [
            ("identifier", {"identifier": "example.unrelated"}),
            ("package", {"package_type": "BNDL"}),
            ("executable", {"executable": "Other"}),
        ]:
            with self.subTest(name=name):
                app = self.bundle(self.base / name / "Vyron.app", **metadata)
                self.assertFalse(self.module.is_vyron_app(app))
        missing = self.bundle(self.base / "missing" / "Vyron.app")
        (missing / "Contents" / "MacOS" / "Vyron").unlink()
        self.assertFalse(self.module.is_vyron_app(missing))
        malformed = self.bundle(self.base / "malformed" / "Vyron.app")
        (malformed / "Contents" / "Info.plist").write_bytes(b"Not a property list.")
        self.assertFalse(self.module.is_vyron_app(malformed))

    def test_bundle_root_ancestor_and_critical_content_symlinks_are_rejected(self):
        real = self.bundle(self.base / "real" / "Vyron.app")
        alias = self.base / "Alias.app"
        alias.symlink_to(real, target_is_directory=True)
        self.assertFalse(self.module.is_vyron_app(alias))
        ancestor = self.base / "LinkedParent"
        ancestor.symlink_to(real.parent, target_is_directory=True)
        self.assertFalse(self.module.is_vyron_app(ancestor / real.name))
        for index, relative in enumerate([
            "Contents", "Contents/Info.plist", "Contents/MacOS", "Contents/MacOS/Vyron"
        ]):
            with self.subTest(relative=relative):
                app = self.bundle(self.base / ("critical-" + str(index)) / "Vyron.app")
                critical = app / relative
                moved = self.base / ("external-critical-" + str(index))
                critical.rename(moved)
                critical.symlink_to(moved, target_is_directory=moved.is_dir())
                self.assertFalse(self.module.is_vyron_app(app))
                self.assertTrue(moved.exists())

    def test_discovery_is_scoped_prunes_app_bundles_and_excludes_entire_staging_directory(self):
        expected = [
            self.bundle(self.project / ".build" / "debug" / "Old.app"),
            self.bundle(self.home / "Desktop" / "Vyron older.app"),
            self.bundle(self.home / "Applications" / "Vyron.app"),
            self.bundle(self.target),
        ]
        self.bundle(self.stage, marker="new")
        staging_sibling = self.bundle(self.stage.parent / "Another staged copy.app")
        unrelated = self.bundle(self.home / "Desktop" / "Vyron.app", identifier="example.unrelated")
        another_project = self.bundle(self.home / "Desktop" / "AnotherProject" / ".build" / "Vyron.app")
        host = self.bundle(self.project / ".build" / "Host.app", identifier="example.host")
        embedded = self.bundle(host / "Contents" / "Resources" / "Vyron.app")

        found = self.discover()

        self.assertEqual(set(found), set(expected))
        self.assertEqual(len(found), len(expected))
        for excluded in [self.stage, staging_sibling, unrelated, another_project, embedded]:
            self.assertNotIn(excluded, found)

    def test_discovery_does_not_follow_symlink_search_roots_or_build_subdirectories(self):
        external_project = self.base / "ExternalProject"
        external_home = self.base / "ExternalHome"
        external_apps = self.base / "ExternalApps"
        self.bundle(external_project / ".build" / "Vyron.app")
        self.bundle(external_home / "Desktop" / "Vyron.app")
        self.bundle(external_home / "Applications" / "Vyron.app")
        self.bundle(external_apps / "Vyron.app")
        aliases = [self.base / "ProjectAlias", self.base / "HomeAlias", self.base / "AppsAlias"]
        for alias, destination in zip(aliases, [external_project, external_home, external_apps]):
            alias.symlink_to(destination, target_is_directory=True)
        self.assertEqual(self.discover(project=aliases[0], home=aliases[1], applications=aliases[2]), [])
        (self.project / ".build" / "LinkedBuild").symlink_to(external_apps, target_is_directory=True)
        self.assertEqual(self.discover(), [])

    def test_success_moves_only_previous_bundles_to_unique_trash_names_and_installs_stage(self):
        self.bundle(self.stage, marker="new")
        old_apps = [
            self.bundle(self.project / ".build" / "app" / "Vyron.app", marker="project-old"),
            self.bundle(self.home / "Desktop" / "Vyron.app", marker="desktop-old"),
            self.bundle(self.target, marker="installed-old"),
        ]
        existing_trash = self.bundle(self.trash / "Vyron.app", marker="already-in-trash")
        history = self.home / "Library" / "Application Support" / "VyronAI"
        history.mkdir(parents=True)
        protected = {
            history / "conversations.json": b"Saved conversation fixture",
            history / "model-connections.json": b"Saved connection fixture",
            history / "sidebar.json": b"Saved sidebar fixture",
            self.project / "README.md": b"Keep project sources",
            self.project / ".build" / "keep.txt": b"Keep unrelated build output",
        }
        for path, content in protected.items():
            path.write_bytes(content)
        other_project = self.bundle(
            self.home / "Desktop" / "AnotherProject" / ".build" / "Vyron.app", marker="other-project"
        )
        unrelated = self.bundle(self.home / "Applications" / "Vyron.app", identifier="example.unrelated")

        self.module.replace_apps(self.stage, self.target, old_apps, self.trash)

        self.assertFalse(self.stage.exists())
        self.assertTrue(self.module.is_vyron_app(self.target))
        self.assertEqual(self.marker(self.target), "new")
        self.assertFalse(old_apps[0].exists())
        self.assertFalse(old_apps[1].exists())
        self.assertEqual(self.marker(existing_trash), "already-in-trash")
        trashed_markers = {self.marker(path) for path in self.trash.iterdir()}
        self.assertEqual(trashed_markers, {"project-old", "desktop-old", "installed-old", "already-in-trash"})
        self.assertEqual(len(list(self.trash.iterdir())), 4)
        for path, content in protected.items():
            self.assertEqual(path.read_bytes(), content)
        self.assertEqual(self.marker(other_project), "other-project")
        self.assertTrue(unrelated.exists())

    def test_invalid_stage_leaves_previous_apps_and_trash_untouched(self):
        self.bundle(self.stage, marker="invalid", identifier="example.unrelated")
        old = self.bundle(self.target, marker="old")

        with self.assertRaises((RuntimeError, OSError)):
            self.module.replace_apps(self.stage, self.target, [old], self.trash)

        self.assertEqual(self.marker(old), "old")
        self.assertEqual(self.marker(self.stage), "invalid")
        self.assertEqual(list(self.trash.iterdir()), [])

    def test_unrelated_existing_target_is_never_overwritten(self):
        self.bundle(self.stage, marker="new")
        self.bundle(self.target, marker="unrelated-target", identifier="example.unrelated")
        old = self.bundle(self.home / "Desktop" / "Old.app", marker="old")

        with self.assertRaises((RuntimeError, OSError)):
            self.module.replace_apps(self.stage, self.target, [old], self.trash)

        self.assertEqual(self.marker(self.target), "unrelated-target")
        self.assertEqual(self.marker(old), "old")
        self.assertEqual(self.marker(self.stage), "new")
        self.assertEqual(list(self.trash.iterdir()), [])

    def test_unverified_old_app_list_is_rejected_before_any_bundle_is_moved(self):
        self.bundle(self.stage, marker="new")
        old = self.bundle(self.home / "Desktop" / "Old.app", marker="old")
        unrelated = self.bundle(self.home / "Applications" / "Other.app", identifier="example.unrelated")

        with self.assertRaises((RuntimeError, OSError)):
            self.module.replace_apps(self.stage, self.target, [old, unrelated], self.trash)

        self.assertTrue(old.exists())
        self.assertTrue(unrelated.exists())
        self.assertTrue(self.stage.exists())
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.trash.iterdir()), [])

    def test_symlink_target_and_target_ancestor_are_rejected_without_following_them(self):
        self.bundle(self.stage, marker="new")
        external = self.bundle(self.base / "Elsewhere" / "Vyron.app", marker="external")
        self.target.symlink_to(external, target_is_directory=True)
        old = self.bundle(self.home / "Desktop" / "Old.app", marker="old")
        with self.assertRaises((RuntimeError, OSError)):
            self.module.replace_apps(self.stage, self.target, [old], self.trash)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(self.marker(external), "external")
        self.target.unlink()
        alias = self.base / "ApplicationsAlias"
        alias.symlink_to(self.applications, target_is_directory=True)
        with self.assertRaises((RuntimeError, OSError)):
            self.module.replace_apps(self.stage, alias / "Vyron.app", [old], self.trash)
        self.assertTrue(old.exists())
        self.assertTrue(self.stage.exists())
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.trash.iterdir()), [])

    def test_linked_old_app_or_stage_as_old_app_cannot_be_moved(self):
        self.bundle(self.stage, marker="new")
        old = self.bundle(self.base / "OldContainer" / "Vyron.app", marker="old")
        alias = self.base / "LinkedOldContainer"
        alias.symlink_to(old.parent, target_is_directory=True)
        for candidate in [alias / old.name, self.stage]:
            with self.subTest(candidate=candidate):
                with self.assertRaises((RuntimeError, OSError)):
                    self.module.replace_apps(self.stage, self.target, [candidate], self.trash)
                self.assertTrue(old.exists())
                self.assertTrue(self.stage.exists())
                self.assertFalse(self.target.exists())
                self.assertEqual(list(self.trash.iterdir()), [])

    def test_late_install_rename_failure_rolls_back_all_old_bundles(self):
        self.bundle(self.stage, marker="new")
        old_apps = [
            self.bundle(self.home / "Desktop" / "Vyron.app", marker="desktop-old"),
            self.bundle(self.target, marker="installed-old"),
        ]
        real_rename = os.rename
        attempted_install = []

        def fail_only_install(source, destination, *args, **kwargs):
            if Path(source) == self.stage and Path(destination) == self.target:
                attempted_install.append(True)
                self.assertFalse(old_apps[0].exists())
                self.assertFalse(old_apps[1].exists())
                self.assertEqual(len(list(self.trash.iterdir())), 2)
                raise OSError("Injected late installation rename failure")
            return real_rename(source, destination, *args, **kwargs)

        with mock.patch.object(self.module.os, "rename", side_effect=fail_only_install):
            with self.assertRaises((RuntimeError, OSError)):
                self.module.replace_apps(self.stage, self.target, old_apps, self.trash)

        self.assertEqual(attempted_install, [True])
        self.assertEqual(self.marker(old_apps[0]), "desktop-old")
        self.assertEqual(self.marker(old_apps[1]), "installed-old")
        self.assertEqual(self.marker(self.stage), "new")
        self.assertEqual(list(self.trash.iterdir()), [])

    def test_symlink_trash_directory_is_rejected_without_redirecting_old_bundles(self):
        self.bundle(self.stage, marker="new")
        old = self.bundle(self.target, marker="old")
        external_trash = self.base / "ExternalTrash"
        external_trash.mkdir()
        linked_trash = self.base / "LinkedTrash"
        linked_trash.symlink_to(external_trash, target_is_directory=True)

        with self.assertRaises((RuntimeError, OSError)):
            self.module.replace_apps(self.stage, self.target, [old], linked_trash)

        self.assertEqual(self.marker(old), "old")
        self.assertEqual(self.marker(self.stage), "new")
        self.assertEqual(list(external_trash.iterdir()), [])

    def test_main_refuses_running_app_or_failed_process_check_before_build_or_replacement(self):
        old = self.bundle(self.project / ".build" / "app" / "Vyron.app", marker="installed-old")
        for status in [0, 2]:
            with self.subTest(status=status):
                with mock.patch.object(self.module, "__file__", str(self.project / "scripts" / "replace-app.py")):
                    with mock.patch.object(sys, "argv", ["replace-app.py"]):
                        with mock.patch.object(self.module.Path, "home", return_value=self.home):
                            with mock.patch.object(self.module.subprocess, "run", return_value=
                                                   subprocess.CompletedProcess([], status)) as run:
                                with mock.patch.object(self.module, "replace_apps") as replace:
                                    with self.assertRaises(RuntimeError):
                                        self.module.main()
                                replace.assert_not_called()
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.args[0], ["/usr/bin/pgrep", "-x", "Vyron"])
                self.assertEqual(self.marker(old), "installed-old")
                self.assertEqual(list(self.trash.iterdir()), [])

    def test_main_build_failure_preserves_old_app_and_never_attempts_replacement(self):
        old = self.bundle(self.project / ".build" / "app" / "Vyron.app", marker="installed-old")

        def fail_build(arguments, **kwargs):
            if arguments[0] == "/usr/bin/pgrep":
                return subprocess.CompletedProcess(arguments, 1)
            if arguments[0] == "/bin/zsh":
                raise subprocess.CalledProcessError(1, arguments)
            self.fail("Unexpected external command in the mocked build-failure path: " + repr(arguments))

        with mock.patch.object(self.module, "__file__", str(self.project / "scripts" / "replace-app.py")):
            with mock.patch.object(sys, "argv", ["replace-app.py"]):
                with mock.patch.object(self.module.Path, "home", return_value=self.home):
                    with mock.patch.object(self.module.subprocess, "run", side_effect=fail_build) as run:
                        with mock.patch.object(self.module, "replace_apps") as replace:
                            with self.assertRaises(subprocess.CalledProcessError):
                                self.module.main()
                        replace.assert_not_called()

        self.assertEqual(run.call_count, 2)
        self.assertEqual(self.marker(old), "installed-old")
        self.assertEqual(list(self.trash.iterdir()), [])

    def test_build_script_rejects_lexical_output_escape_before_any_build_command(self):
        outside = self.base / "outside"
        outside.mkdir()
        protected = outside / "keep.txt"
        protected.write_bytes(b"Preserve outside project data.")
        output = str(self.project / ".build" / ".." / ".." / "outside" / "Vyron.app")

        self.assert_early_output_rejection(
            output, "Choose a new Vyron.app output folder inside this project's .build directory."
        )

        self.assertEqual(protected.read_bytes(), b"Preserve outside project data.")
        self.assertFalse((outside / "Vyron.app").exists())

    def test_build_script_rejects_symlink_output_parent_before_any_build_command(self):
        outside = self.base / "outside"
        outside.mkdir()
        protected = outside / "keep.txt"
        protected.write_bytes(b"Preserve linked destination data.")
        link = self.project / ".build" / "link"
        link.symlink_to(outside, target_is_directory=True)

        self.assert_early_output_rejection(
            str(link / "Vyron.app"), "The app output folder must not contain symbolic links."
        )

        self.assertEqual(protected.read_bytes(), b"Preserve linked destination data.")
        self.assertFalse((outside / "Vyron.app").exists())

    def assert_early_output_rejection(self, output, expected_error):
        fixture_script = self.project / "scripts" / "build-app.sh"
        fixture_script.parent.mkdir()
        fixture_script.write_bytes(SCRIPT.with_name("build-app.sh").read_bytes())
        tool_directory = self.base / "mock-build-tools"
        tool_directory.mkdir()
        invocations = self.base / "unexpected-build-commands.txt"
        for name in ["python3", "swift", "codesign"]:
            stub = tool_directory / name
            stub.write_text(
                '#!/bin/zsh\nprint -r -- invoked >> "$VYRON_TEST_INVOCATIONS"\nexit 97\n', encoding="utf-8"
            )
            stub.chmod(0o755)
        environment = dict(os.environ)
        environment["PATH"] = str(tool_directory) + ":/usr/bin:/bin"
        environment["VYRON_TEST_INVOCATIONS"] = str(invocations)

        result = subprocess.run(
            ["/bin/zsh", str(fixture_script), "debug", output], cwd=self.project,
            capture_output=True, text=True, timeout=10, env=environment,
        )

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(expected_error, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(invocations.exists(), "Output validation must precede resource generation and building.")


if __name__ == "__main__":
    unittest.main()
