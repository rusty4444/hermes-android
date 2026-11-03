"""Profile-owned lifecycle observers and restart-safe sender."""

from __future__ import annotations

import contextvars
import json
import logging
import sqlite3
import threading

from .config import Rejected, identifier
from .inbox import Inbox
from .scope import SessionScope
from .store import Store
from .transport import Sender

logger = logging.getLogger(__name__)


class Runtime:
    def __init__(self, profile, sender=None):
        self.profile = profile
        self.store = None
        self.inbox = None
        self.sender = sender or Sender()
        self.stopping = threading.Event()
        self.thread = None

    def initialise(self):
        self.store = Store(self.profile.database)
        self.inbox = Inbox(self.profile.directory / "inbox.sqlite3")

    def start(self):
        context = contextvars.copy_context()
        self.thread = threading.Thread(
            target=context.run, args=(self.run,), name="mobile-push", daemon=True
        )
        self.thread.start()

    def stop(self):
        self.stopping.set()
        if self.thread and self.thread is not threading.current_thread():
            self.thread.join(timeout=12)

    def run(self):
        while not self.stopping.is_set():
            try:
                worked = self.deliver_one()
            except Exception:
                # Exception text can contain subscription endpoints/keys: do not log it.
                logger.warning("mobile-push worker attempt failed")
                worked = False
            if not worked:
                self.stopping.wait(1)

    def deliver_one(self):
        assert self.store is not None and self.inbox is not None
        policy = self.profile.policy()
        if not policy.enabled or self.stopping.is_set():
            return False
        # Move inbox -> outbox before sending any queued hints. Record-then-delete is
        # crash-safe because Store.record deduplicates; inbox and outbox need no shared WAL.
        for _ in range(32):
            incoming = self.inbox.peek()
            if not incoming:
                break
            if incoming["expires_at"] > self.store.now():
                event = json.loads(incoming["payload"])
                event["expires_at"] = incoming["expires_at"]
                if self.profile.durable(event["session_id"]):
                    self.store.record(event, policy)
            self.inbox.remove(incoming["id"])
        if self.inbox.peek():
            return True  # finish queued resolutions before sending any potentially stale input
        job = self.store.claim(policy)
        if not job:
            return False
        # A send holds the DB write lock. Revoke/update cannot return until an in-flight
        # send finishes; another worker cannot reclaim even an expired lease mid-send.
        with self.store.transaction() as db:
            row = db.execute(
                "SELECT * FROM outbox WHERE id=? AND lease_token=? AND done=0",
                (job["id"], job["lease_token"]),
            ).fetchone()
            if not row:
                return True
            registration = db.execute(
                "SELECT * FROM registrations WHERE installation=?", (row["installation"],)
            ).fetchone()
            event = db.execute(
                "SELECT * FROM events WHERE event_id=?", (row["event_id"],)
            ).fetchone()
            policy = self.profile.policy()  # current authz/consent, not the claim's snapshot
            if not self._permitted(registration, event, row, policy):
                db.execute("UPDATE outbox SET done=1,payload='' WHERE id=?", (row["id"],))
                return True
            try:
                status = self.sender.send(registration, row["payload"], policy)
            except Rejected:
                status = 400  # Changed/unsafe DNS is permanent until an explicit update.
            except Exception:
                status = 503
            if status in {404, 410}:
                self.store.revoke_in(db, registration)
            elif 200 <= status <= 202 or (400 <= status < 500 and status not in {408, 429}):
                db.execute(
                    "UPDATE outbox SET done=1,payload='',lease_token=NULL,lease_until=0 WHERE id=?",
                    (row["id"],),
                )
            else:
                delay = min(300, 2 ** row["attempts"])
                db.execute(
                    "UPDATE outbox SET lease_token=NULL,lease_until=0,next_at=? WHERE id=?",
                    (self.store.now() + delay, row["id"]),
                )
        return True

    def _permitted(self, registration, event, job, policy):
        assert self.store is not None
        if (
            self.stopping.is_set()
            or not policy.enabled
            or not registration
            or not event
            or event["cancelled"]
        ):
            return False
        if (
            registration["generation"] != job["generation"]
            or event["expires_at"] <= self.store.now()
        ):
            return False
        principal = (registration["provider"], registration["user_id"])
        if not policy.admitted(principal):
            return False
        scope = SessionScope.from_registration(registration)
        if event["kind"] == "challenge":
            return registration["status"] == "pending" and scope.ready(
                principal, policy, self.profile.durable
            )
        return (
            registration["status"] == "active"
            and event["kind"] in json.loads(registration["kinds_json"])
            and scope.allows(principal, event["session_id"], policy)
            and self.profile.durable(event["session_id"])
        )

    def _record(self, event):
        if self.stopping.is_set():
            return
        assert self.store is not None and self.inbox is not None
        try:
            policy = self.profile.policy()
            if policy.enabled and self.profile.durable(event["session_id"]):
                event = {**event, "registration_generations": self.store.targets(event, policy)}
                # Even an empty delivery target map must retain resolution/turn
                # cancellation, independently of subscriptions to those kinds.
                try:
                    # Preserve order behind any events already queued during a network send.
                    if self.inbox.peek():
                        self._queue_inbox(event, policy)
                    else:
                        self.store.record(event, policy)
                except sqlite3.OperationalError as error:
                    if error.sqlite_errorcode not in {sqlite3.SQLITE_BUSY, sqlite3.SQLITE_LOCKED}:
                        raise
                    self._queue_inbox(event, policy)
        except (OSError, ValueError, sqlite3.Error):
            logger.warning("mobile-push observer enqueue unavailable")

    def _queue_inbox(self, event, policy):
        assert self.store is not None and self.inbox is not None
        # Drain/send may narrow this observer-time decision, never add targets after
        # a later consent or ACL grant. Preserve an already captured (even empty) map.
        captured = (
            event
            if "registration_generations" in event
            else {**event, "registration_generations": self.store.targets(event, policy)}
        )
        self.inbox.put(captured, policy)

    def session_end(self, **kwargs):
        # Ignore incomplete legacy hooks: no turn IDs/outcome flags means no safe dedup/outcome.
        if not all(identifier(kwargs.get(key)) for key in ("session_id", "turn_id")):
            return
        if not all(
            isinstance(kwargs.get(key), bool) for key in ("completed", "failed", "interrupted")
        ):
            return
        if kwargs["interrupted"] or not isinstance(kwargs.get("turn_exit_reason"), str):
            return
        kind = "turn_error" if kwargs["failed"] else "turn_done" if kwargs["completed"] else None
        if kind:
            sid, turn = kwargs["session_id"], kwargs["turn_id"]
            self._record(
                {
                    "kind": kind,
                    "session_id": sid,
                    "turn_id": turn,
                    "dedup": json.dumps([kind, sid, turn], separators=(",", ":")),
                }
            )

    def human_input(self, resolved=False, **kwargs):
        if (
            kwargs.get("kind") not in {"approval", "clarify", "sudo"}
            or not identifier(kwargs.get("session_id"))
            or not identifier(kwargs.get("request_id"))
        ):
            return
        kind = "input_resolved" if resolved else "input"
        sid, request = kwargs["session_id"], kwargs["request_id"]
        # Observer request_id is not the surface's RPC approval ID. No answers/commands retained.
        self._record(
            {
                "kind": kind,
                "session_id": sid,
                "request_id": request,
                "dedup": json.dumps([kind, sid, request], separators=(",", ":")),
            }
        )

    def human_resolved(self, **kwargs):
        self.human_input(resolved=True, **kwargs)
