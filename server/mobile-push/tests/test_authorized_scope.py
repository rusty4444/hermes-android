"""Dynamic scopes use live operator ACLs, never a new ownership grant."""

import json
import sqlite3
import threading
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import pytest
from conftest import PREFIX, activate, end, pending
from fastapi import FastAPI
from fastapi.testclient import TestClient
from test_outbox import RecordingSender

from mobile_push.api import create_router
from mobile_push.config import Profile, Rejected
from mobile_push.service import Runtime
from mobile_push.store import Store

PRINCIPAL = ("fixture", "alice")


def authorized_body(env, **changes):
    body = {**env.body, "session_scope": "authorized", **changes}
    body.pop("session_ids", None)
    return body


def enroll(env, installation="phone", confirm=True, **changes):
    response = env.client.put(
        f"{PREFIX}/registrations/{installation}", json=authorized_body(env, **changes)
    )
    assert response.status_code == 200, response.text
    registration = response.json()
    with env.runtime.store.connection() as db:
        hint = json.loads(
            db.execute(
                "SELECT payload FROM outbox WHERE installation=? AND done=0", (installation,)
            ).fetchone()[0]
        )
    if confirm:
        response = env.client.post(
            f"{PREFIX}/registrations/{installation}/confirm",
            json={"generation": registration["generation"], "challenge": hint["challenge"]},
        )
        assert response.status_code == 200, response.text
    return registration, hint


def bound(env, installation="phone", generation=1, **params):
    return env.client.get(
        PREFIX + "/events",
        params={"installation_id": installation, "generation": generation, **params},
    )


def emit(env, sid, turn="turn"):
    env.runtime.session_end(
        session_id=sid,
        turn_id=turn,
        completed=True,
        failed=False,
        interrupted=False,
        turn_exit_reason="stop",
    )


def sessions(env, *ids):
    with sqlite3.connect(env.profile.home / "state.db") as db:
        db.executemany("INSERT INTO sessions VALUES(?,NULL)", [(sid,) for sid in ids])


def test_capabilities_advertise_additive_scope_modes(env):
    capabilities = env.client.get(PREFIX + "/capabilities").json()
    assert capabilities["schema"] == 1
    assert capabilities["registration_fence"] == 1
    assert capabilities["session_scope_modes"] == ["explicit", "authorized"]


@pytest.mark.parametrize("owner", [False, True])
def test_enroll_before_first_durable_session_and_include_future_sessions(env, owner):
    with sqlite3.connect(env.profile.home / "state.db") as db:
        db.execute("DELETE FROM sessions")
    env.config["principals"][0]["session_ids"] = []
    env.config["principals"][0]["owner_all_sessions"] = owner
    env.save()
    registration, hint = enroll(env)
    assert registration["generation"] == 1
    assert hint["registration_nonce"] == env.body["registration_nonce"]
    assert bound(env).json() == {
        "events": [],
        "next_cursor": 1,
        "has_more": False,
        "installation_id": "phone",
        "generation": 1,
        "session_scope": "authorized",
    }
    sessions(env, "future-session")
    if not owner:
        env.config["principals"][0]["session_ids"] = ["future-session"]
        env.save()
    emit(env, "future-session")
    events = bound(env).json()["events"]
    assert [(event["kind"], event["session_id"]) for event in events] == [
        ("turn_done", "future-session")
    ]
    sender = RecordingSender()
    env.runtime.sender = sender
    assert env.runtime.deliver_one()
    assert len(sender.hints) == 1
    assert sender.hints[0]["kind"] == "turn_done"
    assert "session_id" not in sender.hints[0]


def test_authorized_challenge_send_and_confirmation_work_without_state_database(env):
    (env.profile.home / "state.db").unlink()
    env.config["principals"][0]["session_ids"] = []
    env.save()
    registration, hint = enroll(env, confirm=False)
    sender = RecordingSender()
    env.runtime.sender = sender
    assert env.runtime.deliver_one()
    assert sender.hints == [hint]
    response = env.client.post(
        PREFIX + "/registrations/phone/confirm",
        json={"generation": registration["generation"], "challenge": hint["challenge"]},
    )
    assert response.status_code == 200
    emit(env, "not-durable")
    assert not env.runtime.deliver_one()
    assert bound(env).json()["events"] == []


