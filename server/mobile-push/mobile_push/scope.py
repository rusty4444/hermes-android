"""Subscription selection narrows live operator ACLs; it never grants ownership."""

from __future__ import annotations

import json
from dataclasses import dataclass

from .config import Policy, Rejected, identifier


@dataclass(frozen=True)
class SessionScope:
    mode: str
    sessions: tuple[str, ...] = ()

    @classmethod
    def from_body(cls, body):
        mode = body.get("session_scope", "explicit")
        if mode not in ("explicit", "authorized"):
            raise Rejected(422, "Invalid session scope")
        if mode == "authorized":
            # Omitted, not null or even an empty list: avoid ambiguous consent.
            if "session_ids" in body:
                raise Rejected(422, "Authorized scope must omit session_ids")
            return cls(mode)
        sessions = body.get("session_ids")
        if (
            not isinstance(sessions, list)
            or not 1 <= len(sessions) <= 128
            or not all(identifier(sid) for sid in sessions)
            or len(set(sessions)) != len(sessions)
        ):
            raise Rejected(422, "Explicit scope requires 1–128 unique exact session IDs")
        return cls(mode, tuple(sessions))

    @classmethod
    def from_registration(cls, row):
        sessions = json.loads(row["sessions_json"])
        if row["session_scope"] == "authorized" and sessions == []:
            return cls("authorized")
        # Reuse exact validation, and fail closed for corrupt persisted scopes.
        return cls.from_body({"session_scope": row["session_scope"], "session_ids": sessions})

    def allows(self, principal, session_id, policy: Policy):
        return (
            policy.enabled
            and policy.admitted(principal)
            and identifier(session_id)
            and policy.allowed(principal, session_id)
            and (self.mode == "authorized" or session_id in self.sessions)
        )

    def ready(self, principal, policy: Policy, durable):
        # An admitted dynamic subscription can prove its endpoint before any session
        # exists. Each normal event still needs its own live ACL + durability check.
        return (
            policy.enabled
            and policy.admitted(principal)
            and all(self.allows(principal, sid, policy) and durable(sid) for sid in self.sessions)
        )
