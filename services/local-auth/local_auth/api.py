"""Pure request routing, authentication, and bounded JSON validation."""

from __future__ import annotations

from dataclasses import dataclass
import hmac
import re
import sqlite3

from . import SCHEMA_VERSION, SERVICE_NAME, VERSION
from .storage import CapacityReached, CredentialStore, RevisionConflict
from .validation import MAX_BODY_BYTES, MAX_HEADER_BYTES, MAX_HEADERS
from .validation import bearer_token, encrypted_payload, json_object, record_id, revision

ALLOWED_HOSTS = frozenset({"127.0.0.1:8327", "localhost:8327", "127.0.0.1:8000", "localhost:8000"})


@dataclass(frozen=True)
class Request:
    method: str
    target: str
    headers: tuple[tuple[str, str], ...]
    body: bytes = b""


@dataclass(frozen=True)
class Response:
    status: int
    payload: dict


def error(status: int, code: str) -> Response:
    return Response(status, {"error": code})


class Application:
    def __init__(self, store: CredentialStore, token: str):
        self.store = store
        self._token = bearer_token(token).encode("ascii")

    def dispatch(self, request: Request) -> Response:
        try:
            return self._dispatch(request)
        except (ValueError, TypeError, UnicodeError, RecursionError):
            return error(400, "invalid_request")
        except RevisionConflict:
            return error(409, "revision_conflict")
        except CapacityReached:
            return error(507, "record_limit_reached")
        except (sqlite3.Error, OSError):
            return error(503, "storage_unavailable")

    def _dispatch(self, request: Request) -> Response:
        if len(request.body) > MAX_BODY_BYTES:
            return error(413, "request_too_large")
        if len(request.headers) > MAX_HEADERS:
            return error(431, "headers_too_large")
        if sum(len(key) + len(value) + 4 for key, value in request.headers) > MAX_HEADER_BYTES:
            return error(431, "headers_too_large")
        headers = {}
        for key, value in request.headers:
            name = key.lower()
            if not re.fullmatch(r"[!#$%&'*+.^_`|~0-9A-Za-z-]+", key) or name in headers \
                or any(ord(char) < 32 or ord(char) == 127 for char in key + value):
                return error(400, "invalid_request")
            headers[name] = value
        if "origin" in headers or "referer" in headers or headers.get("host") not in ALLOWED_HOSTS:
            return error(401, "unauthorized")
        if "transfer-encoding" in headers:
            return error(400, "invalid_request")
        if "content-length" in headers and (not re.fullmatch(r"[0-9]{1,6}", headers["content-length"])
            or int(headers["content-length"]) != len(request.body)):
            return error(400, "invalid_request")
        if request.method == "GET" and request.target == "/health" and not request.body:
            return Response(200, {
                "status": "ok", "service": SERVICE_NAME, "schema_version": SCHEMA_VERSION, "version": VERSION
            })
        supplied = headers.get("authorization", "").encode("utf-8")
        if not hmac.compare_digest(supplied, b"Bearer " + self._token):
            return error(401, "unauthorized")
        if request.method == "GET" and request.target == "/v1/session" and not request.body:
            return Response(200, {
                "service": SERVICE_NAME, "schema_version": SCHEMA_VERSION, "instance_id": self.store.instance_id,
                "has_encrypted_credentials": self.store.has_encrypted_credentials()
            })
        prefix = "/v1/credentials/"
        if not request.target.startswith(prefix):
            return error(404, "not_found")
        try:
            identifier = record_id(request.target[len(prefix):])
        except ValueError:
            return error(404, "not_found")
        if request.method == "GET":
            if request.body:
                return error(400, "invalid_request")
            item = self.store.get(identifier)
            return Response(200, {"revision": item.revision, "encrypted_payload": item.encrypted_payload})
        if request.method not in {"PUT", "DELETE"}:
            return error(405, "method_not_allowed")
        content_type = headers.get("content-type", "").lower().replace(" ", "")
        if content_type not in {"application/json", "application/json;charset=utf-8"}:
            return error(415, "unsupported_media_type")
        value = json_object(request.body)
        expected = revision(value.get("expected_revision"))
        if request.method == "DELETE":
            if set(value) != {"expected_revision"}:
                return error(400, "invalid_request")
            next_revision = self.store.delete(identifier, expected)
        else:
            if set(value) != {"expected_revision", "encrypted_payload"}:
                return error(400, "invalid_request")
            next_revision = self.store.put(identifier, expected, encrypted_payload(value.get("encrypted_payload")))
        return Response(200, {"revision": next_revision})
