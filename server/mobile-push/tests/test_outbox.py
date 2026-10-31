import dataclasses
import json
import sqlite3
import threading

from conftest import PREFIX, activate, end, pending

from mobile_push.service import Runtime
from mobile_push.store import Store


class RecordingSender:
    def __init__(self, status=201):
        self.status = status
        self.hints = []

    def send(self, registration, payload, policy):
        self.hints.append(json.loads(payload))
        return self.status


def test_real_outcome_hooks_dedup_minimal_hint_and_restart(env):
    activate(env)
    sender = RecordingSender()
    end(env)
    end(env)
    restarted = Runtime(env.profile, sender)
    restarted.initialise()
    assert restarted.deliver_one()
    assert not restarted.deliver_one()
    end(env)  # dedup includes previously delivered work
    assert not restarted.deliver_one()
    assert len(sender.hints) == 1
    hint = sender.hints[0]
    assert set(hint) == {
        "schema",
        "event_id",
        "kind",
        "generation",
        "registration_nonce",
        "expires_at",
    }
    assert hint["kind"] == "turn_done"
    assert "session-a" not in json.dumps(hint)


def test_hook_ignores_legacy_incomplete_interrupted_and_aliases(env):
    activate(env)
    env.runtime.session_end(session_id="session-a", completed=True)
    for kwargs in [
        dict(session_id="session-a", turn_id="old", completed=True, failed=False, interrupted=True),
        dict(
            session_id="runtime-alias",
            turn_id="new",
            completed=True,
            failed=False,
            interrupted=False,
        ),
    ]:
        env.runtime.session_end(**kwargs, turn_exit_reason="stop")
    assert env.runtime.store.claim(env.profile.policy()) is None
    env.runtime.session_end(
        session_id="session-a",
        turn_id="failed",
        completed=False,
        failed=True,
        interrupted=False,
        turn_exit_reason="error",
    )
    job = env.runtime.store.claim(env.profile.policy())
    assert json.loads(job["payload"])["kind"] == "turn_error"


def test_attention_resolution_out_of_order_cancels_stale_request(env):
    activate(env)
    env.runtime.human_input(
        kind="approval",
        session_id="session-a",
        request_id="observer-id",
        prompt="rm -rf secret",
        approval_id="RPC-ID",
        code="secret",
    )
    env.runtime.human_resolved(
        kind="approval", session_id="session-a", request_id="observer-id", outcome="deny"
    )
    env.runtime.human_resolved(kind="sudo", session_id="session-a", request_id="out-of-order")
    env.runtime.human_input(kind="sudo", session_id="session-a", request_id="out-of-order")
    events = env.client.get(PREFIX + "/events").json()["events"]
    assert [event["kind"] for event in events] == ["challenge", "input_resolved", "input_resolved"]
    assert events[1]["request_id"] == "observer-id"
    assert "RPC-ID" not in json.dumps(events) and "secret" not in json.dumps(events)
    sender = RecordingSender()
    env.runtime.sender = sender
    while env.runtime.deliver_one():
        pass
    assert all(hint["kind"] == "input_resolved" for hint in sender.hints)


def test_turn_completion_cancels_attention(env):
    activate(env)
    env.runtime.human_input(kind="clarify", session_id="session-a", request_id="question")
    end(env)
    assert "input" not in [
        event["kind"] for event in env.client.get(PREFIX + "/events").json()["events"]
    ]


def test_claim_lease_excludes_workers_and_recovers_after_expiry(env):
    activate(env)
    end(env)
    clock = [env.runtime.store.now()]
    first = Store(env.profile.database, clock=lambda: clock[0])
    second = Store(env.profile.database, clock=lambda: clock[0])
    job = first.claim(env.profile.policy())
    assert job and second.claim(env.profile.policy()) is None
    clock[0] += 31
    recovered = second.claim(env.profile.policy())
    assert recovered["id"] == job["id"] and recovered["lease_token"] != job["lease_token"]