def test_restricted_acl_remains_strict_and_tracks_live_additions(env):
    enroll(env)
    emit(env, "session-a", "allowed")
    emit(env, "session-b", "denied-child")
    emit(env, "runtime-alias", "not-durable")
    assert [event["turn_id"] for event in bound(env).json()["events"]] == ["allowed"]
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM outbox").fetchone()[0] == 1
    env.config["principals"][0]["session_ids"].append("session-b")
    env.save()
    emit(env, "session-b", "newly-allowed")
    assert [event["session_id"] for event in bound(env).json()["events"]] == [
        "session-a",
        "session-b",
    ]


def test_owner_grant_covers_current_and_future_but_never_nondurable_sessions(env):
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    enroll(env)
    emit(env, "session-b", "existing")
    emit(env, "future", "too-early")
    sessions(env, "future")
    emit(env, "future", "durable-now")
    assert [event["turn_id"] for event in bound(env).json()["events"]] == [
        "existing",
        "durable-now",
    ]
    env.config["principals"][0]["owner_all_sessions"] = False
    env.save()
    assert bound(env).json()["events"] == []


@pytest.mark.parametrize("mode", [None, "explicit", "authorized"])
@pytest.mark.parametrize("change", ["acl", "deleted", "principal", "disabled"])
def test_send_rechecks_live_authority_after_claim(env, mode, change):
    if mode == "authorized":
        enroll(env)
    else:
        activate(env, **({"session_scope": mode} if mode else {}))
    end(env)
    claim = env.runtime.store.claim

    def change_after_claim(policy):
        job = claim(policy)
        assert job is not None
        if change == "deleted":
            with sqlite3.connect(env.profile.home / "state.db") as db:
                db.execute("DELETE FROM sessions WHERE id='session-a'")
        else:
            if change == "acl":
                env.config["principals"][0]["session_ids"] = []
            elif change == "principal":
                env.config["principals"] = env.config["principals"][1:]
            else:
                env.config["enabled"] = False
            env.save()
        return job

    env.runtime.store.claim = change_after_claim
    sender = RecordingSender()
    env.runtime.sender = sender
    assert env.runtime.deliver_one()
    assert sender.hints == []
    response = bound(env)
    if change in {"acl", "deleted"}:
        assert response.status_code == 200
        assert response.json()["events"] == []
    else:
        assert response.status_code == (403 if change == "principal" else 503)
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT done,payload FROM outbox").fetchone()[:] == (1, "")


@pytest.mark.parametrize("authorized", [False, True])
@pytest.mark.parametrize("change", ["acl", "deleted", "principal"])
def test_confirmation_rechecks_scope_without_broadening(env, authorized, change):
    if authorized:
        registration, hint = enroll(env, confirm=False)
    else:
        registration, hint = pending(env)
    if change == "deleted":
        with sqlite3.connect(env.profile.home / "state.db") as db:
            db.execute("DELETE FROM sessions WHERE id='session-a'")
    else:
        if change == "acl":
            env.config["principals"][0]["session_ids"] = []
        else:
            env.config["principals"] = env.config["principals"][1:]
        env.save()
    response = env.client.post(
        PREFIX + "/registrations/phone/confirm",
        json={"generation": registration["generation"], "challenge": hint["challenge"]},
    )
    expected = 200 if authorized and change != "principal" else 403
    assert response.status_code == expected, response.text
    assert env.runtime.store.registration(PRINCIPAL, "phone")["status"] == (
        "active" if expected == 200 else "pending"
    )


@pytest.mark.parametrize(
    "fields",
    [
        {},
        {"session_ids": None},
        {"session_ids": []},
        {"session_scope": "explicit"},
        {"session_scope": "explicit", "session_ids": None},
        {"session_scope": None, "session_ids": ["session-a"]},
        {"session_scope": "all", "session_ids": ["session-a"]},
        {"session_scope": "authorised"},
        {"session_scope": True},
        {"session_scope": "authorized", "session_ids": []},
        {"session_scope": "authorized", "session_ids": None},
        {"session_scope": "authorized", "session_ids": ["session-a"]},
        {"session_ids": ["session-a", "session-a"]},
        {"session_ids": ["session-a "]},
        {"session_ids": ["session-a\n"]},
        {"session_ids": ["*"]},
        {"session_ids": ["a"] * 129},
        {"session_ids": "session-a"},
    ],
)
def test_invalid_scope_rejected_before_dns_and_store_mutation(env, monkeypatch, fields):
    from mobile_push import api

    def no_dns(*args):
        pytest.fail("Malformed scope reached endpoint/DNS validation")

    monkeypatch.setattr(api, "validate_endpoint", no_dns)
    body = {key: value for key, value in env.body.items() if key != "session_ids"}
    body.update(fields)
    response = env.client.put(PREFIX + "/registrations/phone", json=body)
    assert response.status_code == 422, response.text
    # The durable boundary must reject malformed scopes from older handlers too.
    with pytest.raises(Rejected) as error:
        env.runtime.store.put(PRINCIPAL, "phone", body, env.profile.policy())
    assert error.value.status == 422
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM registrations").fetchone()[0] == 0


