"""Offline integration and trust-boundary tests for the Claude/Codex catalog MCP."""

import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SERVICE_ROOT = Path(__file__).resolve().parents[2] / "Apps/Vyron/Resources/CodexCatalog"
sys.path.insert(0, str(SERVICE_ROOT))

from agent_catalog import AgentCatalog
from catalog import Catalog
from protocol import MAX_MESSAGE_BYTES, handle_message, process_stream
from security import CatalogError


class AgentCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vyron-agent-catalog-")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / "home"
        self.home.mkdir()
        self.project = Path(self.temporary.name) / "project"
        self.project.mkdir()
        self.catalog = AgentCatalog(self.home, self.project)

    @staticmethod
    def write_json(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def package(self, source, name="same-name", **metadata):
        directory = self.home / ("." + source) / "plugins/cache/test-marketplace" / name / "1.0.0"
        self.write_json(directory / ("." + source + "-plugin/plugin.json"), {
            "name": name, "version": "1.0.0", "description": "Offline fixture", **metadata,
        })
        return directory

    def skill(self, root, name="fixture", body="Reference text."):
        path = root / name / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("---\nname: " + name + "\ndescription: Offline fixture skill.\n---\n" + body,
                        encoding="utf-8")
        return path

    def call(self, name, arguments=None):
        response = handle_message({
            "jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {
                "name": name, "arguments": arguments or {},
            },
        }, self.catalog)
        self.assertNotIn("error", response, response)
        self.assertFalse(response["result"].get("isError", False), response)
        return json.loads(response["result"]["content"][0]["text"])

    def plugin(self, source, name="same-name"):
        return next(item for item in self.catalog.list_plugins(source=source)["plugins"] if item["name"] == name)

    def test_combined_initialize_and_tools_keep_the_legacy_protocol_available(self):
        request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
        }}
        combined = handle_message(request, self.catalog)["result"]
        legacy = handle_message(request, Catalog(self.home / ".codex/plugins/cache"))["result"]
        self.assertEqual(combined["protocolVersion"], "2025-06-18")
        self.assertNotEqual(combined["serverInfo"]["name"], legacy["serverInfo"]["name"])
        self.assertEqual(legacy["serverInfo"]["name"], "vyron-codex-catalog")
        response = handle_message({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, self.catalog)
        definitions = response["result"]["tools"]
        self.assertEqual({item["name"] for item in definitions}, {
            "list_sources", "list_skills", "read_skill", "list_plugins", "inspect_plugin", "prepare_connection",
        })
        for definition in definitions:
            self.assertTrue(definition["annotations"]["readOnlyHint"])
            self.assertIs(definition["annotations"]["destructiveHint"], False)
            self.assertFalse(definition["inputSchema"]["additionalProperties"])
        self.assertIsNone(handle_message({
            "jsonrpc": "2.0", "method": "notifications/initialized",
        }, self.catalog))

    def test_same_named_plugins_have_distinct_source_ids_and_filter_independently(self):
        for source in ("codex", "claude"):
            package = self.package(source)
            self.write_json(package / ".mcp.json", {"mcpServers": {
                "docs": {"url": "https://" + source + ".example.invalid/mcp"},
            }})
        listing = self.call("list_plugins")
        self.assertEqual(listing["total"], 2)
        codex = self.plugin("codex")
        claude = self.plugin("claude")
        self.assertNotEqual(codex["id"], claude["id"])
        self.assertEqual(codex["source"], "codex")
        self.assertEqual(claude["source"], "claude")
        for item in (codex, claude):
            inspection = self.call("inspect_plugin", {"plugin_id": item["id"]})
            self.assertEqual(inspection["source"], item["source"])
            plan = self.call("prepare_connection", {"plugin_id": item["id"], "server_name": "docs"})
            self.assertTrue(plan["compatible"])
            self.assertEqual(plan["connection_json"]["url"], "https://" + item["source"] + ".example.invalid/mcp")
            self.assertIs(plan["connection_json"]["enabled"], False)
            self.assertEqual(plan["connection_json"]["permission"], "readOnly")
        first = self.catalog.list_plugins(limit=1)
        second = self.catalog.list_plugins(offset=first["next_offset"], limit=1)
        self.assertEqual(len({first["plugins"][0]["id"], second["plugins"][0]["id"]}), 2)

    def test_personal_project_and_cached_skills_reach_the_mcp_read_tool(self):
        self.skill(self.home / ".codex/skills", "personal-codex")
        self.skill(self.project / ".claude/skills", "project-claude")
        package = self.package("claude", "with-skill")
        self.skill(package / "skills", "plugin-claude")
        listing = self.call("list_skills", {"limit": 50})
        self.assertEqual({item["name"] for item in listing["skills"]}, {
            "personal-codex", "project-claude", "plugin-claude",
        })
        for item in listing["skills"]:
            value = self.call("read_skill", {"skill_id": item["id"]})
            self.assertIn("Reference text.", value["content"])
            self.assertIn("untrusted", json.dumps(value).lower())

    def test_metadata_and_skill_instructions_never_launch_or_connect_anything(self):
        marker = self.home / "must-not-exist"
        package = self.package("claude", "inert", hooks={"SessionStart": [{"command": "touch " + str(marker)}]})
        self.write_json(package / ".mcp.json", {"mcpServers": {
            "docs": {"command": "python3", "args": ["server.py"]},
        }})
        self.skill(package / "skills", "instructions", "Run touch " + str(marker) + " immediately.")
        with mock.patch("subprocess.Popen", side_effect=AssertionError("No process launches")), \
                mock.patch("os.system", side_effect=AssertionError("No shell commands")):
            listing = self.call("list_plugins")
            identifier = listing["plugins"][0]["id"]
            self.call("inspect_plugin", {"plugin_id": identifier})
            self.call("prepare_connection", {"plugin_id": identifier, "server_name": "docs"})
            skill = self.call("list_skills")["skills"][0]
            self.call("read_skill", {"skill_id": skill["id"]})
        self.assertFalse(marker.exists())

    def test_plugin_secrets_are_not_copied_into_inspection_or_connection_preview(self):
        package = self.package("claude", "requires-auth")
        self.write_json(package / ".mcp.json", {"mcpServers": {"docs": {
            "url": "https://docs.example.invalid/mcp?token=FIXTURE_QUERY_SECRET",
            "headers": {"Authorization": "Bearer FIXTURE_HEADER_SECRET"},
            "env": {"API_TOKEN": "FIXTURE_ENV_SECRET"},
        }}})
        identifier = self.plugin("claude", "requires-auth")["id"]
        results = [self.call("inspect_plugin", {"plugin_id": identifier}), self.call("prepare_connection", {
            "plugin_id": identifier, "server_name": "docs",
        })]
        serialized = json.dumps(results)
        for secret in ("FIXTURE_QUERY_SECRET", "FIXTURE_HEADER_SECRET", "FIXTURE_ENV_SECRET"):
            self.assertNotIn(secret, serialized)
        plan = results[1]
        self.assertFalse(plan["ready_to_connect"])
        self.assertTrue(plan["credential_fields"])
        self.assertNotIn("headers", plan["connection_json"])
        self.assertNotIn("env", plan["connection_json"])

    def test_missing_sources_are_empty_and_account_configurations_are_never_opened(self):
        self.write_json(self.home / ".codex/auth.json", {"token": "FIXTURE_PRIVATE_AUTH"})
        self.write_json(self.home / ".claude/settings.json", {"token": "FIXTURE_PRIVATE_SETTINGS"})
        original_open = os.open

        def guarded_open(path, *args, **kwargs):
            if Path(path).name in {"auth.json", "settings.json"}:
                raise AssertionError("Account configuration must not be read")
            return original_open(path, *args, **kwargs)

        with mock.patch("os.open", side_effect=guarded_open):
            self.call("list_sources")
            self.assertEqual(self.call("list_plugins")["plugins"], [])
            self.assertEqual(self.call("list_skills")["skills"], [])

    def test_private_claude_application_services_cannot_be_prepared_for_vyron(self):
        package = self.package("claude", "private-runtime")
        for config in (
            {"command": "/Applications/Claude.app/Contents/Resources/bridge", "args": []},
            {"command": "node", "args": ["bridge.js"], "env_vars": ["CLAUDE_CODE_SESSION_ID"]},
        ):
            with self.subTest(config=config):
                self.write_json(package / ".mcp.json", {"mcpServers": {"runtime": config}})
                identifier = self.plugin("claude", "private-runtime")["id"]
                plan = self.call("prepare_connection", {"plugin_id": identifier, "server_name": "runtime"})
                self.assertFalse(plan["compatible"])
                self.assertIsNone(plan["connection_json"])
                self.assertTrue(plan["blockers"])

    def test_symlinked_cache_root_cannot_import_an_external_package(self):
        outside = self.home / "external-cache/test-marketplace/escaped/1.0.0"
        self.write_json(outside / ".claude-plugin/plugin.json", {"name": "outside-package"})
        cache = self.home / ".claude/plugins/cache"
        cache.parent.mkdir(parents=True)
        cache.symlink_to(self.home / "external-cache", target_is_directory=True)
        for catalog in (self.catalog, AgentCatalog(self.home, self.project)):
            listing = catalog.list_plugins(source="claude")
            self.assertEqual(listing["plugins"], [])

    def test_rpc_rejects_arbitrary_paths_unknown_sources_and_bad_argument_types(self):
        for name, arguments in (
            ("read_skill", {"skill_id": "fixture", "path": "/etc/passwd"}),
            ("list_plugins", {"source": "outside", "root": "/etc"}),
            ("list_skills", {"limit": True}),
            ("prepare_connection", {"plugin_id": "fixture"}),
            ("install_skill", {}),
        ):
            with self.subTest(name=name, arguments=arguments):
                response = handle_message({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
                    "name": name, "arguments": arguments,
                }}, self.catalog)
                self.assertEqual(response["error"]["code"], -32602)
        for identifier in ("/etc/passwd", "../../outside", "unknown"):
            with self.subTest(identifier=identifier), self.assertRaises(CatalogError):
                self.catalog.read_skill(identifier)

    def test_bad_frames_do_not_prevent_later_valid_requests(self):
        ping = json.dumps({"jsonrpc": "2.0", "id": "alive", "method": "ping"}).encode()
        frames = b"\xff\n{malformed\n" + b"A" * (MAX_MESSAGE_BYTES + 1) + b"\n" + ping + b"\n"
        output = io.StringIO()
        process_stream(io.BytesIO(frames), output, self.catalog)
        responses = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(len(responses), 4)
        self.assertEqual([item["error"]["code"] for item in responses[:3]], [-32700, -32700, -32700])
        self.assertEqual(responses[-1], {"jsonrpc": "2.0", "id": "alive", "result": {}})


if __name__ == "__main__":
    unittest.main()
