"""Real FastAPI + SQLite + loopback TCP, with the OLD handler held BEFORE commit."""

import json
import socket
import threading
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest
import uvicorn
from conftest import PREFIX, activate, pending

from mobile_push import transport
from mobile_push.config import Rejected
from mobile_push.store import Store

PRINCIPAL = ("fixture", "alice")


@pytest.fixture
def loopback(env):
    ready = threading.Event()

    class Server(uvicorn.Server):
        async def startup(self, sockets=None):
            await super().startup(sockets=sockets)
            ready.set()

    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(16)
    server = Server(uvicorn.Config(env.client.app, lifespan="off", log_level="error"))
    thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]})
    thread.start()
    try:
        assert ready.wait(5)
        yield f"http://127.0.0.1:{listener.getsockname()[1]}{PREFIX}"
    finally:
        server.should_exit = True
        thread.join(5)
        listener.close()
        assert not thread.is_alive()


def confirm(base, env, installation="phone"):
    row = env.runtime.store.registration(PRINCIPAL, installation)
    with env.runtime.store.connection() as db:
        proof = json.loads(
            db.execute(
                "SELECT payload FROM outbox WHERE installation=? AND done=0", (installation,)
            ).fetchone()[0]
        )
    response = httpx.post(
        base + f"/registrations/{installation}/confirm",
        json={
            "generation": row["generation"],
            "challenge": proof["challenge"],
        },
    )
    assert response.status_code == 200, response.text


def snapshot(env):
    with env.runtime.store.connection() as db:
        return {
            table: [tuple(row) for row in db.execute(f"SELECT * FROM {table} ORDER BY rowid")]
            for table in ("registrations", "events", "outbox")
        }


@pytest.mark.parametrize("closed_socket", [False, True])
@pytest.mark.parametrize("replacement", ["recovery", "endpoint", "disable", "new-consent"])
def test_precommit_old_put_cannot_mutate_new_authority(
    env, monkeypatch, loopback, closed_socket, replacement
):
    entered, release, finished = (threading.Event() for _ in range(3))
    lock = threading.Lock()
    first = True
    rejected = []
    original_put = Store.put

    def lookup(host, port, *args, **kwargs):
        nonlocal first
        with lock:
            hold, first = first, False
        if hold:
            entered.set()
            assert release.wait(10)
        return env.lookup(host, port, *args, **kwargs)

    def put(self, principal, installation, body, policy):
        if body["registration_nonce"] != env.body["registration_nonce"]:
            return original_put(self, principal, installation, body, policy)
        try:
            return original_put(self, principal, installation, body, policy)
        except Rejected as error:
            rejected.append(error.status)
            raise
        finally:
            finished.set()

    monkeypatch.setattr(transport, "resolve_addresses", lookup)
    monkeypatch.setattr(Store, "put", put)
    old_socket = None
    with ThreadPoolExecutor(max_workers=1) as executor:
        if closed_socket:
            url = httpx.URL(loopback)
            old_socket = socket.create_connection((url.host, url.port), timeout=5)
            body = json.dumps(env.body).encode()
            old_socket.sendall(
                (
                    f"PUT {PREFIX}/registrations/phone HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                    f"Content-Type: application/json\r\nContent-Length: {len(body)}\r\n"
                    "Connection: close\r\n\r\n"
                ).encode()
                + body
            )
            old = None
        else:
            old = executor.submit(httpx.put, loopback + "/registrations/phone", json=env.body)
        try:
            assert entered.wait(5)
            if old_socket:
                old_socket.close()
                old_socket = None
            if replacement in {"disable", "new-consent"}:
                # Revoke BEFORE there has ever been a committed PUT.
                assert httpx.delete(loopback + "/registrations/phone").status_code == 200
            if replacement != "disable":
                installation = "new-consent-phone" if replacement == "new-consent" else "phone"
                body = {
                    **env.body,
                    "registration_revision": 3 if replacement == "endpoint" else 2,
                    "registration_nonce": "new_native_authority_0123456789",
                }
                if replacement == "endpoint":
                    body["endpoint"] += "-renewed"
                if replacement == "new-consent":
                    env.config["principals"][0]["session_ids"].append("session-b")
                    env.save()
                    body["session_ids"] = ["session-b"]
                    body["registration_revision"] = 1
                response = httpx.put(loopback + f"/registrations/{installation}", json=body)
                assert response.status_code == 200, response.text
                confirm(loopback, env, installation)
                # Preserve real pending delivery work, not just an empty queue.
                env.runtime.store.record(
                    {
                        "kind": "turn_done",
                        "session_id": body["session_ids"][0],
                        "turn_id": "replacement-turn",
                        "dedup": "replacement-turn",
                    },
                    env.profile.policy(),
                )
            expected = snapshot(env)
            if replacement != "disable":
                assert len(expected["outbox"]) == 1
            # Reopen the real durable store before the abandoned handler resumes.
            Store(env.profile.database)
        finally:
            release.set()
            if old_socket:
                old_socket.close()
        if old:
            assert old.result(5).status_code == 409
        assert finished.wait(5)
    assert rejected == [409]
    assert snapshot(env) == expected  # no changes to authority, proof, outbox or events
    if replacement != "disable":
        installation = "new-consent-phone" if replacement == "new-consent" else "phone"
        assert (
            Store(env.profile.database).registration(PRINCIPAL, installation)["status"] == "active"
        )


