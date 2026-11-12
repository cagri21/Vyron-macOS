"""SQLite compare-and-swap storage. This layer never receives a plaintext API key."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import sqlite3
import stat
import uuid

from .validation import MAX_RECORDS, encrypted_payload, record_id, revision


class RevisionConflict(Exception):
    pass


class CapacityReached(Exception):
    pass


@dataclass(frozen=True)
class CredentialRecord:
    revision: int
    encrypted_payload: str | None


class CredentialStore:
    def __init__(self, directory: Path, maximum_records: int = MAX_RECORDS):
        self.directory = Path(directory)
        self.maximum_records = maximum_records
        if not 1 <= maximum_records <= MAX_RECORDS:
            raise ValueError("invalid record limit")
        self._prepare_directory()
        self.path = self.directory / "credentials.sqlite3"
        descriptor = os.open(self.path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise ValueError("unsafe credential store")
        finally:
            os.close(descriptor)
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT NOT NULL)")
            connection.execute(
                "CREATE TABLE IF NOT EXISTS credentials ("
                "id TEXT PRIMARY KEY, revision INTEGER NOT NULL CHECK(revision > 0), encrypted_payload TEXT)"
            )
            connection.execute("INSERT OR IGNORE INTO metadata VALUES ('schema_version', '1')")
            connection.execute("INSERT OR IGNORE INTO metadata VALUES ('instance_id', ?)", (str(uuid.uuid4()),))
            schema = connection.execute("SELECT value FROM metadata WHERE name = 'schema_version'").fetchone()
            if schema != ("1",):
                raise ValueError("unsupported credential store schema")
            instance = connection.execute("SELECT value FROM metadata WHERE name = 'instance_id'").fetchone()
            self.instance_id = record_id(instance[0])
            connection.commit()
        finally:
            connection.close()

    def _prepare_directory(self):
        if not self.directory.is_absolute():
            raise ValueError("data directory must be absolute")
        for component in (self.directory, *self.directory.parents):
            if component.is_symlink():
                raise ValueError("symlinked data directory")
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = self.directory.stat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("unsafe data directory")

    def _connect(self):
        connection = sqlite3.connect(self.path, timeout=3, isolation_level=None)
        connection.execute("PRAGMA busy_timeout = 3000")
        connection.execute("PRAGMA synchronous = FULL")
        return connection

    def get(self, identifier: str) -> CredentialRecord:
        identifier = record_id(identifier)
        connection = self._connect()
        try:
            row = connection.execute(
                "SELECT revision, encrypted_payload FROM credentials WHERE id = ?", (identifier,)
            ).fetchone()
            return CredentialRecord(*row) if row else CredentialRecord(0, None)
        finally:
            connection.close()

    def has_encrypted_credentials(self) -> bool:
        connection = self._connect()
        try:
            return bool(connection.execute(
                "SELECT EXISTS(SELECT 1 FROM credentials WHERE encrypted_payload IS NOT NULL)"
            ).fetchone()[0])
        finally:
            connection.close()

    def put(self, identifier: str, expected_revision: int, payload: str) -> int:
        return self._mutate(identifier, expected_revision, encrypted_payload(payload))

    def delete(self, identifier: str, expected_revision: int) -> int:
        return self._mutate(identifier, expected_revision, None)

    def _mutate(self, identifier: str, expected_revision: int, payload: str | None) -> int:
        identifier = record_id(identifier)
        expected_revision = revision(expected_revision)
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT revision FROM credentials WHERE id = ?", (identifier,)).fetchone()
            current = row[0] if row else 0
            if current != expected_revision:
                raise RevisionConflict()
            if row is None:
                count = connection.execute("SELECT COUNT(*) FROM credentials").fetchone()[0]
                if count >= self.maximum_records:
                    raise CapacityReached()
            next_revision = current + 1
            connection.execute(
                "INSERT INTO credentials (id, revision, encrypted_payload) VALUES (?, ?, ?) "
                "ON CONFLICT(id) DO UPDATE SET revision = excluded.revision, "
                "encrypted_payload = excluded.encrypted_payload",
                (identifier, next_revision, payload)
            )
            connection.commit()
            return next_revision
        finally:
            connection.close()
