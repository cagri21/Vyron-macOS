#!/usr/bin/env python3
"""Run the local read-only Codex catalog MCP, or print a one-shot metadata inventory."""

import argparse
import json
from pathlib import Path
import sys


# Keep the signed resource bundle unchanged when Python imports our helper modules.
sys.dont_write_bytecode = True
# The app starts Python with -I. Import only our bundled helper siblings, never plugin code.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from catalog import Catalog
from protocol import process_stream


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-root", type=Path, default=Path.home() / ".codex/plugins/cache")
    parser.add_argument("--inventory", action="store_true", help="Print metadata once without starting MCP.")
    args = parser.parse_args()
    catalog = Catalog(args.cache_root)
    if args.inventory:
        print(json.dumps(catalog.list_plugins(limit=50), indent=2, ensure_ascii=False))
    else:
        process_stream(sys.stdin.buffer, sys.stdout, catalog)


if __name__ == "__main__":
    main()
