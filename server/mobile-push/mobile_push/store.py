"""SQLite events and transactional delivery leases. No network in observer callbacks."""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import secrets
import sqlite3
import time
import uuid
from pathlib import Path

from .config import Policy, Rejected, identifier
from .scope import SessionScope

SCHEMA = """
CREATE TABLE IF NOT EXISTS registrations (
 installation TEXT PRIMARY KEY, provider TEXT NOT NULL, user_id TEXT NOT NULL,
 generation INTEGER NOT NULL, status TEXT NOT NULL, nonce TEXT NOT NULL,
 endpoint TEXT NOT NULL, keys_json TEXT NOT NULL, kinds_json TEXT NOT NULL,
 sessions_json TEXT NOT NULL, challenge_hash TEXT NOT NULL, challenge_expires INTEGER NOT NULL,
 registration_revision INTEGER NOT NULL DEFAULT 0,
 session_scope TEXT NOT NULL DEFAULT 'explicit'
);
CREATE TABLE IF NOT EXISTS registration_nonces (
 installation TEXT NOT NULL, nonce_hash TEXT NOT NULL,
 PRIMARY KEY(installation,nonce_hash)
);
CREATE TABLE IF NOT EXISTS events (
 cursor INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT UNIQUE NOT NULL,
 provider TEXT NOT NULL, user_id TEXT NOT NULL, dedup TEXT NOT NULL,
 kind TEXT NOT NULL, session_id TEXT, turn_id TEXT, request_id TEXT,
 installation TEXT, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 cancelled INTEGER NOT NULL DEFAULT 0, UNIQUE(provider,user_id,dedup)
);
CREATE TABLE IF NOT EXISTS outbox (
 id INTEGER PRIMARY KEY, event_id TEXT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
 installation TEXT NOT NULL REFERENCES registrations(installation), generation INTEGER NOT NULL,
 payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_at INTEGER NOT NULL,
 lease_token TEXT, lease_until INTEGER NOT NULL DEFAULT 0, done INTEGER NOT NULL DEFAULT 0,
 UNIQUE(event_id,installation,generation)
);
CREATE INDEX IF NOT EXISTS outbox_due ON outbox(next_at,lease_until);
CREATE INDEX IF NOT EXISTS events_principal ON events(provider,user_id,cursor);
CREATE TABLE IF NOT EXISTS attention (
 session_id TEXT NOT NULL, request_id TEXT NOT NULL, resolved INTEGER NOT NULL,
 expires_at INTEGER NOT NULL, PRIMARY KEY(session_id,request_id)
);
"""


