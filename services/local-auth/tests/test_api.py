import base64
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local_auth.api import Application, Request
from local_auth.storage import CredentialStore
from local_auth.validation import MAX_BODY_BYTES, MAX_CIPHERTEXT_BYTES

TOKEN = base64.urlsafe_b64encode(b"T" * 32).decode("ascii").rstrip("=")
PAYLOAD = base64.b64encode(b"a" * 28).decode("ascii")


class APITests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.store = CredentialStore(Path(self.temporary.name).resolve() / "data")
        self.application = Application(self.store, TOKEN)
        self.identifier = str(uuid.uuid4())
        self.path = "/v1/credentials/" + self.identifier

    def tearDown(self):
        self.temporary.cleanup()

    def request(self, method, target, value=None, headers=()):
        body = value if isinstance(value, bytes) else (json.dumps(value).encode() if value is not None else b"")
        defaults = [("Host", "127.0.0.1:8327"), ("Authorization", "Bearer " + TOKEN)]
        if value is not None:
            defaults += [("Content-Type", "application/json"), ("Content-Length", str(len(body)))]
        return self.application.dispatch(Request(method, target, tuple(defaults) + tuple(headers), body))

    def test_health_is_public_but_session_and_unknown_routes_require_exact_auth(self):
        health = self.application.dispatch(Request("GET", "/health", (("Host", "127.0.0.1:8327"),)))
        self.assertEqual(health.status, 200)
        self.assertEqual(health.payload["service"], "vyron-local-auth")
        for target in ("/v1/session", self.path, "/unknown"):
            for token in ("", TOKEN[:-1], "Bearer wrong", "Bearer " + TOKEN + " "):
                result = self.application.dispatch(Request("GET", target, (
                    ("Host", "127.0.0.1:8327"), ("Authorization", token)
                )))
                self.assertEqual(result.status, 401)
                self.assertEqual(result.payload, {"error": "unauthorized"})

    def test_session_identity_and_ciphertext_presence_are_stable_and_tombstone_aware(self):
        initial = self.request("GET", "/v1/session")
        self.assertFalse(initial.payload["has_encrypted_credentials"])
        self.assertEqual(initial.payload["schema_version"], 1)
        self.assertEqual(initial.payload["instance_id"], self.store.instance_id)
        self.request("PUT", self.path, {"expected_revision": 0, "encrypted_payload": PAYLOAD})
        self.assertTrue(self.request("GET", "/v1/session").payload["has_encrypted_credentials"])
        self.request("DELETE", self.path, {"expected_revision": 1})
        self.assertFalse(self.request("GET", "/v1/session").payload["has_encrypted_credentials"])

    def test_browser_origin_referer_duplicate_auth_and_rebinding_host_are_rejected(self):
        for header in (("Origin", "null"), ("Origin", "https://example.test"), ("Referer", "")):
            self.assertEqual(self.request("GET", "/v1/session", headers=(header,)).status, 401)
        duplicate = self.request("GET", "/v1/session", headers=(("authorization", "Bearer " + TOKEN),))
        self.assertEqual(duplicate.status, 400)
        hostile = self.application.dispatch(Request("GET", "/health", (("Host", "example.test:8327"),)))
        self.assertEqual(hostile.status, 401)
        self.assertEqual(self.request("OPTIONS", self.path).status, 405)

    def test_get_put_delete_contract_and_conflict_do_not_disclose_current_payload(self):
        self.assertEqual(self.request("GET", self.path).payload, {"revision": 0, "encrypted_payload": None})
        self.assertEqual(self.request("PUT", self.path, {
            "expected_revision": 0, "encrypted_payload": PAYLOAD
        }).payload, {"revision": 1})
        current = self.request("GET", self.path)
        self.assertEqual(current.payload, {"revision": 1, "encrypted_payload": PAYLOAD})
        stale = self.request("PUT", self.path, {"expected_revision": 0, "encrypted_payload": PAYLOAD})
        self.assertEqual(stale.status, 409)
        self.assertEqual(stale.payload, {"error": "revision_conflict"})
        self.assertEqual(self.request("DELETE", self.path, {"expected_revision": 1}).payload, {"revision": 2})
        self.assertEqual(self.request("GET", self.path).payload, {"revision": 2, "encrypted_payload": None})
        self.assertEqual(self.request("PUT", self.path, {
            "expected_revision": 1, "encrypted_payload": PAYLOAD
        }).status, 409)

    def test_only_bounded_canonical_aes_envelopes_are_accepted(self):
        invalid = ["plaintext-api-key", "", "YQ==", PAYLOAD + "\n", PAYLOAD.rstrip("="),
                   base64.b64encode(b"x" * (MAX_CIPHERTEXT_BYTES + 1)).decode()]
        for encrypted in invalid:
            result = self.request("PUT", self.path, {"expected_revision": 0, "encrypted_payload": encrypted})
            self.assertEqual(result.status, 400)
            self.assertNotIn("plaintext-api-key", json.dumps(result.payload))
        largest = base64.b64encode(b"x" * MAX_CIPHERTEXT_BYTES).decode()
        self.assertEqual(self.request("PUT", self.path, {
            "expected_revision": 0, "encrypted_payload": largest
        }).status, 200)

    def test_revision_types_json_ambiguity_unknown_fields_and_ids_are_rejected(self):
        for value in (True, False, -1, 1.0, "0", 1 << 63, None):
            self.assertEqual(self.request("PUT", self.path, {
                "expected_revision": value, "encrypted_payload": PAYLOAD
            }).status, 400)
        duplicate = b'{"expected_revision":0,"expected_revision":1,"encrypted_payload":"private"}'
        self.assertEqual(self.request("PUT", self.path, duplicate).status, 400)
        self.assertEqual(self.request("DELETE", self.path, {"expected_revision": 0, "api_key": "private"}).status, 400)
        for identifier in ("../secret", self.identifier + "/extra", self.identifier + "?query", "%2e%2e"):
            self.assertEqual(self.request("GET", "/v1/credentials/" + identifier).status, 404)
        self.assertEqual(self.request("GET", self.path.upper().replace("/V1/CREDENTIALS/", "/v1/credentials/")).status, 200)

    def test_body_header_and_content_type_limits_are_enforced(self):
        self.assertEqual(self.request("PUT", self.path, b"x" * (MAX_BODY_BYTES + 1)).status, 413)
        self.assertEqual(self.request("GET", "/v1/session", headers=(("X-Large", "x" * 8_192),)).status, 431)
        many = tuple(("X-" + str(index), "x") for index in range(33))
        self.assertEqual(self.request("GET", "/v1/session", headers=many).status, 431)
        request = Request("PUT", self.path, (
            ("Host", "127.0.0.1:8327"), ("Authorization", "Bearer " + TOKEN), ("Content-Type", "text/plain")
        ), b"{}")
        self.assertEqual(self.application.dispatch(request).status, 415)

    def test_storage_failures_are_sanitized(self):
        with mock.patch.object(self.store, "get", side_effect=sqlite3.OperationalError("private database path")):
            result = self.request("GET", self.path)
        self.assertEqual(result.status, 503)
        self.assertEqual(result.payload, {"error": "storage_unavailable"})


if __name__ == "__main__":
    unittest.main()
