import base64
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import stat
import sys
import tempfile
import threading
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local_auth.storage import CapacityReached, CredentialStore, RevisionConflict


def payload(value=b"encrypted-envelope-placeholder"):
    return base64.b64encode(value).decode("ascii")


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name).resolve() / "data"
        self.store = CredentialStore(self.directory)
        self.identifier = str(uuid.uuid4())

    def tearDown(self):
        self.temporary.cleanup()

    def test_absent_records_have_revision_zero_without_creating_a_row(self):
        self.assertEqual(self.store.get(self.identifier).revision, 0)
        self.assertIsNone(self.store.get(self.identifier).encrypted_payload)
        self.assertFalse(self.store.has_encrypted_credentials())

    def test_instance_and_ciphertext_survive_store_recreation(self):
        encrypted = payload()
        self.assertEqual(self.store.put(self.identifier, 0, encrypted), 1)
        recreated = CredentialStore(self.directory)
        self.assertEqual(recreated.instance_id, self.store.instance_id)
        self.assertEqual(recreated.get(self.identifier).revision, 1)
        self.assertEqual(recreated.get(self.identifier).encrypted_payload, encrypted)
        self.assertTrue(recreated.has_encrypted_credentials())
        self.assertEqual(stat.S_IMODE(recreated.path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(recreated.directory.stat().st_mode), 0o700)

    def test_delete_keeps_a_tombstone_that_rejects_stale_writes(self):
        self.store.put(self.identifier, 0, payload())
        self.assertEqual(self.store.delete(self.identifier, 1), 2)
        for stale in (0, 1):
            with self.assertRaises(RevisionConflict):
                self.store.put(self.identifier, stale, payload(b"different-encrypted-envelope!!"))
        self.assertEqual(self.store.get(self.identifier).revision, 2)
        self.assertIsNone(self.store.get(self.identifier).encrypted_payload)
        self.assertFalse(self.store.has_encrypted_credentials())
        recreated = CredentialStore(self.directory)
        with self.assertRaises(RevisionConflict):
            recreated.put(self.identifier, 1, payload())

    def test_delete_of_absent_record_blocks_an_already_inflight_creation(self):
        self.assertEqual(self.store.delete(self.identifier, 0), 1)
        with self.assertRaises(RevisionConflict):
            self.store.put(self.identifier, 0, payload())
        self.assertIsNone(self.store.get(self.identifier).encrypted_payload)

    def test_compare_and_swap_is_atomic_between_concurrent_writers(self):
        barrier = threading.Barrier(2)

        def write(index):
            barrier.wait(timeout=3)
            try:
                self.store.put(self.identifier, 0, payload(bytes([65 + index]) * 28))
                return "written"
            except RevisionConflict:
                return "conflict"

        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = list(executor.map(write, (0, 1)))
        self.assertCountEqual(outcomes, ["written", "conflict"])
        self.assertEqual(self.store.get(self.identifier).revision, 1)

    def test_uuid_casing_refers_to_the_same_record(self):
        self.store.put(self.identifier.upper(), 0, payload())
        self.assertEqual(self.store.get(self.identifier).revision, 1)
        self.assertEqual(self.store.delete(self.identifier.upper(), 1), 2)

    def test_capacity_includes_tombstones_and_does_not_block_existing_records(self):
        limited = CredentialStore(self.directory, maximum_records=2)
        first, second, third = (str(uuid.uuid4()) for _ in range(3))
        limited.put(first, 0, payload())
        limited.put(second, 0, payload())
        limited.delete(first, 1)
        with self.assertRaises(CapacityReached):
            limited.put(third, 0, payload())
        self.assertEqual(limited.put(second, 1, payload()), 2)

    def test_symlinked_or_world_readable_storage_is_rejected_without_replacement(self):
        existing = self.store.path.read_bytes()
        self.store.path.chmod(0o644)
        with self.assertRaises(ValueError):
            CredentialStore(self.directory)
        self.assertEqual(self.store.path.read_bytes(), existing)
        self.store.path.chmod(0o600)
        alias = Path(self.temporary.name).resolve() / "alias"
        alias.symlink_to(self.directory, target_is_directory=True)
        with self.assertRaises(ValueError):
            CredentialStore(alias)


if __name__ == "__main__":
    unittest.main()
