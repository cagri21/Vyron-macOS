import base64
from contextlib import redirect_stdout
from importlib.util import module_from_spec, spec_from_file_location
from io import StringIO
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
SPEC = spec_from_file_location("vyron_local_auth_setup", ROOT / "scripts/local-auth.py")
setup = module_from_spec(SPEC)
SPEC.loader.exec_module(setup)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local_auth.__main__ import read_bootstrap_token


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name).resolve() / "private auth"
        self.previous_umask = os.umask(0o077)

    def tearDown(self):
        os.umask(self.previous_umask)
        self.temporary.cleanup()

    def test_setup_creates_private_files_once_and_preserves_them_on_reinstall(self):
        setup.prepare(self.directory)
        token_path = self.directory / "bootstrap.token"
        config_path = self.directory / "config.json"
        token = token_path.read_bytes()
        config = config_path.read_bytes()
        self.assertEqual(json.loads(config), {"schema_version": 1, "endpoint": "http://127.0.0.1:8327"})
        self.assertEqual(len(base64.urlsafe_b64decode(token.strip() + b"=")), 32)
        self.assertEqual(stat.S_IMODE(token_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(config_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        setup.prepare(self.directory)
        self.assertEqual(token_path.read_bytes(), token)
        self.assertEqual(config_path.read_bytes(), config)
        self.assertEqual(read_bootstrap_token(token_path).encode(), token.strip())

    def test_invalid_existing_files_are_preserved_without_partial_configuration(self):
        self.directory.mkdir(mode=0o700)
        token = self.directory / "bootstrap.token"
        token.write_bytes(b"invalid-existing-token")
        token.chmod(0o600)
        with self.assertRaises(setup.SetupError):
            setup.prepare(self.directory)
        self.assertEqual(token.read_bytes(), b"invalid-existing-token")
        self.assertFalse((self.directory / "config.json").exists())

    def test_insecure_files_and_symlinked_paths_are_rejected(self):
        setup.prepare(self.directory)
        token = self.directory / "bootstrap.token"
        original = token.read_bytes()
        token.chmod(0o644)
        with self.assertRaises(setup.SetupError):
            setup.prepare(self.directory)
        with self.assertRaises(ValueError):
            read_bootstrap_token(token)
        token.chmod(0o600)
        alias = Path(self.temporary.name).resolve() / "alias"
        alias.symlink_to(self.directory, target_is_directory=True)
        with self.assertRaises(setup.SetupError):
            setup.prepare(alias)
        token.unlink()
        target = self.directory / "another-file"
        target.write_bytes(original)
        token.symlink_to(target)
        with self.assertRaises(setup.SetupError):
            setup.prepare(self.directory)
        self.assertEqual(target.read_bytes(), original)

    def test_invalid_configuration_is_never_replaced(self):
        setup.prepare(self.directory)
        config = self.directory / "config.json"
        for invalid in (b'{"schema_version":true,"endpoint":"http://127.0.0.1:8327"}',
                        b'{"schema_version":1,"endpoint":"https://remote.example.test"}',
                        b'{"schema_version":1,"schema_version":1,"endpoint":"http://127.0.0.1:8327"}'):
            config.write_bytes(invalid)
            with self.assertRaises(setup.SetupError):
                setup.prepare(self.directory)
            self.assertEqual(config.read_bytes(), invalid)

    def test_dry_run_does_not_write_read_secrets_or_invoke_docker(self):
        output = StringIO()
        with mock.patch.object(setup.subprocess, "run", side_effect=AssertionError("No Docker in dry-run")), \
            mock.patch.object(setup, "default_directory", side_effect=AssertionError("Use only isolated test path")), \
            redirect_stdout(output):
            result = setup.main(["start", "--data-dir", str(self.directory), "--dry-run"])
        self.assertEqual(result, 0)
        self.assertFalse(self.directory.exists())
        self.assertTrue(json.loads(output.getvalue())["dry_run"])
        setup.prepare(self.directory)
        with mock.patch.object(setup.os, "fdopen", side_effect=AssertionError("Do not read existing tokens")), \
            redirect_stdout(StringIO()):
            self.assertEqual(setup.main(["start", "--data-dir", str(self.directory), "--dry-run"]), 0)

    def test_daemon_failure_keeps_config_marker_and_bootstrap_for_later_retry(self):
        output = StringIO()
        with mock.patch.object(setup.shutil, "which", return_value="/mock/docker"), \
            mock.patch.object(setup, "require_local_docker", side_effect=setup.SetupError("Docker is unavailable.")), \
            redirect_stdout(output):
            self.assertEqual(setup.main(["start", "--data-dir", str(self.directory)]), 1)
            first = (self.directory / "bootstrap.token").read_bytes()
            self.assertEqual(setup.main(["start", "--data-dir", str(self.directory)]), 1)
        self.assertTrue((self.directory / "config.json").exists())
        self.assertEqual((self.directory / "bootstrap.token").read_bytes(), first)
        self.assertNotIn(first.decode().strip(), output.getvalue())

    def test_only_docker_location_settings_and_token_file_path_are_forwarded(self):
        with mock.patch.dict(os.environ, {
            "HOME": str(self.directory), "PATH": "/mock/bin", "OPENAI_API_KEY": "fake-secret",
            "ANTHROPIC_API_KEY": "fake-secret-2", "DOCKER_CONTEXT": "local"
        }, clear=True):
            environment = setup.docker_environment(self.directory)
        self.assertNotIn("OPENAI_API_KEY", environment)
        self.assertNotIn("ANTHROPIC_API_KEY", environment)
        self.assertEqual(environment["VYRON_LOCAL_UID"], str(os.getuid()))
        self.assertEqual(environment["VYRON_LOCAL_AUTH_TOKEN_FILE"], str(self.directory / "bootstrap.token"))

    def test_remote_docker_hosts_and_contexts_are_rejected(self):
        with mock.patch.object(setup.subprocess, "run") as run:
            with self.assertRaises(setup.SetupError):
                setup.require_local_docker("/mock/docker", {"DOCKER_HOST": "tcp://remote.example.test:2376"})
            run.assert_not_called()
        result = SimpleNamespace(returncode=0, stdout='"ssh://remote.example.test"')
        with mock.patch.object(setup.subprocess, "run", return_value=result):
            with self.assertRaises(setup.SetupError):
                setup.require_local_docker("/mock/docker", {})

    def test_explicit_start_and_stop_use_absolute_compose_paths_and_preserve_files(self):
        context = SimpleNamespace(returncode=0, stdout='"unix:///mock/docker.sock"')
        complete = SimpleNamespace(returncode=0, stdout="")
        with mock.patch.object(setup.shutil, "which", return_value="/mock/docker"), \
            mock.patch.object(setup.subprocess, "run", side_effect=[context, complete, context, complete]) as run, \
            mock.patch.object(setup, "healthy", return_value=True):
            self.assertEqual(setup.execute("start", self.directory, 1)["status"], "healthy")
            token = (self.directory / "bootstrap.token").read_bytes()
            self.assertEqual(setup.execute("stop", self.directory, 1)["status"], "stopped")
        self.assertEqual((self.directory / "bootstrap.token").read_bytes(), token)
        self.assertEqual(setup.VOLUME_NAME, "vyron-local-auth-data")
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(str(setup.COMPOSE_FILE), commands[1])
        self.assertTrue(setup.COMPOSE_FILE.is_absolute())
        self.assertEqual(commands[3][-1], "stop")
        self.assertNotIn("--volumes", commands[3])
        self.assertNotIn("down", commands[3])


if __name__ == "__main__":
    unittest.main()
