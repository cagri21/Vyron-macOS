#!/usr/bin/env python3
"""Explicitly register a packaged Vyron host for one Chrome extension ID."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys
import uuid


HOST_NAME = "ai.vyron.chrome"
MANIFEST_NAME = HOST_NAME + ".json"
REGISTRATION_NAME = "registration.json"
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
EXTENSION_ID = re.compile(r"[a-p]{32}\Z")


class InstallationError(Exception):
    """A registration path or input could not be safely verified."""


def absolute_parts(path: Path) -> tuple[str, ...]:
    if not path.is_absolute() or any(part in {".", ".."} for part in path.parts):
        raise InstallationError("Use an absolute path without '.' or '..' components.")
    return path.parts[1:]


def open_directory(path: Path, *, create: bool = False) -> int:
    """Traverse with directory descriptors, never through a symbolic link."""
    descriptor = os.open("/", DIRECTORY_FLAGS)
    try:
        for part in absolute_parts(path):
            try:
                child = os.open(part, DIRECTORY_FLAGS, dir_fd=descriptor)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(part, mode=0o700, dir_fd=descriptor)
                child = os.open(part, DIRECTORY_FLAGS, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def verified_host(app: Path) -> Path:
    if app.suffix.lower() != ".app":
        raise InstallationError("--app must identify a packaged Vyron .app bundle.")
    directory = open_directory(app / "Contents" / "MacOS")
    try:
        descriptor = os.open("VyronChromeHost", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or not metadata.st_mode & 0o111:
                raise InstallationError("The packaged VyronChromeHost must be a regular executable file.")
            if metadata.st_uid not in {0, os.getuid()} or metadata.st_mode & 0o022:
                raise InstallationError("The packaged host must be owned by you or root and not writable by others.")
        finally:
            os.close(descriptor)
    finally:
        os.close(directory)
    return app / "Contents" / "MacOS" / "VyronChromeHost"


def manifest_for(app: Path, extension_id: str) -> dict[str, object]:
    if not EXTENSION_ID.fullmatch(extension_id):
        raise InstallationError("--extension-id must contain exactly 32 lowercase letters from a through p.")
    host = verified_host(app)
    return {
        "name": HOST_NAME,
        "description": "Vyron Chrome browser bridge",
        "path": str(host),
        "type": "stdio",
        "allowed_origins": [f"chrome-extension://{extension_id}/"],
    }


def existing_registration_file(directory: int, name: str) -> os.stat_result | None:
    try:
        metadata = os.stat(name, dir_fd=directory, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_nlink != 1:
        raise InstallationError(f"The existing {name} must be a regular file owned only by you.")
    return metadata


def write_registration_file(destination: Path, manifest: dict[str, object], *, private_directory: bool) -> None:
    directory = open_directory(destination.parent, create=True)
    name = destination.name
    temporary = "." + name + "." + uuid.uuid4().hex
    created = False
    try:
        parent = os.fstat(directory)
        if private_directory and (parent.st_uid != os.getuid() or parent.st_mode & 0o077):
            raise InstallationError("Vyron's ChromeBridge folder must be private and owned by you.")
        if not private_directory and (parent.st_uid != os.getuid() or parent.st_mode & 0o022):
            raise InstallationError("Chrome's NativeMessagingHosts folder must be owned by you and not writable by others.")
        previous = existing_registration_file(directory, name)
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=directory,
        )
        created = True
        with os.fdopen(descriptor, "wb") as output:
            output.write((json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
            output.flush()
            os.fsync(output.fileno())
        current = existing_registration_file(directory, name)
        identity = lambda item: None if item is None else (item.st_dev, item.st_ino)
        if identity(previous) != identity(current):
            raise InstallationError(f"{name} changed during registration. Try again after reviewing it.")
        os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
        created = False
        os.fsync(directory)
    finally:
        if created:
            os.unlink(temporary, dir_fd=directory)
        os.close(directory)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Absolute path to the packaged Vyron.app")
    parser.add_argument("--extension-id", required=True, help="The exact ID shown on chrome://extensions")
    parser.add_argument("--dry-run", action="store_true", help="Print registration details without writing files")
    arguments = parser.parse_args()
    try:
        manifest = manifest_for(arguments.app, arguments.extension_id)
        support = Path.home() / "Library" / "Application Support"
        destination = support / "Google" / "Chrome" / "NativeMessagingHosts" / MANIFEST_NAME
        registration = support / "VyronAI" / "ChromeBridge" / REGISTRATION_NAME
        if arguments.dry_run:
            print(json.dumps({
                "destination": str(destination),
                "registration": str(registration),
                "manifest": manifest,
            }, indent=2))
        else:
            write_registration_file(registration, manifest, private_directory=True)
            write_registration_file(destination, manifest, private_directory=False)
            print(f"Registered {HOST_NAME} for extension {arguments.extension_id} at {destination}")
        return 0
    except (InstallationError, OSError) as error:
        print(f"Chrome host registration failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
