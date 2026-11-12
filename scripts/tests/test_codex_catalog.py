"""Offline regression tests for the local, read-only Codex plugin catalog."""

import json
import io
from pathlib import Path
import sys
import tempfile
import unittest


SERVICE_ROOT = (
    Path(__file__).resolve().parents[2]
    / "Apps/Vyron/Resources/CodexCatalog"
)
sys.path.insert(0, str(SERVICE_ROOT))

from catalog import Catalog
from protocol import MAX_MESSAGE_BYTES, handle_message, process_stream


class CodexCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vyron-codex-catalog-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.catalog = Catalog(self.cache)

    def package(self, name="example", version="1.0.0", portable=False, **extra):
        package = self.cache / "test-marketplace" / name / version
        package.mkdir(parents=True)
        manifest = {
            "name": name,
            "version": version,
            "description": "A sample plugin for offline tests.",
            **extra,
        }
        relative = "plugin.json" if portable else ".codex-plugin/plugin.json"
        self.write_json(package / relative, manifest)
        return package

    @staticmethod
    def write_json(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def item(self, name="example"):
        items = self.catalog.list_plugins(limit=50)["plugins"]
        return next(item for item in items if item["name"] == name)

    def inspected(self, name="example"):
        return self.catalog.inspect_plugin(self.item(name)["id"])

    @staticmethod
    def serialized(value):
        return json.dumps(value, ensure_ascii=False)

    def test_compatibility_manifest_exposes_metadata_without_install_claim(self):
        self.package(interface={"displayName": "Example Tools"}, skills="./skills/")
        result = self.catalog.list_plugins()
        self.assertEqual(result["total"], 1)
        self.assertIn("cache", result["scope"].lower())
        item = result["plugins"][0]
        self.assertEqual(item["display_name"], "Example Tools")
        self.assertEqual(item["version"], "1.0.0")
        self.assertIsNone(item["installed"])
        self.assertIsNone(item["enabled"])
        self.assertIn("test-marketplace", item["source"])

    def test_portable_manifest_wins_and_discovers_standard_components(self):
        package = self.package("portable", portable=True)
        self.write_json(package / ".codex-plugin/plugin.json", {"name": "obsolete-overlay"})
        self.write_json(package / "mcp.json", {
            "mcpServers": {"docs": {"type": "http", "url": "https://docs.example.com/mcp"}}
        })
        skill = package / "skills/search/SKILL.md"
        skill.parent.mkdir(parents=True)
        skill.write_text("""---
name: Search
description: Search documents.
---
Read docs.
""")
        result = self.catalog.list_plugins()
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["plugins"][0]["name"], "portable")
        inspection = self.inspected("portable")
        self.assertEqual(inspection["servers"][0]["name"], "docs")
        self.assertEqual(inspection["servers"][0]["transport"], "http")
        self.assertEqual(inspection["skills"][0]["path"], "skills/search/SKILL.md")

    def test_public_http_plan_is_disabled_and_read_only(self):
        package = self.package(mcpServers="./.mcp.json")
        self.write_json(package / ".mcp.json", {
            "mcpServers": {"docs": {"url": "https://docs.example.com/mcp"}}
        })
        plan = self.catalog.prepare_connection(self.item()["id"], "docs")
        self.assertTrue(plan["compatible"])
        self.assertEqual(plan["blockers"], [])
        connection = plan["connection_json"]
        self.assertEqual(connection["type"], "http")
        self.assertEqual(connection["url"], "https://docs.example.com/mcp")
        self.assertIs(connection["enabled"], False)
        self.assertEqual(connection["permission"], "readOnly")

    def test_conventional_legacy_mcp_file_is_discovered_without_overriding_explicit_choices(self):
        package = self.package()
        self.write_json(package / ".mcp.json", {"mcpServers": {"docs": {
            "url": "https://docs.example.com/mcp",
        }}})
        self.assertEqual(self.inspected()["servers"][0]["name"], "docs")
        manifest = package / ".codex-plugin/plugin.json"
        for explicit in (None, {}):
            with self.subTest(explicit=explicit):
                self.write_json(manifest, {"name": "example", "mcpServers": explicit})
                self.assertEqual(self.inspected()["servers"], [])

    def test_headers_environment_and_url_secrets_never_leave_catalog(self):
        package = self.package(mcpServers="./.mcp.json")
        self.write_json(package / ".mcp.json", {
            "mcpServers": {
                "private": {
                    "type": "http",
                    "url": "https://user:SECRET_PASSWORD@api.example.com/mcp?api_key=SECRET_QUERY#SECRET_FRAGMENT",
                    "headers": {"Authorization": "Bearer SECRET_HEADER", "X-Client": "SECRET_CLIENT"},
                    "env": {"API_TOKEN": "SECRET_ENV"},
                }
            }
        })
        plugin_id = self.item()["id"]
        results = [self.catalog.list_plugins(), self.catalog.inspect_plugin(plugin_id)]
        results.append(self.catalog.prepare_connection(plugin_id, "private"))
        text = self.serialized(results)
        for secret in ("SECRET_PASSWORD", "SECRET_QUERY", "SECRET_FRAGMENT", "SECRET_HEADER",
                       "SECRET_CLIENT", "SECRET_ENV"):
            self.assertNotIn(secret, text)
        self.assertTrue(results[-1]["credential_fields"] or results[-1]["blockers"])

    def test_private_codex_pipe_and_application_runtime_are_not_importable(self):
        package = self.package("codex-app-tools", mcpServers="./.mcp.json")
        self.write_json(package / ".mcp.json", {
            "mcpServers": {
                "codex_app": {
                    "command": "/Applications/Codex.app/Contents/Resources/launch_codex_app_tools_mcp",
                    "args": [],
                    "env_vars": ["CODEX_APP_TOOLS_PIPE_PATH"],
                }
            }
        })
        plan = self.catalog.prepare_connection(self.item("codex-app-tools")["id"], "codex_app")
        self.assertFalse(plan["compatible"])
        self.assertIsNone(plan["connection_json"])
        self.assertTrue(plan["blockers"])

    def test_private_inherited_runtime_environment_is_not_portable(self):
        package = self.package(mcpServers="./.mcp.json")
        for variable in ("CODEX_APP_TOOLS_PIPE_PATH", "BROWSER_USE_ACCESS_PIPE_PATH"):
            with self.subTest(variable=variable):
                self.write_json(package / ".mcp.json", {"mcpServers": {"runtime": {
                    "command": "node", "args": ["runtime.js"], "env_vars": [variable],
                }}})
                plan = self.catalog.prepare_connection(self.item()["id"], "runtime")
                self.assertFalse(plan["compatible"])
                self.assertIsNone(plan["connection_json"])

    def test_command_credentials_are_not_exposed_or_copied(self):
        package = self.package(mcpServers="./.mcp.json")
        self.write_json(package / ".mcp.json", {"mcpServers": {"local": {
            "command": "python3", "args": ["-m", "example", "--api-key", "SECRET_COMMAND_ARG"],
        }}})
        plugin_id = self.item()["id"]
        inspection = self.catalog.inspect_plugin(plugin_id)
        plan = self.catalog.prepare_connection(plugin_id, "local")
        self.assertFalse(plan["compatible"])
        self.assertIsNone(plan["connection_json"])
        self.assertNotIn("SECRET_COMMAND_ARG", self.serialized([inspection, plan]))

    def test_relative_executable_and_working_directory_require_manual_setup(self):
        package = self.package(mcpServers="./.mcp.json")
        configurations = (
            {"command": "./server", "args": []},
            {"command": "bin/server", "args": []},
            {"command": "python3", "args": ["server.py"], "cwd": "/package"},
        )
        for config in configurations:
            with self.subTest(config=config):
                self.write_json(package / ".mcp.json", {"mcpServers": {"local": config}})
                plan = self.catalog.prepare_connection(self.item()["id"], "local")
                self.assertFalse(plan["compatible"])
                self.assertIsNone(plan["connection_json"])
                self.assertTrue(plan["blockers"])

    def test_cookie_and_embedded_url_auth_values_are_not_copied_into_plans(self):
        package = self.package(mcpServers="./.mcp.json")
        configurations = (
            {"command": "node", "args": ["server.js", "--cookie", "session=qazxsw987"]},
            {"command": "python3", "args": ["--endpoint=https://user:qazxsw987@example.com/mcp"]},
            {"command": "https://user:qazxsw987@example.com/mcp", "args": []},
        )
        for config in configurations:
            with self.subTest(command=config["command"]):
                self.write_json(package / ".mcp.json", {"mcpServers": {"local": config}})
                plan = self.catalog.prepare_connection(self.item()["id"], "local")
                self.assertFalse(plan["compatible"])
                self.assertIsNone(plan["connection_json"])
                self.assertNotIn("qazxsw987", self.serialized(plan))

    def test_inherited_environment_is_reported_as_required_setup_without_reading_values(self):
        package = self.package(mcpServers="./.mcp.json")
        self.write_json(package / ".mcp.json", {"mcpServers": {"local": {
            "command": "python3", "args": ["-m", "docs"], "env_vars": ["DOCS_API_TOKEN"],
        }}})
        plan = self.catalog.prepare_connection(self.item()["id"], "local")
        self.assertTrue(plan["compatible"])
        self.assertFalse(plan["ready_to_connect"])
        self.assertTrue(plan["credential_fields"])
        self.assertNotIn("env", plan["connection_json"])

    def test_nested_oauth_and_generic_auth_fields_are_not_lost_during_import(self):
        package = self.package(mcpServers="./.mcp.json")
        servers = {"oauth": {"url": "https://api.example.com/mcp", "auth": {
            "type": "oauth2", "clientSecret": "qazxsw987",
        }}}
        self.write_json(package / ".mcp.json", {"mcpServers": servers})
        plan = self.catalog.prepare_connection(self.item()["id"], "oauth")
        self.assertFalse(plan["compatible"])
        self.assertIn("oauth", plan["credential_fields"])
        self.assertNotIn("qazxsw987", self.serialized(plan))
        servers["manual"] = {"url": "https://api.example.com/mcp", "apiKey": "qazxsw987"}
        self.write_json(package / ".mcp.json", {"mcpServers": servers})
        plan = self.catalog.prepare_connection(self.item()["id"], "manual")
        self.assertTrue(plan["compatible"])
        self.assertFalse(plan["ready_to_connect"])
        self.assertNotIn("qazxsw987", self.serialized(plan))

    def test_oauth_is_blocked_and_auth_values_are_configured_separately(self):
        package = self.package(mcpServers="./.mcp.json")
        servers = {"oauth": {"type": "http", "url": "https://api.example.com/mcp",
                             "oauth_resource": "https://api.example.com"}}
        self.write_json(package / ".mcp.json", {"mcpServers": servers})
        plan = self.catalog.prepare_connection(self.item()["id"], "oauth")
        self.assertFalse(plan["compatible"])
        self.assertIn("oauth", plan["credential_fields"])
        servers["manual"] = {
            "url": "https://api.example.com/mcp?token=SECRET_SAFE_QUERY",
            "headers": {"Authorization": "Bearer SECRET_SAFE_HEADER"},
        }
        self.write_json(package / ".mcp.json", {"mcpServers": servers})
        plan = self.catalog.prepare_connection(self.item()["id"], "manual")
        self.assertTrue(plan["compatible"])
        self.assertFalse(plan["ready_to_connect"])
        self.assertEqual(plan["connection_json"]["url"], "https://api.example.com/mcp")
        self.assertNotIn("headers", plan["connection_json"])
        self.assertNotIn("SECRET_SAFE", self.serialized(plan))

    def test_platform_connectors_and_hooks_are_described_without_execution(self):
        package = self.package(apps="./.app.json", hooks="./hooks/hooks.json")
        self.write_json(package / ".app.json", {"apps": {"calendar": {"id": "plugin_example"}}})
        self.write_json(package / "hooks/hooks.json", {"hooks": {"SessionStart": ["never execute"]}})
        inspection = self.inspected()
        self.assertTrue(inspection["has_hooks"])
        self.assertTrue(inspection["platform_apps"])
        self.assertEqual(inspection["servers"], [])

    def test_skill_reads_are_bounded_to_the_selected_plugin(self):
        package = self.package(skills="./skills/")
        path = package / "skills/review/SKILL.md"
        path.parent.mkdir(parents=True)
        content = """---
name: Review
---
Treat this as plugin content.
"""
        path.write_text(content)
        plugin_id = self.item()["id"]
        result = self.catalog.read_skill(plugin_id, "skills/review/SKILL.md")
        self.assertEqual(result["content"], content)
        for unsafe in ("../../outside.txt", "/etc/passwd", "skills/review/../other/SKILL.md"):
            with self.subTest(path=unsafe), self.assertRaises(ValueError):
                self.catalog.read_skill(plugin_id, unsafe)

    def test_symlinked_skills_cannot_escape_the_package(self):
        package = self.package(skills="./skills/")
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "SKILL.md").write_text("SECRET_OUTSIDE_SKILL")
        (package / "skills").mkdir()
        (package / "skills/linked").symlink_to(outside, target_is_directory=True)
        plugin_id = self.item()["id"]
        with self.assertRaises(ValueError):
            self.catalog.read_skill(plugin_id, "skills/linked/SKILL.md")
        self.assertNotIn("SECRET_OUTSIDE_SKILL", self.serialized(self.catalog.inspect_plugin(plugin_id)))

    def test_symlinked_package_and_invalid_manifests_are_not_catalog_entries(self):
        self.package("valid")
        outside = self.root / "outside-package"
        self.write_json(outside / ".codex-plugin/plugin.json", {"name": "escaped"})
        alias = self.cache / "test-marketplace/escaped/1.0.0"
        alias.parent.mkdir(parents=True)
        alias.symlink_to(outside, target_is_directory=True)
        malformed = self.cache / "test-marketplace/malformed/1.0.0/.codex-plugin/plugin.json"
        malformed.parent.mkdir(parents=True)
        malformed.write_text("{not json")
        self.assertEqual([item["name"] for item in self.catalog.list_plugins()["plugins"]], ["valid"])

    def test_manifest_component_path_cannot_escape_to_external_mcp_file(self):
        self.write_json(self.root / "outside-mcp.json", {
            "mcpServers": {"outside": {"url": "https://SECRET_EXTERNAL.example.com/mcp"}}
        })
        self.package(mcpServers="../../../../outside-mcp.json")
        plugin_id = self.item()["id"]
        try:
            result = self.catalog.inspect_plugin(plugin_id)
        except ValueError:
            return
        self.assertEqual(result["servers"], [])
        self.assertNotIn("SECRET_EXTERNAL", self.serialized(result))

    def test_symlinked_manifest_and_mcp_metadata_are_not_followed(self):
        outside = self.root / "external.json"
        self.write_json(outside, {"name": "SECRET_EXTERNAL_MANIFEST"})
        package = self.cache / "test-marketplace/linked-manifest/1.0.0"
        (package / ".codex-plugin").mkdir(parents=True)
        (package / ".codex-plugin/plugin.json").symlink_to(outside)
        self.assertEqual(self.catalog.list_plugins()["plugins"], [])
        package = self.package(mcpServers="./.mcp.json")
        self.write_json(outside, {"mcpServers": {"secret": {"url": "https://SECRET_EXTERNAL.example.com"}}})
        (package / ".mcp.json").symlink_to(outside)
        with self.assertRaises(ValueError):
            self.catalog.inspect_plugin(self.item()["id"])

    def test_wrong_type_metadata_is_isolated_and_oversized_skills_are_not_read(self):
        wrong_name = self.package("wrong-name")
        self.write_json(wrong_name / ".codex-plugin/plugin.json", {"name": 123})
        self.package("wrong-types", portable=True, extensions=["not an object"])
        self.package("valid", interface=["not an interface"], skills="./skills/")
        self.assertEqual([item["name"] for item in self.catalog.list_plugins()["plugins"]], ["valid"])
        package = self.cache / "test-marketplace/valid/1.0.0"
        skill = package / "skills/large/SKILL.md"
        skill.parent.mkdir(parents=True)
        skill.write_text("A" * 65_537)
        plugin_id = self.item("valid")["id"]
        self.assertEqual(self.catalog.inspect_plugin(plugin_id)["skills"], [])
        with self.assertRaises(ValueError):
            self.catalog.read_skill(plugin_id, "skills/large/SKILL.md")

    def test_pagination_query_and_invalid_bounds(self):
        for name in ("alpha", "beta", "gamma"):
            self.package(name)
        first = self.catalog.list_plugins(limit=2)
        self.assertEqual(first["total"], 3)
        self.assertEqual(len(first["plugins"]), 2)
        self.assertEqual(first["next_offset"], 2)
        second = self.catalog.list_plugins(offset=2, limit=2)
        self.assertEqual(len(second["plugins"]), 1)
        self.assertIsNone(second["next_offset"])
        self.assertEqual({item["id"] for item in first["plugins"]}.intersection(
            item["id"] for item in second["plugins"]), set())
        self.assertEqual(self.catalog.list_plugins(query="GAMMA")["total"], 1)
        self.assertEqual(self.catalog.list_plugins(offset=99)["plugins"], [])
        for bounds in ({"offset": -1}, {"limit": 0}, {"limit": 1000}, {"limit": True}, {"offset": True}):
            with self.subTest(bounds=bounds), self.assertRaises(ValueError):
                self.catalog.list_plugins(**bounds)

    def test_missing_cache_and_unknown_ids_are_handled(self):
        empty = Catalog(self.root / "absent")
        self.assertEqual(empty.list_plugins()["plugins"], [])
        for plugin_id in ("does-not-exist", "../outside", "/etc/passwd"):
            with self.subTest(plugin_id=plugin_id), self.assertRaises(ValueError):
                self.catalog.inspect_plugin(plugin_id)

    def test_jsonrpc_initialization_notifications_and_ping(self):
        message = {"jsonrpc": "2.0", "id": 7, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "offline-tests", "version": "1"},
        }}
        response = handle_message(message, self.catalog)
        self.assertEqual(response["id"], 7)
        self.assertIsInstance(response["result"]["protocolVersion"], str)
        self.assertIn("tools", response["result"]["capabilities"])
        self.assertIn("serverInfo", response["result"])
        self.assertIsNone(handle_message({"jsonrpc": "2.0", "method": "notifications/initialized"}, self.catalog))
        response = handle_message({"jsonrpc": "2.0", "id": "ping", "method": "ping"}, self.catalog)
        self.assertEqual(response["result"], {})

    def test_jsonrpc_exposes_only_read_only_catalog_tools(self):
        response = handle_message({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}, self.catalog)
        tools = response["result"]["tools"]
        self.assertEqual({tool["name"] for tool in tools}, {
            "list_plugins", "inspect_plugin", "read_skill", "prepare_connection",
        })
        for tool in tools:
            self.assertTrue(tool["annotations"]["readOnlyHint"])
            self.assertIs(tool["annotations"]["destructiveHint"], False)

    def test_jsonrpc_tool_calls_and_invalid_method_arguments(self):
        self.package()
        request = {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {
            "name": "list_plugins", "arguments": {"limit": 1},
        }}
        response = handle_message(request, self.catalog)
        self.assertIn("result", response)
        self.assertNotIn("error", response)
        for params in (
            {"name": "install_plugin", "arguments": {}},
            {"name": "list_plugins", "arguments": {"limit": "not an integer"}},
            {"name": "read_skill", "arguments": {"plugin_id": "missing"}},
        ):
            request["params"] = params
            response = handle_message(request, self.catalog)
            self.assertEqual(response["error"]["code"], -32602)
        response = handle_message({"jsonrpc": "2.0", "id": 2, "method": "unknown"}, self.catalog)
        self.assertEqual(response["error"]["code"], -32601)

    def test_protocol_rejects_bad_frames_and_recovers_for_next_request(self):
        ping = json.dumps({"jsonrpc": "2.0", "id": 20, "method": "ping"}).encode()
        frames = b"{malformed\n" + b"A" * (MAX_MESSAGE_BYTES + 1) + b"\n" + ping + b"\n"
        target = io.StringIO()
        process_stream(io.BytesIO(frames), target, self.catalog)
        responses = [json.loads(line) for line in target.getvalue().splitlines()]
        self.assertEqual(len(responses), 3)
        self.assertEqual([item["error"]["code"] for item in responses[:2]], [-32700, -32700])
        self.assertEqual(responses[2], {"jsonrpc": "2.0", "id": 20, "result": {}})

    def test_protocol_rejects_invalid_utf8_nonfinite_numbers_and_request_ids(self):
        target = io.StringIO()
        process_stream(io.BytesIO(b"\xff\n{\"jsonrpc\":\"2.0\",\"id\":NaN,\"method\":\"ping\"}\n"),
                       target, self.catalog)
        responses = [json.loads(line) for line in target.getvalue().splitlines()]
        self.assertEqual([item["error"]["code"] for item in responses], [-32700, -32700])
        for identifier in ([], {}, True, 1.5):
            with self.subTest(identifier=identifier):
                response = handle_message({"jsonrpc": "2.0", "id": identifier, "method": "ping"}, self.catalog)
                self.assertEqual(response["error"]["code"], -32600)


if __name__ == "__main__":
    unittest.main()
