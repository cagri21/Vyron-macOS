"""Bounded validation shared by the HTTP boundary and persistent store."""

import base64
import binascii
import json
import re
import uuid

MAX_CIPHERTEXT_BYTES = 32_768
MAX_BODY_BYTES = 45_056
MAX_HEADER_BYTES = 8_192
MAX_HEADERS = 32
MAX_RECORDS = 256
MAX_REVISION = (1 << 63) - 2
TOKEN_PATTERN = re.compile(r"[A-Za-z0-9_-]{43}\Z")
UUID_PATTERN = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\Z")


def record_id(value: str) -> str:
    if not isinstance(value, str) or not UUID_PATTERN.fullmatch(value):
        raise ValueError("invalid record identifier")
    return str(uuid.UUID(value))


def bearer_token(value: str) -> str:
    if not isinstance(value, str) or not TOKEN_PATTERN.fullmatch(value):
        raise ValueError("invalid bootstrap token")
    decoded = base64.urlsafe_b64decode(value + "=")
    if len(decoded) != 32 or base64.urlsafe_b64encode(decoded).decode("ascii").rstrip("=") != value:
        raise ValueError("invalid bootstrap token")
    return value


def revision(value: object) -> int:
    if type(value) is not int or not 0 <= value <= MAX_REVISION:
        raise ValueError("invalid revision")
    return value


def encrypted_payload(value: object) -> str:
    if not isinstance(value, str) or len(value) > ((MAX_CIPHERTEXT_BYTES + 2) // 3) * 4:
        raise ValueError("invalid encrypted payload")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ValueError("invalid encrypted payload") from error
    if not 28 <= len(decoded) <= MAX_CIPHERTEXT_BYTES or base64.b64encode(decoded).decode("ascii") != value:
        raise ValueError("invalid encrypted payload")
    return value


def json_object(data: bytes) -> dict:
    if len(data) > MAX_BODY_BYTES:
        raise ValueError("request body exceeds limit")

    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result

    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=unique_keys)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ValueError("invalid JSON") from error
    if not isinstance(value, dict):
        raise ValueError("expected JSON object")
    return value
