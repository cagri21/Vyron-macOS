"""Bounded byte-preserving ingress to the fixed, isolated auth backend. No secrets or volumes are loaded."""

from __future__ import annotations

import select
import signal
import socket
import socketserver
import sys
import threading
import time

from .http_transport import BoundedHTTPServer
from .validation import MAX_BODY_BYTES, MAX_HEADER_BYTES

UPSTREAM_HOST = "auth"
UPSTREAM_PORT = 8000
DEADLINE_SECONDS = 5
MAX_REQUEST_BYTES = MAX_BODY_BYTES + MAX_HEADER_BYTES + 2_048
MAX_RESPONSE_BYTES = 65_536


class Relay:
    def __init__(self, client, upstream, clock=time.monotonic, wait=select.select):
        self.client = client
        self.upstream = upstream
        self.clock = clock
        self.wait = wait

    def run(self, deadline=None):
        deadline = self.clock() + DEADLINE_SECONDS if deadline is None else deadline
        client, upstream = self.client, self.upstream
        client.setblocking(False)
        upstream.setblocking(False)
        pending = {client: bytearray(), upstream: bytearray()}
        received = {client: 0, upstream: 0}
        maximum = {client: MAX_REQUEST_BYTES, upstream: MAX_RESPONSE_BYTES}
        peer = {client: upstream, upstream: client}
        client_open = upstream_open = True
        upload_closed = False
        while upstream_open or pending[client]:
            remaining = deadline - self.clock()
            if remaining <= 0:
                raise TimeoutError()
            readers = [upstream] if upstream_open else []
            if client_open and upstream_open:
                readers.append(client)
            writers = [connection for connection, data in pending.items() if data]
            readable, writable, _ = self.wait(readers, writers, [], remaining)
            if self.clock() >= deadline or not readable and not writable:
                raise TimeoutError()
            for connection in readable:
                try:
                    data = connection.recv(4_096)
                except BlockingIOError:
                    continue
                if data:
                    received[connection] += len(data)
                    if received[connection] > maximum[connection]:
                        raise ValueError("relay byte limit")
                    pending[peer[connection]].extend(data)
                elif connection is upstream:
                    upstream_open = False
                    pending[upstream].clear()
                else:
                    client_open = False
            for connection in writable:
                if not pending[connection]:
                    continue
                try:
                    count = connection.send(pending[connection])
                except BlockingIOError:
                    continue
                if count <= 0:
                    raise ConnectionError()
                del pending[connection][:count]
            if not client_open and not pending[upstream] and not upload_closed:
                try:
                    upstream.shutdown(socket.SHUT_WR)
                except OSError:
                    pass  # The backend may already have closed its one HTTP response.
                upload_closed = True


class RelayHandler(socketserver.BaseRequestHandler):
    def handle(self):
        deadline = time.monotonic() + DEADLINE_SECONDS
        try:
            # DNS resolution happens once at startup, before any accepted connection's deadline begins.
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as upstream:
                upstream.settimeout(max(0.001, deadline - time.monotonic()))
                upstream.connect((self.server.upstream_ipv4, UPSTREAM_PORT))
                Relay(self.request, upstream).run(deadline)
        except (OSError, ValueError):
            # Close the connection rather than append an error to an already partially relayed response.
            return


def main() -> int:
    try:
        # A request URL, CONNECT target, environment value, or command argument never selects this destination.
        upstream_ipv4 = socket.gethostbyname(UPSTREAM_HOST)
        with BoundedHTTPServer(("0.0.0.0", 8000), None, handler_class=RelayHandler) as server:
            server.upstream_ipv4 = upstream_ipv4

            def stop(_signal, _frame):
                threading.Thread(target=server.shutdown, daemon=True).start()

            signal.signal(signal.SIGTERM, stop)
            signal.signal(signal.SIGINT, stop)
            print("Vyron local authentication ingress ready.", flush=True)
            server.serve_forever(poll_interval=0.25)
        return 0
    except Exception:
        print("Vyron local authentication ingress could not start.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
