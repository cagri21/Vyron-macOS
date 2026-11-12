"""Container entrypoint; no credentials or requests are written to logs."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import signal
import stat
import sys
import threading

from .api import Application
from .http_transport import BoundedHTTPServer
from .storage import CredentialStore
from .validation import bearer_token


def read_bootstrap_token(path: Path) -> str:
    for component in (path, *path.parents):
        if component.is_symlink():
            raise ValueError("unsafe bootstrap file")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077 \
            or not 43 <= info.st_size <= 44:
            raise ValueError("unsafe bootstrap file")
        with os.fdopen(descriptor, "r", encoding="ascii") as stream:
            descriptor = -1
            return bearer_token(stream.read(45).removesuffix("\n"))
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Vyron's encrypted local credential backup.")
    parser.add_argument("--data-dir", type=Path, default=Path("/data"))
    parser.add_argument("--token-file", type=Path, default=Path("/run/secrets/vyron-auth"))
    arguments = parser.parse_args()
    try:
        os.umask(0o077)
        token = read_bootstrap_token(arguments.token_file)
        application = Application(CredentialStore(arguments.data_dir), token)
        with BoundedHTTPServer(("0.0.0.0", 8000), application) as server:
            def stop(_signal, _frame):
                threading.Thread(target=server.shutdown, daemon=True).start()

            signal.signal(signal.SIGTERM, stop)
            signal.signal(signal.SIGINT, stop)
            print("Vyron local authentication service ready.", flush=True)
            server.serve_forever(poll_interval=0.25)
        return 0
    except Exception:
        print("Vyron local authentication service could not start.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
