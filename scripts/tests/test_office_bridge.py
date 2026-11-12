"""Offline contract tests for the fixed Office bridge; no SDK or engine is installed or launched."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch


BRIDGE = Path(__file__).resolve().parents[2] / "Packages/VyronCore/Office/Resources/vyron_office.py"
SPEC = importlib.util.spec_from_file_location("vyron_office_bridge", BRIDGE)
assert SPEC and SPEC.loader
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class OfficeBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.calls = []
        package = types.ModuleType("deepseek_harness")
        package.__path__ = []
        office = types.ModuleType("deepseek_harness.office")
        office.OfficeOptions = lambda **kwargs: types.SimpleNamespace(**kwargs)
        office.convert = self.convert
        office.recalculate = self.recalculate
        office.render_images = self.render
        runtime = types.ModuleType("deepseek_harness_runtime")
        runtime.resolve_office_launch_args = lambda: self.calls.append(("locate",))
        self.modules = {"deepseek_harness": package, "deepseek_harness.office": office,
                        "deepseek_harness_runtime": runtime}

    def invoke(self, operation, *arguments):
        output = io.StringIO()
        argv = [str(BRIDGE), operation, str(self.directory), "--resource-cache", str(self.directory / "cache")]
        with patch.dict(sys.modules, self.modules), patch.object(sys, "argv", argv + list(arguments)), \
                patch.dict("os.environ", {}, clear=False), contextlib.redirect_stdout(output):
            code = bridge.main()
        lines = output.getvalue().splitlines()
        payload = json.loads(next(line.removeprefix("VYRON_OFFICE_RESULT ") for line in lines
                                  if line.startswith("VYRON_OFFICE_RESULT ")))
        return code, payload

    def convert(self, source, destination, *, options):
        self.calls.append(("convert", source, destination, options))
        Path(destination).write_bytes(b"%PDF-fixture")
        return types.SimpleNamespace(missing_fonts=["FixtureFont"])

    def recalculate(self, source, destination, *, options):
        self.calls.append(("recalculate", source, destination, options))
        Path(destination).write_bytes(b"PK\x03\x04fixture")
        return types.SimpleNamespace(missing_fonts=[])

    def render(self, source, destination, *, pages, max_pages, max_pixels, max_dimension, options):
        self.calls.append(("render", pages, max_pages, max_pixels, max_dimension, options))
        destination = Path(destination)
        destination.mkdir()
        image = destination / "page-0001.png"
        image.write_bytes(b"\x89PNG\r\n\x1a\nfixture")
        (destination / "manifest.json").write_text('{"pages":[1]}')
        return types.SimpleNamespace(images=[types.SimpleNamespace(path=image, width=100, height=100)], missing_fonts=[])

    def test_status_only_locates_prepared_runtime(self):
        code, payload = self.invoke("status")
        self.assertEqual(code, 0)
        self.assertEqual(payload, {"ok": True, "code": "available"})
        self.assertEqual(self.calls, [("locate",)])
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_missing_sdk_returns_setup_result_without_download(self):
        self.modules["deepseek_harness_runtime"] = None
        code, payload = self.invoke("status")
        self.assertEqual(code, 1)
        self.assertEqual(payload["code"], "missing_module")
        self.assertEqual(self.calls, [])

    def test_missing_sidecar_is_distinct_from_missing_sdk(self):
        def missing():
            raise FileNotFoundError("fixture sidecar is absent")
        self.modules["deepseek_harness_runtime"].resolve_office_launch_args = missing
        code, payload = self.invoke("status")
        self.assertEqual(code, 1)
        self.assertEqual(payload["code"], "missing_office")

    def test_conversion_bounds_engine_and_reports_missing_fonts(self):
        source = self.directory / "input.docx"
        source.write_bytes(b"original")
        code, payload = self.invoke("convert")
        self.assertEqual(code, 0)
        self.assertEqual(payload["files"], ["document.pdf"])
        self.assertIn("FixtureFont", payload["warnings"][0])
        options = self.calls[-1][-1]
        self.assertLess(options.timeout_ms, 120_000)
        self.assertEqual(options.max_input_bytes, 64 * 1024 * 1024)
        self.assertEqual(options.max_output_bytes, 128 * 1024 * 1024)
        self.assertEqual(source.read_bytes(), b"original")

    def test_render_uses_returned_images_and_ignores_manifest(self):
        (self.directory / "input.pptx").write_bytes(b"original")
        code, payload = self.invoke("render", "--pages", "1,3")
        self.assertEqual(code, 0)
        self.assertEqual(payload["files"], ["page-0001.png"])
        self.assertNotIn("manifest.json", payload["files"])
        self.assertEqual(self.calls[-1][1:5], ([1, 3], 20, 20 * 1600 * 3200, 3200))

    def test_recalculation_keeps_original_and_writes_new_workbook(self):
        source = self.directory / "input.xlsx"
        source.write_bytes(b"original")
        code, payload = self.invoke("recalculate")
        self.assertEqual(code, 0)
        self.assertEqual(payload["files"], ["workbook.xlsx"])
        self.assertEqual(source.read_bytes(), b"original")

    def test_existing_output_is_preserved(self):
        (self.directory / "input.docx").write_bytes(b"original")
        output = self.directory / "output"
        output.mkdir()
        existing = output / "keep.pdf"
        existing.write_bytes(b"keep")
        code, payload = self.invoke("convert")
        self.assertEqual(code, 1)
        self.assertEqual(payload["code"], "operation_failed")
        self.assertEqual(existing.read_bytes(), b"keep")
        self.assertEqual(self.calls, [("locate",)])

    def test_render_refuses_image_symlink(self):
        (self.directory / "input.pptx").write_bytes(b"original")
        def symlink(*args, **kwargs):
            destination = Path(args[1])
            destination.mkdir()
            image = destination / "page.png"
            image.symlink_to(self.directory / "input.pptx")
            return types.SimpleNamespace(images=[types.SimpleNamespace(path=image)], missing_fonts=[])
        self.modules["deepseek_harness.office"].render_images = symlink
        code, payload = self.invoke("render", "--pages", "1")
        self.assertEqual(code, 1)
        self.assertEqual(payload["code"], "operation_failed")


if __name__ == "__main__":
    unittest.main()
