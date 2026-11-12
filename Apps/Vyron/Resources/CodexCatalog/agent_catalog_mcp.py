#!/usr/bin/env python3
"""Run the local read-only Claude/Codex catalog MCP, or print a one-shot inventory."""

import argparse
import json
from pathlib import Path
import sys


# Keep signed resource bundles unchanged. Import trusted bundled siblings only.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from agent_catalog import AgentCatalog
from protocol import process_stream
from security import CatalogError


def absolute_path(value):
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("Use an absolute local folder path.")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home-root", type=absolute_path, default=Path.home(),
                        help="Home directory containing .codex, .claude, and .agents.")
    parser.add_argument("--project-root", type=absolute_path,
                        help="Optional project directory whose skill folders should be included.")
    parser.add_argument("--inventory", action="store_true", help="Print metadata once without starting MCP.")
    args = parser.parse_args()
    try:
        catalog = AgentCatalog(args.home_root, args.project_root)
        if args.inventory:
            inventory = {
                "sources": catalog.list_sources(),
                "skills": catalog.list_skills(limit=50),
                "plugins": catalog.list_plugins(limit=50),
            }
            print(json.dumps(inventory, indent=2, ensure_ascii=False, allow_nan=False))
        else:
            process_stream(sys.stdin.buffer, sys.stdout, catalog)
    except CatalogError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
