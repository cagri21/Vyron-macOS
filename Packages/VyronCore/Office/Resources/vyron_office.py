"""Fixed, offline bridge to the optional standalone DeepSeek Harness Office API.

This helper does not create an agent, read API keys, or download dependencies.
Vyron launches it with isolated Python and its network-denied process runner.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def result(ok: bool, code: str, files: list[str] | None = None, warnings: list[str] | None = None) -> None:
    payload = {"ok": ok, "code": code}
    if files is not None:
        payload["files"] = files
    if warnings:
        payload["warnings"] = warnings
    print("VYRON_OFFICE_RESULT " + json.dumps(payload, separators=(",", ":")), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("status", "convert", "render", "recalculate"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("--resource-cache", type=Path, required=True)
    parser.add_argument("--pages", default="")
    arguments = parser.parse_args()
    os.environ["DSH_RESOURCE_CACHE"] = str(arguments.resource_cache)
    try:
        from deepseek_harness_runtime import resolve_office_launch_args
        from deepseek_harness.office import OfficeOptions, convert, recalculate, render_images
    except ImportError:
        result(False, "missing_module")
        return 1
    try:
        # This lookup never downloads resources. It requires an already prepared sidecar.
        resolve_office_launch_args()
    except (FileNotFoundError, ValueError):
        result(False, "missing_office")
        return 1
    if arguments.operation == "status":
        result(True, "available")
        return 0
    try:
        directory = arguments.directory.resolve(strict=True)
        inputs = list(directory.glob("input.*"))
        if len(inputs) != 1 or inputs[0].is_symlink() or not inputs[0].is_file():
            raise ValueError("Invalid staged input")
        source = inputs[0]
        destination = directory / "output"
        if destination.exists() or destination.is_symlink():
            raise ValueError("Output exists")
        options = OfficeOptions(timeout_ms=90_000, max_input_bytes=64 * 1024 * 1024, max_output_bytes=128 * 1024 * 1024)
        if arguments.operation == "render":
            pages = [int(value) for value in arguments.pages.split(",") if value]
            if not pages or len(pages) > 20 or len(set(pages)) != len(pages) or min(pages) < 1:
                raise ValueError("Invalid pages")
            processed = render_images(
                str(source), str(destination), pages=pages, max_pages=20,
                max_pixels=20 * 1600 * 3200, max_dimension=3200, options=options,
            )
            # The API also creates manifest.json. Publish only its explicitly returned PNG images.
            files = [Path(image.path) for image in processed.images]
            if any(path.parent.resolve() != destination.resolve() for path in files):
                raise ValueError("Output outside staged directory")
        else:
            destination.mkdir(mode=0o700)
            if arguments.operation == "convert":
                processed = convert(str(source), str(destination / "document.pdf"), options=options)
            else:
                processed = recalculate(str(source), str(destination / "workbook.xlsx"), options=options)
            files = sorted(destination.iterdir())
        if not files or len(files) > 20 or any(path.is_symlink() or not path.is_file() for path in files):
            raise ValueError("Invalid outputs")
        if arguments.operation == "render" and any(path.suffix.lower() != ".png" for path in files):
            raise ValueError("Non-PNG preview")
        if sum(path.stat().st_size for path in files) > 128 * 1024 * 1024:
            raise ValueError("Oversized outputs")
        fonts = [str(font)[:100] for font in getattr(processed, "missing_fonts", ())][:20]
        warnings = ["Missing fonts may change document layout: " + ", ".join(fonts)] if fonts else []
        result(True, "completed", [path.name for path in files], warnings)
        return 0
    except Exception:
        # Avoid returning document content or private engine diagnostics to the model.
        result(False, "operation_failed")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