@pytest.mark.parametrize("revision", [None, True, 0, -1, 1.5, "2", 9007199254740992])
def test_missing_or_invalid_revision_fails_closed_at_api_and_store(env, revision):
    body = dict(env.body)
    if revision is None:
        body.pop("registration_revision")
    else:
        body["registration_revision"] = revision
    assert env.client.put(PREFIX + "/registrations/phone", json=body).status_code == 422
    with pytest.raises(Rejected) as error:
        env.runtime.store.put(PRINCIPAL, "phone", body, env.profile.policy())
    assert error.value.status == 422
    assert snapshot(env)["registrations"] == []


def test_revision_not_nonce_order_and_no_reset_on_same_installation(env):
    activate(env, registration_revision=40, registration_nonce="zzzz_0123456789abcdef")
    for revision in (1, 39, 40):
        before = snapshot(env)
        response = env.client.put(
            PREFIX + "/registrations/phone",
            json={
                **env.body,
                "registration_revision": revision,
                "registration_nonce": "aaaa_0123456789abcdef",
            },
        )
        assert response.status_code == 409
        assert snapshot(env) == before
    # A lexically smaller UUID/nonce has NO ordering meaning. Persisted revision wins.
    activate(env, registration_revision=41, registration_nonce="aaaa_0123456789abcdef")
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    before = snapshot(env)
    assert (
        env.client.put(
            PREFIX + "/registrations/phone",
            json={
                **env.body,
                "registration_revision": 999,
                "registration_nonce": "higher_after_revoke_0123456789",
            },
        ).status_code
        == 409
    )
    assert snapshot(env) == before
    # New explicit consent creates a DIFFERENT installation; rev1 is valid again.
    activate(env, installation="fresh-consent", registration_revision=1)
    assert env.runtime.store.registration(PRINCIPAL, "fresh-consent")["status"] == "active"


@pytest.mark.parametrize("legacy_status", ["pending", "active"])
def test_legacy_database_migration_invalidates_proofs_but_permits_upgrade(env, legacy_status):
    registration, hint = pending(env)
    if legacy_status == "active":
        response = env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={
                "generation": registration["generation"],
                "challenge": hint["challenge"],
            },
        )
        assert response.status_code == 200
    with env.runtime.store.connection() as db:
        # Exact previous schema, not just a modern row with zero revision.
        db.execute("ALTER TABLE registrations DROP COLUMN registration_revision")
    migrated = Store(env.profile.database)
    row = migrated.registration(PRINCIPAL, "phone")
    assert row["status"] == "upgrade_required" and row["registration_revision"] == 0
    assert row["endpoint"] == "" and row["keys_json"] == "{}"
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={
                "generation": registration["generation"],
                "challenge": hint["challenge"],
            },
        ).status_code
        == 409
    )
    assert snapshot(env)["outbox"] == []
    before = snapshot(env)
    Store(env.profile.database)  # restart doesn't reset floor/generation again
    assert snapshot(env) == before
    activate(env, registration_revision=2, registration_nonce="upgraded_native_nonce_0123456789")
    assert migrated.registration(PRINCIPAL, "phone")["status"] == "active"


def test_unknown_delete_requires_admission_and_cannot_exceed_capacity(env, monkeypatch):
    from dataclasses import replace
    from types import SimpleNamespace

    from mobile_push.config import Profile

    env.identity[0] = SimpleNamespace(provider="fixture", user_id="unadmitted")
    assert env.client.delete(PREFIX + "/registrations/unseen").status_code == 403
    assert snapshot(env)["registrations"] == []
    env.identity[0] = SimpleNamespace(provider="fixture", user_id="alice")
    activate(env)
    read_policy = Profile.policy
    monkeypatch.setattr(
        Profile, "policy", lambda self: replace(read_policy(self), max_registrations=1)
    )
    before = snapshot(env)
    assert env.client.delete(PREFIX + "/registrations/unseen").status_code == 429
    assert snapshot(env) == before
    # Capacity/removed grants never prevent revoking an existing owned authority.
    env.config["principals"] = []
    env.save()
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    before = snapshot(env)
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    assert snapshot(env) == before  # terminal DELETE acknowledgement recovery is idempotent


def test_legacy_revoked_row_never_reactivated_by_migration(env):
    activate(env)
    env.client.delete(PREFIX + "/registrations/phone")
    with env.runtime.store.connection() as db:
        db.execute("ALTER TABLE registrations DROP COLUMN registration_revision")
    migrated = Store(env.profile.database)
    assert migrated.registration(PRINCIPAL, "phone")["status"] == "revoked"
    assert (
        env.client.put(
            PREFIX + "/registrations/phone",
            json={
                **env.body,
                "registration_revision": 100,
                "registration_nonce": "upgraded_but_revoked_0123456789",
            },
        ).status_code
        == 409
    )
