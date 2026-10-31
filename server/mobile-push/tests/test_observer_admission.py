"""Observer admission fixes targets before asynchronous inbox drain."""

import json
from dataclasses import FrozenInstanceError
from types import SimpleNamespace

import pytest
from conftest import PREFIX, activate
from test_authorized_scope import PRINCIPAL, bound, emit, enroll
from test_outbox import RecordingSender

from mobile_push.config import Policy
from mobile_push.scope import SessionScope
from mobile_push.service import Runtime


def test_denied_event_cannot_gain_authority_from_later_acl_grant(env):
    enroll(env)
    assert not env.profile.policy().allowed(("fixture", "alice"), "session-b")
    # A real in-flight sender holds this same SQLite write lock. Force a valid
    # event into the durable inbox, then a different session denied at admission.
    with env.runtime.store.transaction():
        emit(env, "session-a", "allowed-while-busy")
        emit(env, "session-b", "denied-at-admission")
    with env.runtime.inbox.connection() as db:
        queued = [json.loads(row[0]) for row in db.execute("SELECT payload FROM inbox")]
    print("Queued real observer turns:", [item["turn_id"] for item in queued])
    env.config["principals"][0]["session_ids"].append("session-b")
    env.save()
    env.runtime.sender = RecordingSender()
    for _ in range(4):
        if not env.runtime.deliver_one():
            break
    feed = bound(env).json()["events"]
    turns = [item["turn_id"] for item in feed]
    print("Authenticated bound feed after later grant:", turns)
    assert "denied-at-admission" not in turns, (
        "An event denied by live ACL at observer admission was queued and later "
        "acquired authority from an ACL grant before inbox drain."
    )


def queued_events(env):
    with env.runtime.inbox.connection() as db:
        return [json.loads(row[0]) for row in db.execute("SELECT payload FROM inbox ORDER BY id")]


def restart_and_drain(env):
    sender = RecordingSender()
    restarted = Runtime(env.profile, sender)
    restarted.initialise()
    try:
        for _ in range(64):
            if not restarted.deliver_one():
                break
        else:
            pytest.fail("Inbox/outbox did not drain")
        assert restarted.inbox.peek() is None
    finally:
        restarted.stop()
    return sender


@pytest.mark.parametrize("mode", ["explicit", "authorized"])
@pytest.mark.parametrize("grant", ["session", "owner", "principal"])
@pytest.mark.parametrize("admission", ["observer", "queue-helper"])
def test_later_grants_cannot_expand_captured_targets_after_restart(env, mode, grant, admission):
    env.config["principals"][0]["session_ids"] = ["session-a", "session-b"]
    env.save()
    if mode == "authorized":
        enroll(env)
    else:
        activate(env, session_scope=mode, session_ids=["session-a", "session-b"])
    alice = env.config["principals"][0]
    alice["session_ids"] = ["session-a"]
    if grant == "principal":
        env.config["principals"].remove(alice)
    env.save()
    with env.runtime.store.transaction():
        if admission == "observer":
            emit(env, "session-b", "denied")
        else:
            env.runtime._queue_inbox(
                {
                    "kind": "turn_done",
                    "session_id": "session-b",
                    "turn_id": "denied",
                    "dedup": "denied",
                },
                env.profile.policy(),
            )
    assert [event["registration_generations"] for event in queued_events(env)] == [{}]
    if grant == "owner":
        alice["owner_all_sessions"] = True
    else:
        alice["session_ids"].append("session-b")
        if grant == "principal":
            env.config["principals"].append(alice)
    env.save()
    assert restart_and_drain(env).hints == []
    assert bound(env).json()["events"] == []
    # The same scope must still admit new events after the grant, not become a
    # static subscription to the old ACL or require a new registration.
    emit(env, "session-b", "newly-authorized")
    assert [event["turn_id"] for event in bound(env).json()["events"]] == ["newly-authorized"]
    assert [hint["kind"] for hint in restart_and_drain(env).hints] == ["turn_done"]


def test_observer_snapshots_exact_scope_kind_principal_and_active_generation(env):
    env.config["principals"][0]["owner_all_sessions"] = True
    env.config["principals"].append(
        {"provider": "foreign", "user_id": "alice", "session_ids": ["session-b"]}
    )
    env.save()
    enroll(env, installation="authorized")
    activate(env, installation="explicit-a", session_scope="explicit")
    activate(env, installation="explicit-b", session_ids=["session-b"])
    enroll(env, installation="wrong-kind", event_kinds=["input"])
    enroll(env, installation="pending", confirm=False)
    enroll(env, installation="revoked")
    assert env.client.delete(PREFIX + "/registrations/revoked").status_code == 200
    env.identity[0] = SimpleNamespace(provider="fixture", user_id="bob")
    enroll(env, installation="bob")
    env.identity[0] = SimpleNamespace(provider="foreign", user_id="alice")
    enroll(env, installation="foreign-provider")
    env.identity[0] = SimpleNamespace(provider="fixture", user_id="alice")
    # Renew one scope so targets must retain its actual generation, not a default.
    enroll(
        env,
        installation="authorized",
        registration_revision=2,
        registration_nonce="admission_generation_0123456789",
    )
    env.config["principals"][0]["owner_all_sessions"] = False
    env.save()
    with env.runtime.store.transaction():
        emit(env, "session-a", "a")
        emit(env, "session-b", "b")
    assert {
        event["turn_id"]: event["registration_generations"] for event in queued_events(env)
    } == {
        "a": {"authorized": 2, "explicit-a": 1},
        "b": {"bob": 1, "foreign-provider": 1},
    }
    # A broad grant before drain cannot attach the old B event to any of Alice's
    # fixture-provider registrations, even though other principals received it.
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    restart_and_drain(env)
    with env.runtime.store.connection() as db:
        delivered = {
            tuple(row)
            for row in db.execute(
                "SELECT outbox.installation,generation,turn_id FROM outbox JOIN events USING(event_id) "
                "WHERE kind='turn_done'"
            )
        }
    assert delivered == {
        ("authorized", 2, "a"),
        ("explicit-a", 1, "a"),
        ("bob", 1, "b"),
        ("foreign-provider", 1, "b"),
    }
    assert [event["turn_id"] for event in bound(env, "authorized", 2).json()["events"]] == ["a"]


