import base64
import json
import sqlite3
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mobile_push import transport
from mobile_push.api import create_router
from mobile_push.config import Profile
from mobile_push.service import Runtime

PREFIX = "/api/plugins/mobile-push"


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


@pytest.fixture
def subscription():
    key = ec.generate_private_key(ec.SECP256R1())
    public = key.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    return key, {"p256dh": b64(public), "auth": b64(b"a" * 16)}


@pytest.fixture
def env(tmp_path, subscription, monkeypatch):
    profile = Profile(tmp_path / "home")
    profile.directory.mkdir(parents=True)
    with sqlite3.connect(profile.home / "state.db") as db:
        db.execute("CREATE TABLE sessions(id TEXT PRIMARY KEY,parent_session_id TEXT)")
        db.executemany(
            "INSERT INTO sessions VALUES(?,?)", [("session-a", None), ("session-b", "session-a")]
        )
    key = ec.generate_private_key(ec.SECP256R1())
    key_file = tmp_path / "vapid.pem"
    key_file.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    key_file.chmod(0o600)
    config = {
        "enabled": True,
        "vapid_private_key_file": str(key_file),
        "vapid_subject": "mailto:operator@example.test",
        "principals": [
            {"provider": "fixture", "user_id": "alice", "session_ids": ["session-a"]},
            {"provider": "fixture", "user_id": "bob", "session_ids": ["session-b"]},
        ],
    }

    def save():
        path = profile.directory / "config.json"
        path.write_text(json.dumps(config))
        path.chmod(0o600)

    save()
    real_lookup = transport.resolve_addresses

    def lookup(host, port, *args, **kwargs):
        if host == "push.example.test":
            return ("93.184.216.34",)
        return real_lookup(host, port, *args, **kwargs)

    monkeypatch.setattr(transport, "resolve_addresses", lookup)
    identity = [SimpleNamespace(provider="fixture", user_id="alice")]
    app = FastAPI()

    @app.middleware("http")
    async def verified_fixture(request, call_next):
        # This test-owned seam stands in for the trusted Hermes authentication middleware.
        # No fixture identity is ever read from a client-supplied header.
        if identity[0] is not None:
            request.state.session = identity[0]
        return await call_next(request)

    app.include_router(create_router(profile), prefix=PREFIX)
    runtime = Runtime(profile)
    runtime.initialise()
    body = {
        "endpoint": "https://push.example.test/subscription/secret-token",
        "keys": subscription[1],
        "registration_nonce": "nonce_0123456789abcdef",
        "registration_revision": 1,
        "event_kinds": ["turn_done", "turn_error", "input", "input_resolved"],
        "session_ids": ["session-a"],
    }
    with TestClient(app) as client:
        yield SimpleNamespace(
            profile=profile,
            config=config,
            save=save,
            identity=identity,
            client=client,
            runtime=runtime,
            body=body,
            private_key=key,
            subscriber_key=subscription[0],
            lookup=lookup,
        )
    runtime.stop()


def pending(env, installation="phone", **changes):
    body = {**env.body, **changes}
    if "registration_revision" not in changes:
        with env.runtime.store.connection() as db:
            row = db.execute(
                "SELECT registration_revision FROM registrations WHERE installation=?",
                (installation,),
            ).fetchone()
        body["registration_revision"] = row[0] + 1 if row else 1
    response = env.client.put(f"{PREFIX}/registrations/{installation}", json=body)
    assert response.status_code == 200, response.text
    with env.runtime.store.connection() as db:
        row = db.execute(
            "SELECT payload FROM outbox WHERE installation=? AND done=0", (installation,)
        ).fetchone()
    return response.json(), json.loads(row[0])


def activate(env, installation="phone", **changes):
    registration, hint = pending(env, installation, **changes)
    response = env.client.post(
        f"{PREFIX}/registrations/{installation}/confirm",
        json={"generation": registration["generation"], "challenge": hint["challenge"]},
    )
    assert response.status_code == 200, response.text
    return registration


def end(env, turn="turn-a", **changes):
    env.runtime.session_end(
        session_id="session-a",
        turn_id=turn,
        completed=True,
        failed=False,
        interrupted=False,
        turn_exit_reason="text_response(stop)",
        **changes,
    )