def test_concurrent_claims_never_lease_same_job(env):
    activate(env)
    end(env)
    barrier = threading.Barrier(2)
    claims = []

    def worker():
        barrier.wait()
        claims.append(env.runtime.store.claim(env.profile.policy()))

    threads = [threading.Thread(target=worker) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert len([job for job in claims if job]) == 1


def test_generation_and_authz_are_rechecked_after_claim(env):
    activate(env)
    end(env)
    original = env.runtime.store.claim
    sender = RecordingSender()
    env.runtime.sender = sender

    def revoke_between_claim_and_send(policy):
        job = original(policy)
        if job:
            env.runtime.store.revoke(("fixture", "alice"), "phone")
        return job

    env.runtime.store.claim = revoke_between_claim_and_send
    assert env.runtime.deliver_one()
    assert sender.hints == []
    activate(env, installation="new-phone", registration_nonce="new_nonce_0123456789abcdef")
    end(env, turn="turn-b")

    def remove_acl_between_claim_and_send(policy):
        job = original(policy)
        env.config["principals"][0]["session_ids"] = []
        env.save()
        return job

    env.runtime.store.claim = remove_acl_between_claim_and_send
    assert env.runtime.deliver_one()
    assert sender.hints == []


def test_retries_are_capped_and_expire_with_durable_retention(env):
    activate(env)
    end(env)
    clock = [env.runtime.store.now()]
    env.runtime.store.clock = lambda: clock[0]
    sender = RecordingSender(503)
    env.runtime.sender = sender
    for index in range(5):
        assert env.runtime.deliver_one()
        assert not env.runtime.deliver_one()
        clock[0] += 300
    assert not env.runtime.deliver_one()
    assert len(sender.hints) == 5
    clock[0] += 5000
    assert env.runtime.store.claim(env.profile.policy()) is None
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM events").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM outbox").fetchone()[0] == 0


def test_expired_challenge_never_activates(env):
    _, hint = pending(env)
    with env.runtime.store.transaction() as db:
        db.execute("UPDATE registrations SET challenge_expires=0")
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": 1, "challenge": hint["challenge"]},
        ).status_code
        == 409
    )


def test_404_and_410_revoke_and_cancel_sibling_jobs(env):
    for status in [404, 410]:
        installation = f"phone-{status}"
        activate(
            env, installation=installation, registration_nonce=f"nonce_unique_for_status_{status}"
        )
        end(env, turn=f"turn-{status}")
        end(env, turn=f"sibling-{status}")
        env.runtime.sender = RecordingSender(status)
        assert env.runtime.deliver_one()
        assert (
            env.runtime.store.registration(("fixture", "alice"), installation)["status"]
            == "revoked"
        )
        assert not env.runtime.deliver_one()


def test_retention_is_capped_and_bounded_even_with_many_events(env):
    activate(env)
    policy = dataclasses.replace(env.profile.policy(), max_events=3)
    for index in range(8):
        env.runtime.store.record(
            {
                "kind": "turn_done",
                "session_id": "session-a",
                "turn_id": str(index),
                "dedup": str(index),
            },
            policy,
        )
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM events").fetchone()[0] == 3
        assert db.execute("SELECT count(*) FROM outbox").fetchone()[0] == 3


def test_opaque_ids_cannot_collide_through_delimiters(env):
    env.config["principals"][0]["session_ids"] = ["a:b", "a"]
    env.save()
    with sqlite3.connect(env.profile.home / "state.db") as db:
        db.executemany("INSERT INTO sessions VALUES(?,NULL)", [("a:b",), ("a",)])
    activate(env, session_ids=["a:b", "a"])
    for sid, turn in [("a:b", "c"), ("a", "b:c")]:
        env.runtime.session_end(
            session_id=sid,
            turn_id=turn,
            completed=True,
            failed=False,
            interrupted=False,
            turn_exit_reason="stop",
        )
    events = env.client.get(PREFIX + "/events").json()["events"]
    assert [
        (event["session_id"], event["turn_id"]) for event in events if event["kind"] == "turn_done"
    ] == [("a:b", "c"), ("a", "b:c")]


def test_deleted_durable_session_is_rechecked_at_send(env):
    activate(env)
    end(env)
    with sqlite3.connect(env.profile.home / "state.db") as db:
        db.execute("DELETE FROM sessions WHERE id='session-a'")
    sender = RecordingSender()
    env.runtime.sender = sender
    assert env.runtime.deliver_one()
    assert sender.hints == []
    assert all(
        event["kind"] == "challenge"
        for event in env.client.get(PREFIX + "/events").json()["events"]
    )


def test_revoke_serialises_with_inflight_send(env):
    activate(env)
    end(env)
    entered = threading.Event()
    release = threading.Event()

    class BlockingSender(RecordingSender):
        def send(self, *args):
            entered.set()
            assert release.wait(2)
            return super().send(*args)

    sender = BlockingSender()
    env.runtime.sender = sender
    worker = threading.Thread(target=env.runtime.deliver_one)
    worker.start()
    assert entered.wait(2)
    # Busy is explicit, not a success claiming revocation while send is in flight.
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 503
    release.set()
    worker.join(2)
    assert not worker.is_alive()
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    assert len(sender.hints) == 1
