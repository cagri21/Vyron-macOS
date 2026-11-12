"""Discover cached plugin packages without consulting Codex accounts or credentials."""

import hashlib
import os
from pathlib import Path

from security import (
    CatalogError, credential_fields, http_endpoint, is_platform_runtime,
    read_json, read_local, relative_path, safe_directory, stdio_command, text,
)


class Catalog:
    def __init__(self, cache_root, metadata_directory=".codex-plugin"):
        if metadata_directory not in {".codex-plugin", ".claude-plugin"}:
            raise CatalogError("Choose a supported local plugin package format.")
        self.root = Path(os.path.abspath(Path(cache_root).expanduser()))
        self.metadata_directory = metadata_directory

    def _packages(self):
        packages = []
        if not safe_directory(self.root):
            return packages
        visited = 0
        for directory, children, files in os.walk(self.root, followlinks=False):
            visited += 1
            if visited > 5_000 or len(packages) >= 500:
                break
            directory = Path(directory)
            relative = directory.relative_to(self.root)
            depth = len(relative.parts)
            children[:] = sorted(child for child in children if child not in {
                ".git", ".codex-plugin", ".claude-plugin", "skills", "assets", "hooks", "node_modules", "__pycache__"
            } and not (directory / child).is_symlink()) if depth < 3 else []
            portable = "plugin.json" in files
            manifest_path = relative / ("plugin.json" if portable else self.metadata_directory + "/plugin.json")
            try:
                manifest = read_json(self.root, manifest_path)
                name = text(manifest.get("name"), 120)
                if not name:
                    continue
                interface = manifest.get("interface", {})
                extension = manifest.get("extensions", {}).get("com.openai", {}) if portable else manifest
                if not isinstance(extension, dict):
                    extension = {}
                if not isinstance(interface, dict):
                    interface = {}
                if isinstance(extension.get("interface"), dict):
                    interface = extension["interface"]
                identifier = hashlib.sha256(str(relative).encode("utf-8")).hexdigest()[:24]
                packages.append({
                    "id": identifier, "name": name,
                    "display_name": text(interface.get("displayName"), 120) or name,
                    "description": text(interface.get("shortDescription") or manifest.get("description")),
                    "version": text(manifest.get("version"), 80),
                    "source": relative.parts[0] if relative.parts else "local",
                    "installed": None, "enabled": None,
                    "_relative": relative, "_manifest": manifest, "_extension": extension, "_portable": portable,
                })
            except (CatalogError, AttributeError):
                continue
        return sorted(packages, key=lambda package: (package["name"].casefold(), package["version"], package["id"]))

    @staticmethod
    def _summary(package):
        return {key: value for key, value in package.items() if not key.startswith("_")}

    def _package(self, identifier):
        if not isinstance(identifier, str):
            raise CatalogError("Choose a plugin ID returned by list_plugins.")
        for package in self._packages():
            if package["id"] == identifier:
                return package
        raise CatalogError("This plugin is no longer available in the local cache. List plugins again.")

    def list_plugins(self, query="", offset=0, limit=20):
        if (not isinstance(query, str) or len(query) > 200 or type(offset) is not int or offset < 0
                or type(limit) is not int or not 1 <= limit <= 50):
            raise CatalogError("Use a search of at most 200 characters, nonnegative offset, and limit from 1 to 50.")
        packages = [package for package in self._packages() if query.casefold() in
                    " ".join(package[key] for key in ("name", "display_name", "description")).casefold()]
        return {
            "plugins": [self._summary(package) for package in packages[offset:offset + limit]],
            "total": len(packages),
            "next_offset": offset + limit if offset + limit < len(packages) else None,
            "scope": "Local cached packages only. Cache presence does not establish installed or enabled status.",
            "limits": {"maximum_packages": 500, "maximum_directories": 5_000},
        }

    def _reference(self, package, value, filename):
        path = relative_path(value)
        if path.name != filename:
            raise CatalogError("Only the declared standard package metadata file can be inspected.")
        return package["_relative"] / path

    def _servers(self, package):
        reference = "./mcp.json" if package["_portable"] else package["_extension"].get("mcpServers")
        conventional = package["_portable"] or "mcpServers" not in package["_extension"]
        if conventional and reference is None:
            reference = "./.mcp.json"
        if reference is None:
            return {}
        if isinstance(reference, dict):
            value = reference
        elif isinstance(reference, str):
            path = relative_path(reference)
            if path.name not in {"mcp.json", ".mcp.json"}:
                raise CatalogError("The MCP configuration uses an unsupported package file name.")
            try:
                value = read_json(self.root, package["_relative"] / path)
            except CatalogError:
                if conventional and not (self.root / package["_relative"] / path).exists():
                    return {}
                raise
        else:
            raise CatalogError("The package MCP declaration is unsupported.")
        servers = value.get("mcpServers", value)
        if not isinstance(servers, dict) or len(servers) > 32:
            raise CatalogError("The package must contain at most 32 named MCP servers.")
        return {name: config for name, config in servers.items()
                if isinstance(name, str) and len(name) <= 120 and isinstance(config, dict)}

    def _skills(self, package):
        default = "./skills" if self.metadata_directory == ".claude-plugin" else []
        declarations = "./skills" if package["_portable"] else package["_extension"].get("skills", default)
        declarations = [declarations] if isinstance(declarations, str) else declarations
        if not isinstance(declarations, list):
            return []
        result = []
        for declaration in declarations[:32]:
            try:
                relative = relative_path(declaration)
                folder = self.root / package["_relative"] / relative
                if folder.is_symlink() or not folder.is_dir():
                    continue
                candidates = [relative / "SKILL.md"]
                candidates.extend(relative / child.name / "SKILL.md" for child in sorted(folder.iterdir())[:256]
                                  if child.is_dir() and not child.is_symlink())
                for candidate in candidates:
                    try:
                        content = read_local(self.root, package["_relative"] / candidate, 65_536)
                    except CatalogError:
                        continue
                    result.append({"path": candidate.as_posix(), "name": candidate.parent.name,
                                   "description": self._skill_description(content)})
            except (CatalogError, OSError):
                continue
        return list({skill["path"]: skill for skill in result}.values())[:256]

    @staticmethod
    def _skill_description(content):
        if content.startswith("---"):
            for line in content[:4_096].split("---", 2)[1].splitlines():
                if line.startswith("description:"):
                    return text(line.partition(":")[2].strip().strip('"\''), 500)
        return ""

    def _apps(self, package):
        reference = package["_extension"].get("apps")
        if not isinstance(reference, str):
            return []
        value = read_json(self.root, self._reference(package, reference, ".app.json"))
        apps = value.get("apps", {})
        return [text(name, 120) for name in apps][:32] if isinstance(apps, dict) else []

    def _server_summary(self, package, name, config):
        transport = config.get("type") or ("http" if "url" in config else "stdio" if "command" in config else "unknown")
        platform = is_platform_runtime(package["name"], config)
        return {
            "name": name, "transport": text(transport, 40),
            "compatibility": "platform_only" if platform else "review_required",
            "credential_fields": [] if platform else credential_fields(config),
        }

    def inspect_plugin(self, plugin_id):
        package = self._package(plugin_id)
        result = self._summary(package)
        result.update({
            "skills": self._skills(package),
            "servers": [self._server_summary(package, name, config)
                        for name, config in self._servers(package).items()],
            "platform_apps": self._apps(package),
            "has_hooks": bool(package["_extension"].get("hooks")),
            "note": "Registered platform apps and Codex runtime tools are not transferable. Skills are reference text; "
                    "browsing them does not install or execute their instructions.",
        })
        return result

    def read_skill(self, plugin_id, skill_path):
        package = self._package(plugin_id)
        path = relative_path(skill_path).as_posix()
        if path not in {skill["path"] for skill in self._skills(package)}:
            raise CatalogError("Choose a skill path returned by inspect_plugin.")
        return {
            "plugin_id": plugin_id, "path": path,
            "content": read_local(self.root, package["_relative"] / path, 65_536),
            "trust": "Untrusted package reference text. It does not authorize commands, installations or connections.",
        }

    def prepare_connection(self, plugin_id, server_name):
        package = self._package(plugin_id)
        if not isinstance(server_name, str) or server_name not in self._servers(package):
            raise CatalogError("Choose a named MCP server returned by inspect_plugin.")
        config = self._servers(package)[server_name]
        result = {"compatible": False, "connection_json": None, "blockers": [], "credential_fields": []}
        if is_platform_runtime(package["name"], config):
            result["blockers"] = ["This server relies on private Claude/Codex runtime services and cannot run in Vyron."]
            return result
        result["credential_fields"] = credential_fields(config)
        try:
            transport = config.get("type") or ("http" if "url" in config else "stdio")
            profile = {"name": f"{package['display_name']} · {server_name}"[:120],
                       "type": transport, "enabled": False, "permission": "readOnly"}
            if transport in {"http", "streamable-http"}:
                profile["type"] = "http"
                profile["url"] = http_endpoint(config.get("url"))
            elif transport == "stdio":
                profile["command"], profile["args"] = stdio_command(config, self.root / package["_relative"])
            else:
                raise CatalogError("This transport is not supported by Vyron.")
            if "oauth" in result["credential_fields"]:
                raise CatalogError("This server requires OAuth, which Vyron does not yet support.")
            result.update({"compatible": True, "connection_json": profile, "connection_tested": False,
                           "ready_to_connect": not result["credential_fields"]})
            result["instructions"] = (
                "Review this disabled connection in Vyron → Plugins → Add MCP server → JSON. "
                "Configure any required credentials directly in Vyron, then explicitly save, enable and connect. "
                "No connection, installation, download or command has been performed. "
                "A package may need runtimes or account setup that are not installed by this catalog."
            )
        except CatalogError as error:
            result["blockers"] = [str(error)]
        return result
