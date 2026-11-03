"""Immutable profile paths and reloadable, operator-owned policy (never client identity)."""

from __future__ import annotations

import base64
import contextlib
import ipaddress
import json
import os
import re
import sqlite3
import stat
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

KINDS = frozenset({"turn_done", "turn_error", "input", "input_resolved"})
IDENTIFIER = re.compile(r"[A-Za-z0-9_.:@-]{1,200}\Z")


class Rejected(ValueError):
    def __init__(self, status: int, message: str):
        self.status = status
        super().__init__(message)


def identifier(value: object) -> bool:
    return isinstance(value, str) and bool(IDENTIFIER.fullmatch(value))


def b64decode(value: str, size: int) -> bytes:
    if not re.fullmatch(r"[A-Za-z0-9_-]+={0,2}", value):
        raise Rejected(422, "Invalid subscription keys")
    try:
        raw = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except ValueError:
        raise Rejected(422, "Invalid subscription keys") from None
    if len(raw) != size:
        raise Rejected(422, "Invalid subscription keys")
    return raw


def validate_keys(keys: dict) -> None:
    public = b64decode(keys["p256dh"], 65)
    b64decode(keys["auth"], 16)
    try:
        ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), public)
    except ValueError:
        raise Rejected(422, "Invalid subscription keys") from None


def private_file(path: Path) -> bytes:
    # O_NOFOLLOW plus fstat avoids symlink and check/read races on secret files.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("Private config/key must be owner-only regular files")
        raw = stream.read(65537)
    if len(raw) > 65536:
        raise ValueError("Config/key too large")
    return raw


@dataclass(frozen=True)
class Policy:
    enabled: bool
    grants: Mapping[tuple[str, str], frozenset[str]]
    owner_grants: frozenset[tuple[str, str]]
    vapid_key: Path | None = None
    vapid_subject: str = ""
    allowed_private: tuple[tuple[str, frozenset[str]], ...] = ()
    ttl: int = 3600
    challenge_ttl: int = 300
    max_events: int = 10000
    max_registrations: int = 256
    max_attempts: int = 5

    def __post_init__(self):
        # A frozen dataclass alone does not freeze a caller-owned grants mapping.
        # Admission must retain its original ACL even if the source later changes.
        object.__setattr__(
            self,
            "grants",
            MappingProxyType(
                {principal: frozenset(sessions) for principal, sessions in self.grants.items()}
            ),
        )
        object.__setattr__(self, "owner_grants", frozenset(self.owner_grants))

    def allowed(self, principal: tuple[str, str], session_id: str) -> bool:
        return principal in self.owner_grants or session_id in self.grants.get(principal, ())

    def admitted(self, principal: tuple[str, str]) -> bool:
        return principal in self.owner_grants or principal in self.grants

    def public_key(self) -> str:
        if not self.vapid_key:
            return ""
        key = serialization.load_pem_private_key(private_file(self.vapid_key), password=None)
        if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(
            key.curve, ec.SECP256R1
        ):
            raise ValueError("VAPID key must be P-256")
        public = key.public_key().public_bytes(
            serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
        )
        return base64.urlsafe_b64encode(public).rstrip(b"=").decode()


@dataclass(frozen=True)
class Profile:
    home: Path

    @property
    def directory(self) -> Path:
        return self.home / "plugin-data" / "mobile-push"

    @property
    def database(self) -> Path:
        return self.directory / "outbox.sqlite3"

    def policy(self) -> Policy:
        try:
            raw = json.loads(private_file(self.directory / "config.json"))
        except FileNotFoundError:
            return Policy(False, {}, frozenset())
        if not isinstance(raw, dict) or not isinstance(raw.get("principals", []), list):
            raise ValueError("Invalid operator config")
        grants = {}
        owners = set()
        for grant in raw.get("principals", []):
            if not isinstance(grant, dict) or not all(
                key in grant for key in ("provider", "user_id")
            ):
                raise ValueError("Invalid operator principal")
            principal = (grant["provider"], grant["user_id"])
            if not all(isinstance(item, str) and item for item in principal):
                raise ValueError("Invalid operator principal")
            sessions = grant.get("session_ids", [])
            if not isinstance(sessions, list) or not all(identifier(item) for item in sessions):
                raise ValueError("Only explicit durable session IDs are permitted")
            grants[principal] = frozenset(sessions)
            if grant.get("owner_all_sessions") is True:
                owners.add(principal)
        key = Path(raw["vapid_private_key_file"]) if raw.get("vapid_private_key_file") else None
        if key and not key.is_absolute():
            raise ValueError("VAPID secret path must be absolute")
        subject = raw.get("vapid_subject", "")
        if not isinstance(subject, str) or len(subject) > 254:
            raise ValueError("Invalid VAPID contact")
        enabled = raw.get("enabled") is True
        if enabled and (not key or not subject.startswith(("mailto:", "https://"))):
            raise ValueError("Enabled push requires VAPID key and subject")
        allowed = []
        for entry in raw.get("private_endpoints", []):
            if (
                not isinstance(entry, dict)
                or not isinstance(entry.get("host"), str)
                or not re.fullmatch(r"[a-z0-9.:-]{1,253}", entry["host"])
                or not isinstance(entry.get("ips"), list)
            ):
                raise ValueError("Private endpoint exceptions require exact hosts and IPs")
            ips = frozenset(str(ipaddress.ip_address(address)) for address in entry["ips"])
            allowed.append((entry["host"], ips))
        allowed = tuple(allowed)
        return Policy(enabled, grants, frozenset(owners), key, subject, allowed)

    def durable(self, session_id: str) -> bool:
        # Never create/open the live state DB for writing, and never infer an alias or parent.
        if not identifier(session_id):
            return False
        try:
            with contextlib.closing(
                sqlite3.connect(
                    (self.home / "state.db").as_uri() + "?mode=ro", uri=True, timeout=0.1
                )
            ) as db:
                return (
                    db.execute("SELECT 1 FROM sessions WHERE id=?", (session_id,)).fetchone()
                    is not None
                )
        except sqlite3.Error:
            return False
