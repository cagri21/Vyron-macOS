"""Small, bounded HTTP/1 transport. Connections are never reused and requests are never logged."""

from __future__ import annotations

from http import HTTPStatus
import json
import re
import socket
import socketserver
import threading
import time

from .api import Application, Request, Response, error
from .validation import MAX_BODY_BYTES, MAX_HEADER_BYTES, MAX_HEADERS

SOCKET_TIMEOUT = 5
MAX_WORKERS = 8


class HTTPFailure(Exception):
    def __init__(self, status: int):
        self.status = status


class DeadlineReader:
    """Bound raw receives by total elapsed time, even when a peer keeps sending tiny fragments."""

    def __init__(self, connection, timeout=SOCKET_TIMEOUT, clock=time.monotonic):
        self.connection = connection
        self.clock = clock
        self.deadline = clock() + timeout
        self.buffer = bytearray()

    def _remaining(self):
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise TimeoutError()
        return remaining

    def _receive(self, maximum):
        self.connection.settimeout(self._remaining())
        chunk = self.connection.recv(min(maximum, 4_096))
        self.buffer.extend(chunk)
        return bool(chunk)

    def _take(self, count):
        value = bytes(self.buffer[:count])
        del self.buffer[:count]
        return value

    def readline(self, maximum):
        self._remaining()
        while True:
            newline = self.buffer.find(b"\n", 0, maximum)
            if newline >= 0:
                return self._take(newline + 1)
            if len(self.buffer) >= maximum:
                return self._take(maximum)
            if not self._receive(maximum - len(self.buffer)):
                return self._take(len(self.buffer))

    def read(self, size):
        self._remaining()
        while len(self.buffer) < size:
            if not self._receive(size - len(self.buffer)):
                break
        return self._take(size)


def read_request(stream) -> Request:
    line = stream.readline(2_050)
    if len(line) > 2_048 or not line.endswith(b"\r\n"):
        raise HTTPFailure(400)
    try:
        method, target, version = line[:-2].decode("ascii").split(" ")
    except (ValueError, UnicodeError) as exception:
        raise HTTPFailure(400) from exception
    if not re.fullmatch(r"[A-Z]{1,12}", method) or version not in {"HTTP/1.0", "HTTP/1.1"} \
        or not target.startswith("/") or len(target) > 1_024 or any(ord(char) < 33 for char in target):
        raise HTTPFailure(400)
    headers = []
    names = set()
    total = 0
    while True:
        line = stream.readline(2_050)
        total += len(line)
        if len(line) > 2_048 or total > MAX_HEADER_BYTES:
            raise HTTPFailure(431)
        if line == b"\r\n":
            break
        if not line.endswith(b"\r\n") or len(headers) >= MAX_HEADERS:
            raise HTTPFailure(431)
        try:
            name, value = line[:-2].decode("latin-1").split(":", 1)
        except ValueError as exception:
            raise HTTPFailure(400) from exception
        if not re.fullmatch(r"[!#$%&'*+.^_`|~0-9A-Za-z-]+", name) or name.lower() in names:
            raise HTTPFailure(400)
        value = value.strip(" ")
        if any(ord(char) < 32 or ord(char) == 127 for char in value):
            raise HTTPFailure(400)
        names.add(name.lower())
        headers.append((name, value))
    values = {name.lower(): value for name, value in headers}
    if "transfer-encoding" in values:
        raise HTTPFailure(400)
    if "expect" in values:
        raise HTTPFailure(417)
    length = values.get("content-length", "0")
    if not re.fullmatch(r"[0-9]{1,6}", length):
        raise HTTPFailure(400)
    size = int(length)
    if size > MAX_BODY_BYTES:
        raise HTTPFailure(413)
    if method in {"PUT", "DELETE"} and "content-length" not in values:
        raise HTTPFailure(411)
    if method == "GET" and size:
        raise HTTPFailure(400)
    body = stream.read(size) if size else b""
    if len(body) != size:
        raise HTTPFailure(400)
    return Request(method, target, tuple(headers), body)


def response_bytes(response: Response) -> bytes:
    body = json.dumps(response.payload, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    status = HTTPStatus(response.status)
    headers = (
        f"HTTP/1.1 {status.value} {status.phrase}\r\n"
        "Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Connection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
    )
    return headers.encode("ascii") + body


class RequestHandler(socketserver.BaseRequestHandler):
    def handle(self):
        connection = self.request
        try:
            request = read_request(DeadlineReader(connection))
            response = self.server.application.dispatch(request)
        except HTTPFailure as failure:
            response = error(failure.status, "invalid_request")
        except (TimeoutError, socket.timeout):
            response = error(408, "request_timeout")
        except Exception:
            # Never include exception details, request headers, or body in an error or log.
            response = error(500, "internal_error")
        try:
            connection.settimeout(SOCKET_TIMEOUT)
            connection.sendall(response_bytes(response))
        except (OSError, TimeoutError):
            pass  # A closed client needs no retry or diagnostic containing request data.


class BoundedHTTPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 16

    def __init__(self, address, application: Application, handler_class=RequestHandler):
        self.application = application
        self._workers = threading.BoundedSemaphore(MAX_WORKERS)
        super().__init__(address, handler_class)

    def process_request(self, request, client_address):
        if not self._workers.acquire(blocking=False):
            try:
                request.settimeout(SOCKET_TIMEOUT)
                request.sendall(response_bytes(error(503, "service_busy")))
            except OSError:
                pass
            finally:
                self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self._workers.release()
            self.shutdown_request(request)

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._workers.release()

    def handle_error(self, request, client_address):
        # socketserver's default traceback can expose request-local data; responses are sanitized instead.
        return
