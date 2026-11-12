from io import BytesIO
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local_auth.api import Response
from local_auth.http_transport import DeadlineReader, HTTPFailure, read_request, response_bytes
from local_auth.validation import MAX_BODY_BYTES


class TransportTests(unittest.TestCase):
    def test_absolute_deadline_expires_despite_regular_byte_progress(self):
        class SlowSocket:
            def __init__(self):
                self.now = 0
                self.timeouts = []
                self.receives = 0

            def settimeout(self, value):
                self.timeouts.append(value)

            def recv(self, maximum):
                self.receives += 1
                self.now += 2.5
                return b"x"

        connection = SlowSocket()
        reader = DeadlineReader(connection, timeout=5, clock=lambda: connection.now)
        with self.assertRaises(TimeoutError):
            reader.read(3)
        self.assertEqual(connection.receives, 2)
        self.assertEqual(connection.timeouts, [5, 2.5])

    def test_deadline_reader_preserves_header_and_body_framing(self):
        class BufferedSocket:
            def __init__(self, data):
                self.source = BytesIO(data)

            def settimeout(self, value):
                pass

            def recv(self, maximum):
                return self.source.read(min(maximum, 3))

        connection = BufferedSocket(
            b"PUT /example HTTP/1.1\r\nHost: localhost:8000\r\nContent-Length: 2\r\n\r\n{}"
        )
        request = read_request(DeadlineReader(connection))
        self.assertEqual(request.method, "PUT")
        self.assertEqual(request.body, b"{}")

    def test_reads_one_bounded_json_request_without_consuming_a_second_request(self):
        body = b'{"expected_revision":0}'
        stream = BytesIO(
            b"DELETE /v1/credentials/00000000-0000-0000-0000-000000000000 HTTP/1.1\r\n"
            b"Host: 127.0.0.1:8327\r\nContent-Type: application/json\r\n"
            + b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body + b"next request"
        )
        request = read_request(stream)
        self.assertEqual(request.method, "DELETE")
        self.assertEqual(request.body, body)
        self.assertEqual(stream.read(), b"next request")

    def test_rejects_ambiguous_or_unbounded_framing_before_processing(self):
        cases = [
            (b"GET /health HTTP/1.1\n\n", 400),
            (b"GET /health HTTP/1.1\r\nHost: localhost:8000\r\nHost: other\r\n\r\n", 400),
            (b"PUT /x HTTP/1.1\r\nHost: localhost:8000\r\nContent-Length: 2\r\nContent-Length: 4\r\n\r\n{}", 400),
            (b"PUT /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", 400),
            (b"PUT /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n", 400),
            (b"PUT /x HTTP/1.1\r\n\r\n", 411),
            (b"GET /health HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}", 400),
            (b"PUT /x HTTP/1.1\r\nExpect: 100-continue\r\nContent-Length: 2\r\n\r\n{}", 417),
            (b"GET /health HTTP/1.1\r\n Folded: rejected\r\n\r\n", 400),
            (b"GET /health HTTP/1.1\r\nX-Control: bad\x00value\r\n\r\n", 400),
            (b"PUT /x HTTP/1.1\r\nContent-Length: 4\r\n\r\n{}", 400),
            (b"GET /" + b"a" * 2_049 + b" HTTP/1.1\r\n\r\n", 400),
            (b"GET /health HTTP/1.1\r\nX-Large: " + b"x" * 2_049 + b"\r\n\r\n", 431),
            (b"GET /health HTTP/1.1\r\n" + b"".join(
                ("X-" + str(index) + ": x\r\n").encode() for index in range(33)
            ) + b"\r\n", 431),
            (b"PUT /x HTTP/1.1\r\nContent-Length: " + str(MAX_BODY_BYTES + 1).encode() + b"\r\n\r\n", 413)
        ]
        for value, expected in cases:
            with self.subTest(status=expected, size=len(value)):
                with self.assertRaises(HTTPFailure) as failure:
                    read_request(BytesIO(value))
                self.assertEqual(failure.exception.status, expected)

    def test_responses_are_noncacheable_closed_json_without_cors_or_server_details(self):
        encoded = response_bytes(Response(401, {"error": "unauthorized"}))
        headers, body = encoded.split(b"\r\n\r\n", 1)
        self.assertIn(b"HTTP/1.1 401 Unauthorized", headers)
        self.assertIn(b"Connection: close", headers)
        self.assertIn(b"Cache-Control: no-store", headers)
        self.assertIn(b"X-Content-Type-Options: nosniff", headers)
        self.assertNotIn(b"Access-Control", headers)
        self.assertNotIn(b"Server:", headers)
        self.assertEqual(body, b'{"error":"unauthorized"}')
        self.assertIn(("Content-Length: " + str(len(body))).encode(), headers)


if __name__ == "__main__":
    unittest.main()