@pytest.mark.parametrize("mode", [None, "explicit"])
def test_legacy_and_explicit_scopes_remain_exact_when_owner_has_broad_acl(env, mode):
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    activate(env, **({"session_scope": mode} if mode else {}))
    row = env.runtime.store.registration(PRINCIPAL, "phone")
    assert row["session_scope"] == "explicit"
    end(env)
    emit(env, "session-b")
    assert [event["session_id"] for event in bound(env).json()["events"]] == ["session-a"]
    assert bound(env).json()["session_scope"] == "explicit"


def test_authorized_scope_survives_restart_and_fenced_endpoint_renewal(env):
    first, old_hint = enroll(env)
    reopened = Store(env.profile.database)
    assert reopened.registration(PRINCIPAL, "phone")["session_scope"] == "authorized"
    end(env, turn="old-generation")
    second, hint = enroll(
        env,
        confirm=False,
        registration_revision=2,
        registration_nonce="new_authorized_nonce_0123456789",
        endpoint=env.body["endpoint"] + "-new",
    )
    assert second["generation"] == first["generation"] + 1
    row = reopened.registration(PRINCIPAL, "phone")
    assert row["session_scope"] == "authorized" and json.loads(row["sessions_json"]) == []
    assert bound(env, generation=first["generation"]).status_code == 409
    assert bound(env, generation=second["generation"]).status_code == 409
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": first["generation"], "challenge": old_hint["challenge"]},
        ).status_code
        == 409
    )
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": second["generation"], "challenge": hint["challenge"]},
        ).status_code
        == 200
    )
    end(env, turn="new-generation")
    assert bound(env, generation=second["generation"]).json()["session_scope"] == "authorized"
    assert (
        env.client.put(PREFIX + "/registrations/phone", json=authorized_body(env)).status_code
        == 409
    )
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    assert bound(env, generation=second["generation"]).status_code == 409
    assert (
        env.client.put(
            PREFIX + "/registrations/phone",
            json=authorized_body(
                env, registration_revision=99, registration_nonce="after_revoke_nonce_0123456789"
            ),
        ).status_code
        == 409
    )


@pytest.mark.parametrize("status", ["pending", "active", "revoked"])
def test_migrate_old_scope_column_defaults_explicit_without_broadening(env, status):
    registration, hint = pending(env)
    if status != "pending":
        assert (
            env.client.post(
                PREFIX + "/registrations/phone/confirm",
                json={"generation": registration["generation"], "challenge": hint["challenge"]},
            ).status_code
            == 200
        )
    if status == "revoked":
        env.client.delete(PREFIX + "/registrations/phone")
    before = env.runtime.store.registration(PRINCIPAL, "phone")
    with env.runtime.store.connection() as db:
        db.execute("ALTER TABLE registrations DROP COLUMN session_scope")
    migrated = Store(env.profile.database).registration(PRINCIPAL, "phone")
    assert migrated == {**before, "session_scope": "explicit"}
    assert migrated["status"] == status
    assert Store(env.profile.database).registration(PRINCIPAL, "phone") == migrated
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    emit(env, "session-b")
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM events WHERE kind='turn_done'").fetchone()[0] == 0


def test_bound_paging_filters_other_installations_scopes_kinds_and_hidden_rows(env):
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    activate(env, installation="other-explicit", session_ids=["session-b"])
    enroll(env, event_kinds=["turn_done"])
    for index in range(5):
        emit(env, "session-b", f"visible-{index}")
        env.runtime.human_resolved(
            kind="approval", session_id="session-b", request_id=f"hidden-{index}"
        )
    pages, events, after = [], [], 0
    for _ in range(4):
        response = bound(env, after=after, limit=2)
        assert response.status_code == 200, response.text
        page = response.json()
        assert {key: page[key] for key in ("installation_id", "generation", "session_scope")} == {
            "installation_id": "phone",
            "generation": 1,
            "session_scope": "authorized",
        }
        assert type(page["generation"]) is int
        pages.append(page)
        events.extend(page["events"])
        assert page["next_cursor"] > after
        after = page["next_cursor"]
        if not page["has_more"]:
            break
    assert [len(page["events"]) for page in pages] == [2, 2, 1]
    assert [event["turn_id"] for event in events] == [f"visible-{index}" for index in range(5)]
    assert len({event["event_id"] for event in events}) == 5
    assert bound(env, after=after).json()["events"] == []
    # Explicit registrations cannot borrow their owner's authorized registration scope.
    assert [
        event["kind"] for event in bound(env, installation="other-explicit").json()["events"]
    ] == ["turn_done", "input_resolved"] * 5
    legacy = env.client.get(PREFIX + "/events").json()
    assert any(event["kind"] == "challenge" for event in legacy["events"])
    assert "installation_id" not in legacy  # legacy response shape stays compatible


