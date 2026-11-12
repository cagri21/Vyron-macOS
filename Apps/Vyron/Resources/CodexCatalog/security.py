"""Bounded, local-only reads and credential-free MCP configuration previews."""

import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
from urllib.parse import urlsplit, urlunsplit


class CatalogError(ValueError):
    """A package cannot be safely inspected or represented in Vyron."""


def relative_path(value):
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        raise CatalogError("Use a path inside the selected plugin package.")
    parts = PurePosixPath(value).parts
    if PurePosixPath(value).is_absolute() or ".." in parts:
        raise CatalogError("Paths must stay inside the selected plugin package.")
    return Path(*parts)


def read_local(root, relative, limit=262_144):
    """Open every path component without following links, including during races."""
    parts = relative_path(str(relative)).parts
    if not parts:
        raise CatalogError("A file path is required.")
    descriptors = []
    try:
        descriptor = open_directory(root)
        descriptors.append(descriptor)
        for part in parts[:-1]:
            descriptor = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            descriptors.append(descriptor)
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=descriptor)
        descriptors.append(descriptor)
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > limit:
            raise CatalogError("The package file is not a regular file or exceeds the read limit.")
        chunks = bytearray()
        while len(chunks) <= limit:
            chunk = os.read(descriptor, min(65_536, limit + 1 - len(chunks)))
            if not chunk:
                break
            chunks.extend(chunk)
        if len(chunks) > limit:
            raise CatalogError("The package file exceeds the read limit.")
        return chunks.decode("utf-8")
    except (OSError, UnicodeError) as error:
        raise CatalogError("The package file is missing, unreadable, or uses an unsafe path.") from error
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


