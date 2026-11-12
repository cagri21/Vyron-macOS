from io import BytesIO, StringIO
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local_auth.relay import MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES, Relay, RelayHandler
from local_auth.http_transport import HTTPFailure, read_request


class FakeConnection:
    def __init__(self, incoming, maximum_write=3):
        self.incoming = BytesIO(incoming)
        self.sent = bytearray()
        self.maximum_write = maximum_write
        self.half_closed = False

    def setblocking(self, value):
        pass

    def recv(self, maximum):
        return self.incoming.read(min(maximum, 7))

    def send(self, data):
        count = min(len(data), self.maximum_write)
        self.sent.extend(data[:count])
        return count

    def shutdown(self, how):
        self.half_closed = True


class RelayTests(unittest.TestCase):
    def run_relay(self, request, response, clock=lambda: 0):
        client = FakeConnection(request)
        upstream = FakeConnection(response)

        def wait(readers, writers, errors, timeout):
            readable = [connection for connection in readers
                        if connection is client or len(upstream.sent) >= len(request)]
            return readable, writers, []

        Relay(client, upstream, clock=clock, wait=wait).run()
        return client, upstream

    def test_bytes_and_framing_are_preserved_under_fragmented_reads_and_partial_writes(self):
        request = (b"PUT /v1/credentials/00000000-0000-0000-0000-000000000000 HTTP/1.1\r\n"
                   b"Host: 127.0.0.1:8327\r\nAuthorization: Bearer test-only\r\nContent-Length: 2\r\n\r\n{}")
        response = b'HTTP/1.1 200 OK\r\nContent-Length: 14\r\nConnection: close\r\n\r\n{"revision":1}'
        output = StringIO()
        with redirect_stdout(output), redirect_stderr(output):
            client, upstream = self.run_relay(request, response)
        self.assertEqual(bytes(upstream.sent), request)
        self.assertEqual(bytes(client.sent), response)
        self.assertTrue(upstream.half_closed)
        self.assertEqual(output.getvalue(), "")

    def test_request_and_response_byte_budgets_fail_closed(self):
        for request, response in ((b"x" * (MAX_REQUEST_BYTES + 1), b""),
                                  (b"GET /health HTTP/1.1\r\n\r\n", b"x" * (MAX_RESPONSE_BYTES + 1))):
            with self.subTest(request_size=len(request), response_size=len(response)):
                with self.assertRaises(ValueError):
                    self.run_relay(request, response)

    def test_absolute_deadline_expires_even_when_a_peer_continues_making_progress(self):
        client = FakeConnection(b"x" * 100)
        upstream = FakeConnection(b"")
        now = [0]

        def wait(readers, writers, errors, timeout):
            now[0] += 2
            return [client], writers, []

        with self.assertRaises(TimeoutError):
            Relay(client, upstream, clock=lambda: now[0], wait=wait).run()
        self.assertLess(len(upstream.sent), 100)

    def test_stalled_peers_do_not_leave_a_relay_waiting_forever(self):
        client, upstream = FakeConnection(b""), FakeConnection(b"")
        with self.assertRaises(TimeoutError):
            Relay(client, upstream, clock=lambda: 0, wait=lambda *_: ([], [], [])).run()

    def test_request_targets_cannot_select_an_upstream_or_create_a_connect_tunnel(self):
        client = FakeConnection(b"CONNECT attacker.example:443 HTTP/1.1\r\n\r\n")
        upstream = mock.MagicMock()
        upstream.__enter__.return_value = upstream
        server = SimpleNamespace(upstream_ipv4="172.18.0.2")
        with mock.patch("local_auth.relay.socket.socket", return_value=upstream), \
            mock.patch("local_auth.relay.Relay") as relay:
            RelayHandler(client, ("127.0.0.1", 1234), server)
        upstream.connect.assert_called_once_with(("172.18.0.2", 8000))
        relay.assert_called_once_with(client, upstream)
        with self.assertRaises(HTTPFailure):
            read_request(BytesIO(b"CONNECT attacker.example:443 HTTP/1.1\r\nHost: localhost:8000\r\n\r\n"))


if __name__ == "__main__":
    unittest.main()
