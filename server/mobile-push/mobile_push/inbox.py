"""Separate durable hook inbox so an in-flight HTTP send never drops an observer event."""

from __future__ import annotations

import contextlib
import json
import os
import sqlite3
import time


class Inbox:
    def __init__(self, path):
        self.path = path
        fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        os.close(fd)
        os.chmod(path, 0o600)
        with self.connection() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute(
                "CREATE TABLE IF NOT EXISTS inbox (id INTEGER PRIMARY KEY AUTOINCREMENT,"
                "dedup TEXT UNIQUE NOT NULL, payload TEXT NOT NULL, expires_at INTEGER NOT NULL)"
            )

    @contextlib.contextmanager
    def connection(self):
        with contextlib.closing(sqlite3.connect(self.path, timeout=0.025)) as db:
            db.row_factory = sqlite3.Row
            with db:
                yield db

    def put(self, event, policy):
        now = int(time.time())
        with self.connection() as db:
            db.execute("DELETE FROM inbox WHERE expires_at<=?", (now,))
            db.execute(
                "INSERT OR IGNORE INTO inbox(dedup,payload,expires_at) VALUES(?,?,?)",
                (event["dedup"], json.dumps(event), now + policy.ttl),
            )
            db.execute(
                "DELETE FROM inbox WHERE id NOT IN (SELECT id FROM inbox ORDER BY id DESC LIMIT ?)",
                (policy.max_events,),
            )

    def peek(self):
        with self.connection() as db:
            return db.execute("SELECT * FROM inbox ORDER BY id LIMIT 1").fetchone()

    def remove(self, identity):
        with self.connection() as db:
            db.execute("DELETE FROM inbox WHERE id=?", (identity,))