@pytest.mark.parametrize(
    "params",
    [
        {"installation_id": "phone"},
        {"generation": "1"},
        {"installation_id": "", "generation": "1"},
        {"installation_id": "phone ", "generation": "1"},
        {"installation_id": "phone\n", "generation": "1"},
        {"installation_id": "*", "generation": "1"},
        *[
            {"installation_id": "phone", "generation": value}
            for value in (
                "",
                "0",
                "-1",
                "1.0",
                "+1",
                "1e0",
                "true",
                " 1",
                "1\n",
                "9223372036854775808",
            )
        ],
        [("installation_id", "phone"), ("generation", "1"), ("generation", "2")],
        [("installation_id", "phone"), ("installation_id", "other"), ("generation", "1")],
    ],
)
def test_bound_query_requires_exact_paired_parameters(env, params):
    activate(env)
    response = env.client.get(PREFIX + "/events", params=params)
    assert response.status_code == 422, response.text


def test_bound_api_fails_closed_for_pending_foreign_provider_wrong_generation_and_revoked(env):
    registration, hint = enroll(env, confirm=False)
    assert bound(env).status_code == 409
    assert bound(env, installation="missing").status_code == 404
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": registration["generation"], "challenge": hint["challenge"]},
        ).status_code
        == 200
    )
    end(env)
    for provider, user in [("fixture", "bob"), ("other-provider", "alice")]:
        env.config["principals"].append(
            {"provider": provider, "user_id": user, "owner_all_sessions": True}
        )
        env.save()
        env.identity[0] = SimpleNamespace(provider=provider, user_id=user)
        response = bound(env)
        assert response.status_code == 404 and "turn-a" not in response.text
    env.identity[0] = SimpleNamespace(provider="fixture", user_id="alice")
    assert bound(env, generation=2).status_code == 409
    env.identity[0] = None
    assert bound(env).status_code == 401
    env.identity[0] = SimpleNamespace(provider="fixture", user_id="alice")
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    assert bound(env).status_code == 409


def test_selected_profile_isolates_authorized_registration_and_bound_events(env, tmp_path):
    second = Profile(tmp_path / "selected-profile")
    second.directory.mkdir(parents=True)
    config = json.loads(json.dumps(env.config))
    config["principals"][0]["owner_all_sessions"] = True
    config_path = second.directory / "config.json"
    config_path.write_text(json.dumps(config))
    config_path.chmod(0o600)
    with sqlite3.connect(second.home / "state.db") as db:
        db.execute("CREATE TABLE sessions(id TEXT PRIMARY KEY)")
        db.execute("INSERT INTO sessions VALUES('second-only')")
    runtime = Runtime(second)
    runtime.initialise()
    app = FastAPI()

    @app.middleware("http")
    async def verified_fixture(request, call_next):
        request.state.session = SimpleNamespace(provider="fixture", user_id="alice")
        return await call_next(request)

    # Fixture-selected immutable Profile, not a client-supplied filesystem path.
    app.include_router(create_router(lambda: second), prefix=PREFIX)
    enroll(env)
    end(env)
    with TestClient(app) as client:
        params = {"installation_id": "phone", "generation": 1}
        assert client.get(PREFIX + "/events", params=params).status_code == 404
        response = client.put(PREFIX + "/registrations/phone", json=authorized_body(env))
        assert response.status_code == 200
        with runtime.store.connection() as db:
            hint = json.loads(db.execute("SELECT payload FROM outbox").fetchone()[0])
        assert (
            client.post(
                PREFIX + "/registrations/phone/confirm",
                json={"generation": 1, "challenge": hint["challenge"]},
            ).status_code
            == 200
        )
        runtime.session_end(
            session_id="second-only",
            turn_id="selected-turn",
            completed=True,
            failed=False,
            interrupted=False,
            turn_exit_reason="stop",
        )
        assert [
            event["session_id"]
            for event in client.get(PREFIX + "/events", params=params).json()["events"]
        ] == ["second-only"]
        assert [event["session_id"] for event in bound(env).json()["events"]] == ["session-a"]
    runtime.stop()