def test_busy_fallback_preserves_empty_admission_map_after_policy_reload(env, monkeypatch):
    enroll(env)
    queue = env.runtime._queue_inbox

    def grant_before_fallback(event, policy):
        assert event["registration_generations"] == {}
        env.config["principals"][0]["session_ids"].append("session-b")
        env.save()
        assert not policy.allowed(PRINCIPAL, "session-b")
        assert env.profile.policy().allowed(PRINCIPAL, "session-b")
        queue(event, policy)

    monkeypatch.setattr(env.runtime, "_queue_inbox", grant_before_fallback)
    with env.runtime.store.transaction():
        emit(env, "session-b", "denied-before-busy")
    assert queued_events(env)[0]["registration_generations"] == {}
    assert restart_and_drain(env).hints == []
    assert bound(env).json()["events"] == []


@pytest.mark.parametrize("mode", ["explicit", "authorized"])
@pytest.mark.parametrize("kind", ["input_resolved", "turn_done", "turn_error"])
@pytest.mark.parametrize("queued_input", [False, True])
def test_unsubscribed_resolution_still_cancels_attention_after_restart(
    env, mode, kind, queued_input
):
    if mode == "authorized":
        enroll(env, event_kinds=["input"])
    else:
        activate(env, session_scope=mode, event_kinds=["input"])

    def prompt():
        env.runtime.human_input(kind="approval", session_id="session-a", request_id="request")

    if not queued_input:
        prompt()
    with env.runtime.store.transaction():
        if queued_input:
            prompt()
        if kind == "input_resolved":
            env.runtime.human_resolved(
                kind="approval", session_id="session-a", request_id="request"
            )
        else:
            env.runtime.session_end(
                session_id="session-a",
                turn_id="finished",
                completed=kind == "turn_done",
                failed=kind == "turn_error",
                interrupted=False,
                turn_exit_reason="stop",
            )
    queued = queued_events(env)
    assert queued[-1]["kind"] == kind
    assert queued[-1]["registration_generations"] == {}
    if queued_input:
        assert queued[0]["registration_generations"] == {"phone": 1}
    assert restart_and_drain(env).hints == []
    assert bound(env).json()["events"] == []
    # Cancellation authority is retained even without a subscribed delivery kind.
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT resolved FROM attention").fetchone()[0] == 1
        assert db.execute("SELECT count(*) FROM outbox WHERE done=0").fetchone()[0] == 0
    prompt()  # a duplicate/late observer cannot resurrect the resolved request
    assert restart_and_drain(env).hints == []


@pytest.mark.parametrize("mode", ["explicit", "authorized"])
def test_unsubscribed_resolution_before_queued_input_keeps_tombstone(env, mode):
    if mode == "authorized":
        enroll(env, event_kinds=["input"])
    else:
        activate(env, session_scope=mode, event_kinds=["input"])
    with env.runtime.store.transaction():
        env.runtime.human_resolved(kind="sudo", session_id="session-a", request_id="request")
        env.runtime.human_input(kind="sudo", session_id="session-a", request_id="request")
    assert [event["registration_generations"] for event in queued_events(env)] == [
        {},
        {"phone": 1},
    ]
    assert restart_and_drain(env).hints == []
    assert bound(env).json()["events"] == []


def test_admission_policy_copies_and_freezes_acl_inputs():
    sessions = {"session-a"}
    grants = {PRINCIPAL: sessions}
    owners = set()
    policy = Policy(True, grants, owners)
    sessions.add("session-b")
    grants[("fixture", "bob")] = {"session-b"}
    owners.add(PRINCIPAL)
    assert policy.allowed(PRINCIPAL, "session-a")
    assert not policy.allowed(PRINCIPAL, "session-b")
    assert not policy.admitted(("fixture", "bob"))
    assert not policy.owner_grants
    with pytest.raises(TypeError):
        policy.grants[PRINCIPAL] = frozenset({"session-b"})
    with pytest.raises(FrozenInstanceError):
        policy.enabled = False


def test_admission_scope_copies_and_freezes_explicit_selection():
    sessions = ["session-a"]
    scope = SessionScope.from_body({"session_scope": "explicit", "session_ids": sessions})
    sessions.append("session-b")
    assert scope.sessions == ("session-a",)
    with pytest.raises(FrozenInstanceError):
        scope.mode = "authorized"