def open_directory(path):
    """Open an absolute directory while rejecting symlinks in every ancestor."""
    absolute = Path(os.path.abspath(Path(path).expanduser()))
    descriptor = os.open(absolute.anchor, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in absolute.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def safe_directory(path):
    try:
        descriptor = open_directory(path)
    except OSError:
        return False
    os.close(descriptor)
    return True


def read_json(root, relative):
    try:
        result = json.loads(read_local(root, relative))
    except (ValueError, RecursionError) as error:
        raise CatalogError("The package metadata is not a supported JSON object.") from error
    if not isinstance(result, dict):
        raise CatalogError("The package metadata must be a JSON object.")
    return result


def text(value, limit=1_000):
    if not isinstance(value, str):
        return ""
    return "".join(character for character in value if character >= " " or character == "\n").strip()[:limit]


def field_names(value, prefix):
    if not isinstance(value, dict):
        return []
    return [f"{prefix}.{key}" for key in sorted(value)
            if isinstance(key, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]{0,63}", key)]


def credential_fields(config):
    fields = field_names(config.get("env"), "environment") + field_names(config.get("headers"), "headers")
    inherited = config.get("env_vars", [])
    if isinstance(inherited, list):
        fields.extend(field_names({key: None for key in inherited if isinstance(key, str)}, "environment"))
    raw_url = config.get("url")
    if isinstance(raw_url, str):
        try:
            parts = urlsplit(raw_url)
            if parts.username is not None or parts.password is not None:
                fields.append("url.credentials")
            if parts.query:
                # Query field names may themselves contain secrets. Never expose them.
                fields.append("url.queryParameters")
        except ValueError:
            fields.append("url.invalid")
    if any("oauth" in str(key).lower() for key in config):
        fields.append("oauth")
    for key in config:
        if isinstance(key, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]{0,63}", key):
            if re.search(r"(?i)(auth|token|password|secret|cookie|api[-_]?key)", key):
                fields.append("configuration." + key)
    for key in ("auth", "authentication"):
        value = config.get(key)
        if isinstance(value, dict) and any("oauth" in str(value.get(field, "")).lower()
                                           for field in ("type", "method")):
            fields.append("oauth")
    return sorted(set(fields))


def http_endpoint(value):
    if not isinstance(value, str) or len(value) > 4_096 or "${" in value:
        raise CatalogError("The server URL needs to be configured separately in Vyron.")
    try:
        parts = urlsplit(value)
        host = parts.hostname
        port = parts.port
    except ValueError as error:
        raise CatalogError("The package server URL is invalid.") from error
    if (not host or (parts.scheme != "https" and not
            (parts.scheme == "http" and host in {"localhost", "127.0.0.1", "::1"}))
            or parts.username is not None or parts.password is not None or parts.fragment
            or (port is not None and not 1 <= port <= 65_535)):
        raise CatalogError("Only HTTPS or loopback HTTP without embedded credentials is supported.")
    # Token-shaped path components cannot be safely included in a preview.
    if any(len(segment) > 48 or re.search(r"(?i)(?:sk-|ghp_|token[=:])", segment)
           for segment in parts.path.split("/")):
        raise CatalogError("The URL path may contain credentials; configure it directly in Vyron.")
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def is_platform_runtime(plugin_name, config):
    if plugin_name in {"codex-app-tools", "unified-computer-use"}:
        return True
    command = config.get("command", "")
    arguments = config.get("args", [])
    launch_values = [command] + (arguments if isinstance(arguments, list) else [])
    if any(isinstance(value, str) and (
            "/Codex.app/" in value or "/Claude.app/" in value
            or "${CODEX_APP_" in value or "${CLAUDE_APP_" in value)
           for value in launch_values):
        return True
    environment = config.get("env", {})
    inherited = config.get("env_vars", [])
    keys = (list(environment) if isinstance(environment, dict) else [])
    keys.extend(inherited if isinstance(inherited, list) else [])
    return any(isinstance(key, str) and (
        "PIPE_PATH" in key or "EXECUTOR_ID" in key or "VERIFYING_IDENTITY" in key
        or key.startswith(("CODEX_APP_", "CLAUDE_APP_", "CLAUDE_CODE_", "SKY_CUA_", "BROWSER_USE_"))
    ) for key in keys)


def stdio_command(config, package_root):
    command = config.get("command")
    arguments = config.get("args", [])
    if (not isinstance(command, str) or not command or len(command) > 2_048
            or any(ord(character) < 32 for character in command) or "${" in command
            or (not command.startswith("/") and ("/" in command or any(c.isspace() for c in command)))
            or not isinstance(arguments, list) or len(arguments) > 100):
        raise CatalogError("The local command requires manual configuration in Vyron.")
    if any(config.get(key) for key in ("cwd", "workingDirectory", "working_directory")):
        raise CatalogError("This server requires a working directory that must be configured manually.")
    if "://" in command or re.search(r"(?i)(?:sk-|ghp_|token[=:]|password[=:])", command):
        raise CatalogError("The command may contain credentials; configure it directly in Vyron.")
    if Path(command).name in {"sh", "bash", "zsh", "fish", "powershell", "cmd"}:
        raise CatalogError("Shell-based launchers need manual setup and review in Vyron.")
    result = []
    for value in arguments:
        if not isinstance(value, str) or len(value) > 16_384 or any(ord(character) < 32 for character in value):
            raise CatalogError("The command arguments require manual configuration in Vyron.")
        if re.search(r"(?i)(token|password|secret|credential|api[-_]?key|authorization|bearer|cookie|session[=:]|sk-|ghp_)", value):
            raise CatalogError("Command credentials must be configured directly in Vyron, not copied from Codex.")
        if "://" in value and ("?" in value or "@" in value or "#" in value):
            raise CatalogError("URL arguments may contain credentials; configure them directly in Vyron.")
        if re.search(r"[A-Za-z0-9_+-]{40,}", value):
            raise CatalogError("An argument may contain credentials; configure this command directly in Vyron.")
        for variable in ("${CODEX_PLUGIN_ROOT}", "${CLAUDE_PLUGIN_ROOT}", "${PLUGIN_ROOT}"):
            value = value.replace(variable, str(package_root))
        if "${" in value:
            raise CatalogError("Environment substitutions require separate configuration in Vyron.")
        result.append(value)
    return command, result