@pytest.mark.parametrize("count", [1, 128])
def test_explicit_scope_accepts_exact_count_boundaries(env, count):
    ids = [f"boundary-{index}" for index in range(count)]
    sessions(env, *ids)
    env.config["principals"][0]["session_ids"] = ids
    env.save()
    activate(env, session_scope="explicit", session_ids=ids)
    assert json.loads(env.runtime.store.registration(PRINCIPAL, "phone")["sessions_json"]) == ids


def test_migration_from_before_both_fences_and_scopes_keeps_upgrade_explicit(env):
    pending(env)
    with env.runtime.store.connection() as db:
        db.execute("ALTER TABLE registrations DROP COLUMN registration_revision")
        db.execute("ALTER TABLE registrations DROP COLUMN session_scope")
    migrated = Store(env.profile.database)
    before = migrated.registration(PRINCIPAL, "phone")
    assert before["status"] == "upgrade_required"
    assert before["session_scope"] == "explicit"
    assert before["registration_revision"] == 0
    activate(env, registration_revision=2, registration_nonce="upgrade_nonce_0123456789")
    after = migrated.registration(PRINCIPAL, "phone")
    assert after["session_scope"] == "explicit"
    assert after["generation"] > before["generation"]
    assert after["registration_revision"] == 2


@pytest.mark.parametrize("replacement", ["explicit", "authorized", "revoke", "new-consent"])
def test_held_authorized_put_cannot_replace_new_scope_or_delete_tombstone(
    env, monkeypatch, replacement
):
    from mobile_push import transport

    entered, release = threading.Event(), threading.Event()
    lock = threading.Lock()
    first = True

    def lookup(host, port, *args, **kwargs):
        nonlocal first
        with lock:
            hold, first = first, False
        if hold:
            entered.set()
            assert release.wait(5)
        return env.lookup(host, port, *args, **kwargs)

    monkeypatch.setattr(transport, "resolve_addresses", lookup)
    with ThreadPoolExecutor(max_workers=1) as executor:
        old = executor.submit(
            env.client.put, PREFIX + "/registrations/phone", json=authorized_body(env)
        )
        try:
            assert entered.wait(3)
            if replacement in {"revoke", "new-consent"}:
                assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
            if replacement == "explicit":
                activate(env, registration_revision=2, registration_nonce="explicit_new_0123456789")
            elif replacement in {"authorized", "new-consent"}:
                enroll(
                    env,
                    installation="new-phone" if replacement == "new-consent" else "phone",
                    registration_revision=1 if replacement == "new-consent" else 2,
                    registration_nonce="authorized_new_0123456789",
                )
            end(env)
            with env.runtime.store.connection() as db:
                before = {
                    table: [
                        tuple(row) for row in db.execute(f"SELECT * FROM {table} ORDER BY rowid")
                    ]
                    for table in ("registrations", "events", "outbox", "registration_nonces")
                }
        finally:
            release.set()
        assert old.result(3).status_code == 409
    with env.runtime.store.connection() as db:
        after = {
            table: [tuple(row) for row in db.execute(f"SELECT * FROM {table} ORDER BY rowid")]
            for table in before
        }
    assert after == before


@pytest.mark.parametrize("change", ["acl", "deleted", "renewal", "new-consent"])
def test_authorized_inbox_drain_rechecks_scope_durability_and_captured_generation(env, change):
    enroll(env)
    env.runtime._queue_inbox(
        {"kind": "turn_done", "session_id": "session-a", "turn_id": "old", "dedup": "old"},
        env.profile.policy(),
    )
    if change == "acl":
        env.config["principals"][0]["session_ids"] = []
        env.save()
    elif change == "deleted":
        with sqlite3.connect(env.profile.home / "state.db") as db:
            db.execute("DELETE FROM sessions WHERE id='session-a'")
    elif change == "renewal":
        enroll(env, registration_revision=2, registration_nonce="inbox_renewal_0123456789")
    else:
        assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
        enroll(env, installation="new-phone")
    sender = RecordingSender()
    restarted = Runtime(env.profile, sender)
    restarted.initialise()
    try:
        assert not restarted.deliver_one()
        assert restarted.inbox.peek() is None
        assert sender.hints == []
    finally:
        restarted.stop()