class Store:
    def __init__(self, path: Path, clock=time.time):
        self.path = path
        self.clock = clock
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(path.parent, 0o700)
        fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        os.close(fd)
        os.chmod(path, 0o600)
        with self.connection() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript(SCHEMA)
        # Transactional, restart-safe migration: old proofs/delivery fail closed,
        # but retain installation + revision floor so an upgraded client can renew.
        with self.transaction() as db:
            columns = {row["name"] for row in db.execute("PRAGMA table_info(registrations)")}
            if "session_scope" not in columns:
                # Existing subscriptions must never become dynamic during upgrade.
                db.execute(
                    "ALTER TABLE registrations ADD COLUMN session_scope TEXT NOT NULL DEFAULT 'explicit'"
                )
            if "registration_revision" not in columns:
                db.execute(
                    "ALTER TABLE registrations ADD COLUMN registration_revision "
                    "INTEGER NOT NULL DEFAULT 0"
                )
            legacy = db.execute(
                "SELECT * FROM registrations WHERE registration_revision=0 "
                "AND status IN ('pending','active')"
            ).fetchall()
            for row in legacy:
                self.revoke_in(db, row)
                db.execute(
                    "UPDATE registrations SET status='upgrade_required' WHERE installation=?",
                    (row["installation"],),
                )
            db.executemany(
                "INSERT OR IGNORE INTO registration_nonces VALUES(?,?)",
                [
                    (row["installation"], self.nonce_hash(row["nonce"]))
                    for row in db.execute(
                        "SELECT installation,nonce FROM registrations WHERE nonce!=''"
                    )
                ],
            )

    @contextlib.contextmanager
    def connection(self):
        with contextlib.closing(sqlite3.connect(self.path, timeout=0.025)) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA foreign_keys=ON")
            with db:
                yield db

    @contextlib.contextmanager
    def transaction(self):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            yield db

    def now(self):
        return int(self.clock())

    @staticmethod
    def owner(row, principal):
        if row is None or (row["provider"], row["user_id"]) != principal:
            raise Rejected(404, "Registration not found")

    def registration(self, principal, installation):
        with self.connection() as db:
            row = db.execute(
                "SELECT * FROM registrations WHERE installation=?", (installation,)
            ).fetchone()
            self.owner(row, principal)
            return dict(row)

    @staticmethod
    def nonce_hash(nonce):
        return hashlib.sha256(nonce.encode()).hexdigest()

    def put(self, principal, installation, body, policy: Policy):
        revision = body.get("registration_revision")
        # Validate here too: an authenticated handler started by old code must not
        # bypass the fence when it eventually reaches this transactional boundary.
        if type(revision) is not int or not 1 <= revision <= 9007199254740991:
            raise Rejected(422, "A fenced registration revision is required")
        scope = SessionScope.from_body(body)
        now = self.now()
        challenge = secrets.token_urlsafe(32)
        with self.transaction() as db:
            previous = db.execute(
                "SELECT * FROM registrations WHERE installation=?", (installation,)
            ).fetchone()
            if previous:
                self.owner(previous, principal)
                if previous["status"] == "revoked":
                    raise Rejected(409, "Installation revoked; enable with a new installation ID")
                if revision <= previous["registration_revision"]:
                    raise Rejected(409, "Registration revision superseded")
                if (
                    previous["nonce"] == body["registration_nonce"]
                    or db.execute(
                        "SELECT 1 FROM registration_nonces WHERE installation=? AND nonce_hash=?",
                        (installation, self.nonce_hash(body["registration_nonce"])),
                    ).fetchone()
                ):
                    raise Rejected(409, "A fresh unused registration_nonce is required")
            elif (
                db.execute("SELECT count(*) FROM registrations").fetchone()[0]
                >= policy.max_registrations
            ):
                raise Rejected(429, "Registration capacity reached")
            generation = previous["generation"] + 1 if previous else 1
            db.execute("DELETE FROM outbox WHERE installation=?", (installation,))
            db.execute(
                "UPDATE events SET cancelled=1 WHERE installation=? AND kind='challenge'",
                (installation,),
            )
            values = (
                installation,
                *principal,
                generation,
                "pending",
                body["registration_nonce"],
                body["endpoint"],
                json.dumps(body["keys"]),
                json.dumps(body["event_kinds"]),
                json.dumps(scope.sessions),
                hashlib.sha256(challenge.encode()).hexdigest(),
                now + policy.challenge_ttl,
                revision,
                scope.mode,
            )
            db.execute(
                "INSERT OR REPLACE INTO registrations "
                "(installation,provider,user_id,generation,status,nonce,endpoint,keys_json,kinds_json,"
                "sessions_json,challenge_hash,challenge_expires,registration_revision,session_scope) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                values,
            )
            db.execute(
                "INSERT OR IGNORE INTO registration_nonces VALUES(?,?)",
                (installation, self.nonce_hash(body["registration_nonce"])),
            )
            event_id = self._event(
                db,
                principal,
                f"challenge:{installation}:{generation}",
                "challenge",
                now,
                now + policy.challenge_ttl,
                installation=installation,
            )
            hint = self.hint(
                event_id,
                "challenge",
                generation,
                body["registration_nonce"],
                now + policy.challenge_ttl,
                challenge=challenge,
            )
            self._queue(db, installation, generation, event_id, hint, now)
            self._prune(db, policy, now)
        return {
            "generation": generation,
            "status": "pending",
            "registration_nonce": body["registration_nonce"],
            "registration_revision": revision,
        }

    def confirm(self, principal, installation, generation, challenge, policy, durable=None):
        with self.transaction() as db:
            row = db.execute(
                "SELECT * FROM registrations WHERE installation=?", (installation,)
            ).fetchone()
            self.owner(row, principal)
            if (
                row["generation"] != generation
                or row["status"] != "pending"
                or row["challenge_expires"] <= self.now()
                or not secrets.compare_digest(
                    row["challenge_hash"], hashlib.sha256(challenge.encode()).hexdigest()
                )
            ):
                raise Rejected(409, "Challenge expired, invalid or superseded")
            if not SessionScope.from_registration(row).ready(
                principal, policy, durable or (lambda sid: False)
            ):
                raise Rejected(403, "Session scope is no longer authorised or durable")
            db.execute(
                "UPDATE registrations SET status='active',challenge_hash='' WHERE installation=?",
                (installation,),
            )
            db.execute("DELETE FROM outbox WHERE installation=?", (installation,))
        return {"generation": generation, "status": "active"}

    @staticmethod
    def revoke_in(db, row):
        db.execute(
            "UPDATE registrations SET generation=generation+1,status='revoked',"
            "challenge_hash='',endpoint='',keys_json='{}' WHERE installation=?",
            (row["installation"],),
        )
        db.execute("DELETE FROM outbox WHERE installation=?", (row["installation"],))
        db.execute(
            "UPDATE events SET cancelled=1 WHERE installation=? AND kind='challenge'",
            (row["installation"],),
        )

    def revoke(self, principal, installation, new_policy=None):
        with self.transaction() as db:
            row = db.execute(
                "SELECT * FROM registrations WHERE installation=?", (installation,)
            ).fetchone()
            if row is None:
                policy = new_policy() if new_policy else None
                if policy is not None and not policy.admitted(principal):
                    raise Rejected(403, "Principal not authorised for mobile push")
                capacity = policy.max_registrations if policy else 256
                if db.execute("SELECT count(*) FROM registrations").fetchone()[0] >= capacity:
                    raise Rejected(429, "Registration capacity reached")
                # DELETE can beat the very first PUT (including its DNS lookup).
                # Keep a terminal tombstone, not a 404 that permits late creation.
                db.execute(
                    "INSERT INTO registrations "
                    "(installation,provider,user_id,generation,status,nonce,endpoint,keys_json,kinds_json,"
                    "sessions_json,challenge_hash,challenge_expires,registration_revision) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (installation, *principal, 1, "revoked", "", "", "{}", "[]", "[]", "", 0, 0),
                )
                generation = 1
            else:
                self.owner(row, principal)
                if row["status"] != "revoked":
                    self.revoke_in(db, row)
                generation = row["generation"] + int(row["status"] != "revoked")
        return {"generation": generation, "status": "revoked"}

    @staticmethod
    def hint(event_id, kind, generation, nonce, expires, **extra):
        return {
            "schema": 1,
            "event_id": event_id,
            "kind": kind,
            "generation": generation,
            "registration_nonce": nonce,
            "expires_at": expires,
            **extra,
        }

    @staticmethod
    def _queue(db, installation, generation, event_id, hint, now):
        db.execute(
            "INSERT OR IGNORE INTO outbox(event_id,installation,generation,payload,next_at) VALUES(?,?,?,?,?)",
            (event_id, installation, generation, json.dumps(hint, separators=(",", ":")), now),
        )

    @staticmethod
    def _event(
        db,
        principal,
        dedup,
        kind,
        now,
        expires,
        session_id=None,
        turn_id=None,
        request_id=None,
        installation=None,
    ):
        event_id = uuid.uuid4().hex
        db.execute(
            "INSERT OR IGNORE INTO events(event_id,provider,user_id,dedup,kind,session_id,turn_id,"
            "request_id,installation,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            (
                event_id,
                *principal,
                dedup,
                kind,
                session_id,
                turn_id,
                request_id,
                installation,
                now,
                expires,
            ),
        )
        row = db.execute(
            "SELECT event_id FROM events WHERE provider=? AND user_id=? AND dedup=?",
            (*principal, dedup),
        ).fetchone()
        return row[0]

    @staticmethod
    def _allows_event(row, event, policy):
        principal = (row["provider"], row["user_id"])
        return event["kind"] in json.loads(row["kinds_json"]) and SessionScope.from_registration(
            row
        ).allows(principal, event["session_id"], policy)

    def targets(self, event, policy: Policy):
        # Capture event-specific consent AND authority before any deferred write.
        # WAL readers remain available while the sender holds a write transaction;
        # these rows and the immutable policy/scope are an admission snapshot.
        with self.connection() as db:
            return {
                row["installation"]: row["generation"]
                for row in db.execute("SELECT * FROM registrations WHERE status='active'")
                if self._allows_event(row, event, policy)
            }

    def record(self, event, policy: Policy):
        now = self.now()
        expires = event.get("expires_at", now + policy.ttl)
        if expires <= now:
            return
        kind, sid = event["kind"], event["session_id"]
        request_id = event.get("request_id")
        with self.transaction() as db:
            self._prune(db, policy, now)
            if request_id:
                attention = db.execute(
                    "SELECT resolved FROM attention WHERE session_id=? AND request_id=?",
                    (sid, request_id),
                ).fetchone()
                if kind == "input" and attention and attention[0]:
                    return
                resolved = int(kind == "input_resolved")
                db.execute(
                    "INSERT INTO attention VALUES(?,?,?,?) ON CONFLICT(session_id,request_id) "
                    "DO UPDATE SET resolved=max(resolved,excluded.resolved),expires_at=excluded.expires_at",
                    (sid, request_id, resolved, now + policy.ttl * 2),
                )
                if resolved:
                    self._cancel_attention(db, sid, request_id)
            if kind in {"turn_done", "turn_error"}:
                self._cancel_attention(db, sid)
                db.execute("UPDATE attention SET resolved=1 WHERE session_id=?", (sid,))
            registrations = db.execute(
                "SELECT * FROM registrations WHERE status='active'"
            ).fetchall()
            for row in registrations:
                principal = (row["provider"], row["user_id"])
                targets = event.get("registration_generations")
                if targets is not None and targets.get(row["installation"]) != row["generation"]:
                    continue
                if not self._allows_event(row, event, policy):
                    continue
                event_id = self._event(
                    db,
                    principal,
                    event["dedup"],
                    kind,
                    now,
                    expires,
                    sid,
                    event.get("turn_id"),
                    request_id,
                )
                hint = self.hint(event_id, kind, row["generation"], row["nonce"], expires)
                self._queue(db, row["installation"], row["generation"], event_id, hint, now)
            self._prune(db, policy, now)

    @staticmethod
    def _cancel_attention(db, sid, request_id=None):
        query = "UPDATE events SET cancelled=1 WHERE session_id=? AND kind='input'"
        args = [sid]
        if request_id:
            query += " AND request_id=?"
            args.append(request_id)
        db.execute(query, args)
        db.execute(
            "DELETE FROM outbox WHERE event_id IN (SELECT event_id FROM events WHERE cancelled=1)"
        )

    @staticmethod
    def _prune(db, policy, now):
        db.execute("DELETE FROM events WHERE expires_at<=?", (now,))
        db.execute(
            "DELETE FROM events WHERE cursor NOT IN (SELECT cursor FROM events ORDER BY cursor DESC LIMIT ?)",
            (policy.max_events,),
        )
        db.execute("DELETE FROM attention WHERE expires_at<=?", (now,))
        db.execute(
            "DELETE FROM attention WHERE rowid NOT IN (SELECT rowid FROM attention ORDER BY rowid DESC LIMIT ?)",
            (policy.max_events,),
        )

    def events(self, principal, after, limit, policy, durable, installation=None, generation=None):
        bound = installation is not None or generation is not None
        if bound and (
            not identifier(installation)
            or type(generation) is not int
            or not 1 <= generation <= 9223372036854775807
        ):
            raise Rejected(422, "Exact installation_id and positive generation required together")
        binding = {}
        scope = None
        kinds = ()
        with self.connection() as db:
            # Registration and events belong to one consistent read snapshot. A
            # concurrent renewal must not mix a new scope with an old generation.
            db.execute("BEGIN")
            if bound:
                registration = db.execute(
                    "SELECT * FROM registrations WHERE installation=?", (installation,)
                ).fetchone()
                self.owner(registration, principal)
                if registration["status"] != "active" or registration["generation"] != generation:
                    raise Rejected(409, "Registration is not active at this generation")
                scope = SessionScope.from_registration(registration)
                kinds = json.loads(registration["kinds_json"])
                binding = {
                    "installation_id": installation,
                    "generation": registration["generation"],
                    "session_scope": scope.mode,
                }
            rows = db.execute(
                "SELECT * FROM events WHERE provider=? AND user_id=? AND cursor>? "
                "AND expires_at>? AND cancelled=0 ORDER BY cursor LIMIT ?",
                (*principal, after, self.now(), policy.max_events),
            ).fetchall()
        visible = []
        cursor = after
        for row in rows:
            if scope is not None:
                permitted = (
                    row["kind"] in kinds
                    and scope.allows(principal, row["session_id"], policy)
                    and durable(row["session_id"])
                )
            else:
                # Preserve the legacy unbound API (including safe challenge metadata).
                permitted = row["kind"] == "challenge" or (
                    policy.allowed(principal, row["session_id"]) and durable(row["session_id"])
                )
            if not permitted:
                cursor = row["cursor"]
                continue
            if len(visible) == limit:
                return {"events": visible, "next_cursor": cursor, "has_more": True, **binding}
            cursor = row["cursor"]
            event = {
                key: row[key] for key in ("cursor", "event_id", "kind", "created_at", "expires_at")
            }
            for key in ("session_id", "turn_id", "request_id"):
                if row[key]:
                    event[key] = row[key]
            if row["installation"]:
                event["installation_id"] = row["installation"]
            visible.append(event)
        return {"events": visible, "next_cursor": cursor, "has_more": False, **binding}

    def claim(self, policy):
        now = self.now()
        with self.transaction() as db:
            self._prune(db, policy, now)
            db.execute(
                "UPDATE outbox SET done=1,payload='' WHERE attempts>=? AND lease_until<=?",
                (policy.max_attempts, now),
            )
            row = db.execute(
                "SELECT * FROM outbox WHERE done=0 AND next_at<=? AND lease_until<=? AND attempts<? "
                "ORDER BY id LIMIT 1",
                (now, now, policy.max_attempts),
            ).fetchone()
            if not row:
                return None
            token = uuid.uuid4().hex
            db.execute(
                "UPDATE outbox SET lease_token=?,lease_until=?,attempts=attempts+1 WHERE id=?",
                (token, now + 30, row["id"]),
            )
            return {**dict(row), "lease_token": token}
