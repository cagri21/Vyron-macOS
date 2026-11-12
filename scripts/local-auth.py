#!/usr/bin/env python3
"""Set up and explicitly start Vyron's persistent local authentication service."""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = "http://127.0.0.1:8327"
PROJECT_NAME = "vyron-local-auth"
VOLUME_NAME = "vyron-local-auth-data"
COMPOSE_FILE = Path(__file__).resolve().parents[1] / "services/local-auth/compose.yaml"
CONFIGURATION = {"schema_version": 1, "endpoint": ENDPOINT}


class SetupError(Exception):
    """A safe, user-facing setup error without sensitive input or subprocess output."""


def default_directory() -> Path:
    return Path.home() / "Library/Application Support/VyronAI/LocalAuth"


def checked_directory(value: Path) -> Path:
    path = value.expanduser()
    if not path.is_absolute() or ".." in path.parts:
        raise SetupError("Use an absolute directory without parent-directory components.")
    for component in (path, *path.parents):
        if component.is_symlink():
            raise SetupError("Local authentication files must not use symlinked paths.")
    if path.exists():
        info = path.stat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise SetupError("The local authentication directory must be private and owned by this account.")
    return path


def checked_file(path: Path, maximum: int, read: bool = True) -> bytes | None:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    except OSError as exception:
        raise SetupError("A local authentication file cannot be opened safely.") from exception
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() \
            or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1 or info.st_size > maximum:
            raise SetupError("Local authentication files must be private, regular files owned by this account.")
        if not read:
            return b""
        with os.fdopen(descriptor, "rb") as stream:
            descriptor = -1
            return stream.read(maximum + 1)
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def validate_token(data: bytes):
    try:
        token = data.decode("ascii").removesuffix("\n")
        decoded = base64.urlsafe_b64decode(token + "=")
        if not re.fullmatch(r"[A-Za-z0-9_-]{43}", token) or len(decoded) != 32 \
            or base64.urlsafe_b64encode(decoded).decode("ascii").rstrip("=") != token:
            raise ValueError()
    except (ValueError, UnicodeError) as exception:
        raise SetupError("The existing bootstrap file is invalid; it was preserved.") from exception


def validate_config(data: bytes):
    def unique_keys(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError()
            value[key] = item
        return value

    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=unique_keys)
        if not isinstance(value, dict) or type(value.get("schema_version")) is not int or value != CONFIGURATION:
            raise ValueError()
    except (ValueError, UnicodeError, RecursionError) as exception:
        raise SetupError("The existing local authentication configuration is invalid; it was preserved.") from exception


def create_once(path: Path, data: bytes):
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        return
    try:
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = -1
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def prepare(directory: Path) -> Path:
    directory = checked_directory(directory)
    token = checked_file(directory / "bootstrap.token", 44)
    configuration = checked_file(directory / "config.json", 4_096)
    if token is not None:
        validate_token(token)
    if configuration is not None:
        validate_config(configuration)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    checked_directory(directory)
    create_once(directory / "bootstrap.token", (secrets.token_urlsafe(32) + "\n").encode("ascii"))
    create_once(directory / "config.json", (json.dumps(CONFIGURATION, indent=2) + "\n").encode("utf-8"))
    saved_token = checked_file(directory / "bootstrap.token", 44)
    saved_config = checked_file(directory / "config.json", 4_096)
    if saved_token is None or saved_config is None:
        raise SetupError("Local authentication files changed during setup; existing data was preserved.")
    validate_token(saved_token)
    validate_config(saved_config)
    return directory


def docker_environment(directory: Path) -> dict[str, str]:
    # Forward Docker's ordinary location/context settings, never unrelated provider keys or host tokens.
    environment = {key: os.environ[key] for key in (
        "HOME", "PATH", "TMPDIR", "LANG", "DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CONFIG"
    ) if key in os.environ}
    environment.update({
        "VYRON_LOCAL_UID": str(os.getuid()), "VYRON_LOCAL_GID": str(os.getgid()),
        "VYRON_LOCAL_AUTH_TOKEN_FILE": str(directory / "bootstrap.token")
    })
    return environment


def compose_command(docker: str) -> list[str]:
    return [docker, "compose", "--project-name", PROJECT_NAME, "--file", str(COMPOSE_FILE)]


