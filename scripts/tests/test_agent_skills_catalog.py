"""Offline skills-catalog regression checks; no MCP process or provider is started."""

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


RESOURCES = Path(__file__).resolve().parents[2] / "Apps/Vyron/Resources/CodexCatalog"
sys.path.insert(0, str(RESOURCES))
import skills_catalog
from security import CatalogError
from skill_metadata import parse_metadata
from skills_catalog import SkillsCatalog


class AgentSkillsCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vyron-skill-catalog-tests-")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.project = self.root / "project"
        self.home.mkdir()
        self.project.mkdir()
        self.catalog = SkillsCatalog(self.home, self.project)

    def tearDown(self):
        self.temporary.cleanup()

    def write_skill(self, relative, name="Review", description="Review local changes.", base=None):
        path = (base or self.home) / relative / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"---\nname: {name}\ndescription: {description}\n---\nReference body.\n")
        return path

    def test_discovers_personal_system_project_and_plugin_skills_with_source_scope(self):
        paths = [
            (".codex/skills/review", "Codex", "codex", "personal", self.home),
            (".codex/skills/.system/tool", "System", "codex", "personal", self.home),
            (".claude/skills/review", "Claude", "claude", "personal", self.home),
            (".agents/skills/shared", "Shared", "shared", "personal", self.home),
            (".claude/skills/project", "Project", "claude", "project", self.project),
            (".codex/plugins/cache/market/pkg/1/skills/example", "Cache", "codex", "plugin", self.home),
            (".claude/plugins/cache/market/pkg/1/skills/example", "Claude cache", "claude", "plugin", self.home),
        ]
        for relative, name, _source, _scope, base in paths:
            self.write_skill(relative, name=name, base=base)
        result = self.catalog.list_skills()
        self.assertEqual(result["total"], len(paths))
        entries = {item["name"]: item for item in result["skills"]}
        for _relative, name, source, scope, _base in paths:
            self.assertEqual((entries[name]["source"], entries[name]["scope"]), (source, scope))
            self.assertEqual(len(entries[name]["id"]), 64)
        self.assertFalse(result["scan_limited"])
        self.assertTrue(result["untrusted"])

    def test_search_filters_pagination_and_distinct_same_name_paths(self):
        self.write_skill(".codex/skills/a", name="Same", description="Inspect Swift.")
        self.write_skill(".claude/skills/b", name="Same", description="Inspect Python.")
        self.write_skill(".agents/skills/c", name="Other", base=self.project)
        result = self.catalog.list_skills(limit=1)
        self.assertEqual(result["total"], 3)
        self.assertEqual(result["next_offset"], 1)
        following = self.catalog.list_skills(offset=1, limit=2)
        self.assertIsNone(following["next_offset"])
        self.assertEqual(len({item["id"] for item in result["skills"] + following["skills"]}), 3)
        self.assertEqual(self.catalog.list_skills(query="  swift  ")["total"], 1)
        self.assertEqual(self.catalog.list_skills(source="claude")["total"], 1)
        self.assertEqual(self.catalog.list_skills(scope="project")["total"], 1)
        self.assertEqual(self.catalog.list_skills(source="shared", scope="project")["total"], 1)

    def test_read_skill_returns_inert_bounded_text_and_refuses_unlisted_ids(self):
        path = self.write_skill(".codex/skills/review")
        item = self.catalog.list_skills()["skills"][0]
        read = self.catalog.read_skill(item["id"])
        self.assertEqual(read["content"], path.read_text())
        self.assertTrue(read["untrusted"])
        self.assertTrue(read["reference_only"])
        self.assertFalse(read["truncated"])
        for identifier in ("/etc/passwd", "../SKILL.md", "0" * 64, None, []):
            with self.subTest(identifier=identifier), self.assertRaises(CatalogError):
                self.catalog.read_skill(identifier)
        path.unlink()
        with self.assertRaises(CatalogError):
            self.catalog.read_skill(item["id"])

    def test_oversize_preview_is_bounded_and_preserves_utf8_at_byte_boundary(self):
        path = self.write_skill(".codex/skills/large")
        prefix = path.read_bytes()
        path.write_bytes(prefix + b"A" * (skills_catalog.MAX_DOCUMENT_BYTES - len(prefix) - 1)
                         + "🙂".encode("utf-8") + b"after")
        item = self.catalog.list_skills()["skills"][0]
        self.assertTrue(item["truncated"])
        result = self.catalog.read_skill(item["id"])
        self.assertTrue(result["truncated"])
        self.assertLessEqual(len(result["content"].encode("utf-8")), skills_catalog.MAX_DOCUMENT_BYTES)
        self.assertNotIn("after", result["content"])

    def test_read_preview_fits_serialized_host_budget_with_escaped_content(self):
        path = self.write_skill(".codex/skills/escaped")
        original = path.read_text() + '\\"\n\t' * 8_000
        self.assertLess(len(original.encode("utf-8")), skills_catalog.MAX_DOCUMENT_BYTES)
        path.write_text(original)
        item = self.catalog.list_skills()["skills"][0]
        self.assertFalse(item["truncated"], "The source-byte limit alone does not shorten this file.")

        result = self.catalog.read_skill(item["id"])

        serialized = json.dumps(result, ensure_ascii=False)
        self.assertLessEqual(len(serialized), skills_catalog.MAX_RESULT_CHARACTERS)
        self.assertEqual(json.loads(serialized), result)
        self.assertTrue(result["truncated"])
        self.assertTrue(original.startswith(result["content"]))
        self.assertLess(len(result["content"]), len(original))
        self.assertEqual(result["id"], item["id"])
        self.assertTrue(result["reference_only"])

    def test_metadata_pages_fit_host_budget_and_advance_by_returned_count(self):
        for index in range(35):
            self.write_skill(f".codex/skills/long-{index:02d}", name=f"Skill {index:02d}",
                             description='"' + '\\\\' * 1_000 + '"')
        offset, seen = 0, []
        while True:
            result = self.catalog.list_skills(offset=offset, limit=50)
            serialized = json.dumps(result, ensure_ascii=False)
            self.assertLessEqual(len(serialized), skills_catalog.MAX_RESULT_CHARACTERS)
            self.assertEqual(result["total"], 35)
            self.assertTrue(result["skills"])
            self.assertLess(len(result["skills"]), 35)
            seen.extend(item["id"] for item in result["skills"])
            if result["next_offset"] is None:
                break
            self.assertEqual(result["next_offset"], offset + len(result["skills"]))
            offset = result["next_offset"]
        self.assertEqual(len(seen), 35)
        self.assertEqual(len(set(seen)), 35)

    def test_symlinked_root_ancestor_child_and_document_are_not_followed(self):
        outside = self.root / "outside"
        self.write_skill("review", base=outside)
        root = self.home / ".codex/skills"
        root.parent.mkdir(parents=True)
        root.symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.catalog.list_skills()["skills"], [])
        root.unlink()
        root.mkdir()
        (root / "linked").symlink_to(outside, target_is_directory=True)
        document = root / "document/SKILL.md"
        document.parent.mkdir()
        document.symlink_to(outside / "review/SKILL.md")
        self.assertEqual(self.catalog.list_skills()["skills"], [])
        self.home.rename(self.root / "real-home")
        self.home.symlink_to(self.root / "real-home", target_is_directory=True)
        self.assertEqual(self.catalog.list_skills()["skills"], [])

    def test_document_replaced_with_link_between_discovery_and_read_is_rejected(self):
        path = self.write_skill(".codex/skills/review")
        outside = self.root / "outside.md"
        outside.write_text("SECRET_OUTSIDE_DOCUMENT")
        original = self.catalog._inventory()
        identity = original[0][0][0]["id"]
        path.unlink()
        path.symlink_to(outside)
        with mock.patch.object(self.catalog, "_inventory", return_value=original):
            with self.assertRaises(CatalogError):
                self.catalog.read_skill(identity)

    def test_fifo_invalid_encoding_and_malformed_metadata_are_skipped(self):
        fifo = self.home / ".codex/skills/fifo/SKILL.md"
        fifo.parent.mkdir(parents=True)
        os.mkfifo(fifo)
        invalid = self.write_skill(".codex/skills/invalid")
        invalid.write_bytes(b"\xffinvalid")
        malformed = self.write_skill(".codex/skills/malformed")
        malformed.write_text("---\nname: [unsupported]\n---\n")
        self.write_skill(".codex/skills/valid")
        result = self.catalog.list_skills()
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["skipped_count"], 3)

    def test_depth_limit_does_not_prevent_other_roots_and_entry_limit_is_explicit(self):
        self.write_skill(".codex/skills/a/b/c/deep", name="Too deep")
        self.write_skill(".claude/skills/shallow", name="Shallow")
        with mock.patch.object(skills_catalog, "MAX_DEPTH", 3):
            result = self.catalog.list_skills()
        self.assertTrue(result["scan_limited"])
        self.assertEqual([item["name"] for item in result["skills"]], ["Shallow"])
        with mock.patch.object(skills_catalog, "MAX_ENTRIES", 1):
            result = self.catalog.list_skills()
        self.assertTrue(result["scan_limited"])

    def test_missing_roots_and_invalid_filter_bounds_are_handled(self):
        self.assertEqual(self.catalog.list_skills()["skills"], [])
        cases = [{"source": []}, {"source": "remote"}, {"scope": []}, {"scope": "unknown"},
                 {"query": "x" * 201}, {"query": None}, {"offset": -1}, {"offset": True},
                 {"limit": 0}, {"limit": 51}, {"limit": True}]
        for arguments in cases:
            with self.subTest(arguments=arguments), self.assertRaises(CatalogError):
                self.catalog.list_skills(**arguments)

    def test_metadata_supports_blocks_quoted_comments_and_multiline_scalars(self):
        folded = parse_metadata("---\nname: 'Review' # comment\ndescription: >-\n  Review changes\n  with context.\n---\n", "fallback")
        self.assertEqual(folded, {"name": "Review", "description": "Review changes with context."})
        quoted = parse_metadata('---\nname: Review\ndescription: "Inspect\n  safely." # note\n---\n', "fallback")
        self.assertEqual(quoted["description"], "Inspect safely.")
        plain = parse_metadata("---\nname: Review\ndescription: Inspect\n  safely.\n---\n", "fallback")
        self.assertEqual(plain["description"], "Inspect safely.")
        literal = parse_metadata("---\nname: Review\ndescription: |\n  First\n  Second\n---\n", "fallback")
        self.assertEqual(literal["description"], "First\nSecond")
        self.assertEqual(parse_metadata("# Skill\nUseful body.\n", "Fallback")["name"], "Fallback")


if __name__ == "__main__":
    unittest.main()