def require_local_docker(docker: str, environment: dict[str, str]):
    host = environment.get("DOCKER_HOST", "")
    if host and not host.startswith("unix:///"):
        raise SetupError("Local authentication requires Docker on this Mac, not a remote Docker host.")
    result = subprocess.run(
        [docker, "context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"],
        env=environment, capture_output=True, text=True, timeout=15, check=False
    )
    try:
        endpoint = json.loads(result.stdout)
        valid = result.returncode == 0 and isinstance(endpoint, str) and endpoint.startswith("unix:///")
    except ValueError:
        valid = False
    if not valid:
        raise SetupError("Select a local Docker context and start Docker before continuing.")


class RejectRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


def healthy() -> bool:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), RejectRedirects())
    try:
        with opener.open(ENDPOINT + "/health", timeout=1) as response:
            value = json.loads(response.read(2_049))
            return response.status == 200 and value.get("status") == "ok" \
                and value.get("service") == PROJECT_NAME and type(value.get("schema_version")) is int \
                and value["schema_version"] == 1
    except (OSError, ValueError, AttributeError, urllib.error.URLError):
        return False


def execute(action: str, directory: Path, wait_seconds: float) -> dict:
    directory = prepare(directory) if action in {"setup", "start"} else checked_directory(directory)
    summary = {
        "action": action, "endpoint": ENDPOINT, "configuration_directory": str(directory),
        "data_volume": VOLUME_NAME
    }
    if action == "setup":
        return dict(summary, ok=True, status="configured")
    if action == "status":
        configuration = checked_file(directory / "config.json", 4_096)
        if configuration is not None:
            validate_config(configuration)
        configured = configuration is not None
        return dict(summary, ok=True, status="healthy" if configured and healthy() else "unavailable")
    if not COMPOSE_FILE.is_file() or COMPOSE_FILE.is_symlink():
        raise SetupError("The local authentication Compose file is missing or unsafe.")
    docker = shutil.which("docker")
    if not docker:
        raise SetupError("Docker is not installed or is not available in this shell.")
    environment = docker_environment(directory)
    require_local_docker(docker, environment)
    command = compose_command(docker) + (["up", "--detach", "--build"] if action == "start" else ["stop"])
    result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=180, check=False)
    if result.returncode:
        raise SetupError("Docker could not start or stop local authentication. Existing files and data were preserved.")
    if action == "stop":
        return dict(summary, ok=True, status="stopped")
    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        if healthy():
            return dict(summary, ok=True, status="healthy")
        time.sleep(0.25)
    raise SetupError("Local authentication is configured but is not healthy yet. Existing files and data were preserved.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["setup", "start", "status", "stop"])
    parser.add_argument("--data-dir", type=Path, default=None, help="Private configuration directory; defaults to VyronAI/LocalAuth.")
    parser.add_argument("--dry-run", action="store_true", help="Validate paths and describe the action without writes or Docker.")
    parser.add_argument("--wait-seconds", type=float, default=30)
    arguments = parser.parse_args(argv)
    try:
        os.umask(0o077)
        if not 1 <= arguments.wait_seconds <= 60:
            raise SetupError("Wait time must be between 1 and 60 seconds.")
        directory = checked_directory(arguments.data_dir or default_directory())
        if arguments.dry_run:
            checked_file(directory / "bootstrap.token", 44, read=False)
            checked_file(directory / "config.json", 4_096, read=False)
            result = {
                "ok": True, "dry_run": True, "action": arguments.action, "endpoint": ENDPOINT,
                "configuration_directory": str(directory), "compose_file": str(COMPOSE_FILE),
                "data_volume": VOLUME_NAME
            }
        else:
            result = execute(arguments.action, directory, arguments.wait_seconds)
        print(json.dumps(result, sort_keys=True))
        return 0
    except SetupError as exception:
        print(json.dumps({"ok": False, "action": arguments.action, "error": str(exception)}))
        return 1
    except (OSError, subprocess.SubprocessError):
        print(json.dumps({
            "ok": False, "action": arguments.action,
            "error": "Local authentication could not complete this action safely; existing credentials and data were preserved."
        }))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
