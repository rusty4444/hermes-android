"""Lost ACK recovery retains consent, but rotates native nonce/revision authority.

The released same-operation replay contract is superseded by the transactional
pre-commit fence. Keep every original recovery/security schedule, asserting stale
replays are read-only rejections and a fresh already-consented handshake recovers.
"""

import json

import pytest
from conftest import PREFIX, end, pending

from mobile_push.config import Rejected
from mobile_push.store import Store


def confirm(env, registration, hint):
    return env.client.post(
        PREFIX + "/registrations/phone/confirm",
        json={"generation": registration["generation"], "challenge": hint["challenge"]},
    )


def renewed(env, prior, *, nonce="recovered_nonce_0123456789"):
    return pending(env, registration_revision=prior["registration_revision"] + 1,
                   registration_nonce=nonce)


def test_lost_put_ack_recovers_fenced_authority_without_new_consent(env):
    first, hint = pending(env)  # Commit, then discard response at the client.
    for _ in range(3):
        retry = env.client.put(PREFIX + "/registrations/phone", json=env.body)
        assert retry.status_code == 409
    with env.runtime.store.connection() as db:
        rows = db.execute("SELECT payload FROM outbox").fetchall()
    assert [json.loads(row[0]) for row in rows] == [hint]  # replay is read-only
    second, proof = renewed(env, first)
    assert second["generation"] == first["generation"] + 1
    assert confirm(env, first, hint).status_code == 409
    assert confirm(env, second, proof).json()["status"] == "active"
    current = env.runtime.store.registration(("fixture", "alice"), "phone")
    assert json.loads(current["sessions_json"]) == env.body["session_ids"]
    assert current["endpoint"] == env.body["endpoint"]


def test_lost_confirm_ack_after_expiry_preserves_events_until_fenced_recovery(env):
    first, hint = pending(env)
    assert confirm(env, first, hint).json()["status"] == "active"
    end(env)
    env.runtime.store.clock = lambda: hint["expires_at"] + 1
    with env.runtime.store.connection() as db:
        db.execute("UPDATE registrations SET challenge_expires=0")
        before = [tuple(row) for row in db.execute("SELECT * FROM outbox")]
    assert confirm(env, first, hint).status_code == 409
    assert env.client.put(PREFIX + "/registrations/phone", json=env.body).status_code == 409
    with env.runtime.store.connection() as db:
        assert [tuple(row) for row in db.execute("SELECT * FROM outbox")] == before
    recovered, proof = renewed(env, first)
    assert confirm(env, recovered, proof).json()["status"] == "active"
    # Recovery intentionally retires old delivery authority, not durable events.
    assert any(e["kind"] == "turn_done" for e in env.client.get(PREFIX + "/events").json()["events"])


def test_expired_pending_retry_refreshes_proof_not_consent(env):
    first, old = pending(env)
    with env.runtime.store.connection() as db:
        db.execute("UPDATE registrations SET challenge_expires=0")
    assert env.client.put(PREFIX + "/registrations/phone", json=env.body).status_code == 409
    second, new = renewed(env, first)
    with env.runtime.store.connection() as db:
        queued = db.execute("SELECT payload FROM outbox WHERE done=0").fetchall()
    assert len(queued) == 1
    assert json.loads(queued[0][0]) == new
    assert new["challenge"] != old["challenge"]
    assert new["event_id"] != old["event_id"]
    assert second["generation"] > first["generation"]
    assert confirm(env, first, old).status_code == 409
    assert confirm(env, second, new).json()["status"] == "active"


def test_same_nonce_changed_body_never_changes_scope_or_endpoint(env):
    first, hint = pending(env)
    for changes in [
        {"endpoint": "https://push.example.test/different"},
        {"event_kinds": ["turn_done"]},
    ]:
        assert env.client.put(PREFIX + "/registrations/phone", json={
            **env.body, "registration_revision": first["registration_revision"] + 1, **changes
        }).status_code == 409
    assert confirm(env, first, hint).json()["status"] == "active"


def test_superseded_and_revoked_nonces_cannot_be_replayed(env):
    first, old = pending(env)
    newer_body = {**env.body, "registration_nonce": "new_nonce_abcdef01234567",
                  "registration_revision": first["registration_revision"] + 1}
    second, new = pending(env, **newer_body)
    assert second["generation"] == first["generation"] + 1
    # An already-used nonce cannot return even with a numerically newer ordinal.
    assert env.client.put(PREFIX + "/registrations/phone", json={
        **env.body, "registration_revision": second["registration_revision"] + 1
    }).status_code == 409
    assert confirm(env, first, old).status_code == 409
    assert confirm(env, second, new).status_code == 200
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
    assert confirm(env, second, new).status_code == 409
    for body in (env.body, newer_body):
        assert env.client.put(PREFIX + "/registrations/phone", json=body).status_code == 409
    assert env.runtime.store.registration(("fixture", "alice"), "phone")["status"] == "revoked"


def test_recovery_and_nonce_tombstones_survive_server_store_restart(env):
    first, hint = pending(env)
    assert confirm(env, first, hint).status_code == 200
    reopened = Store(env.profile.database)
    with pytest.raises(Rejected) as error:
        reopened.put(("fixture", "alice"), "phone", env.body, env.profile.policy())
    assert error.value.status == 409
    with pytest.raises(Rejected) as error:
        reopened.confirm(("fixture", "alice"), "phone", first["generation"],
                         hint["challenge"], env.profile.policy())
    assert error.value.status == 409
    recovered, proof = renewed(env, first)
    assert confirm(env, recovered, proof).status_code == 200
    assert env.client.post(PREFIX + "/registrations/phone/confirm", json={
        "generation": recovered["generation"], "challenge": "wrong" * 8
    }).status_code == 409
    reopened.revoke(("fixture", "alice"), "phone")
    newer = Store(env.profile.database)
    with pytest.raises(Rejected) as error:
        newer.put(("fixture", "alice"), "phone", env.body, env.profile.policy())
    assert error.value.status == 409


def test_retry_still_rechecks_authentication_and_live_policy(env):
    first, hint = pending(env)
    # Pending proof keeps the original authorization check reachable; active
    # proof replay is now invalid regardless of policy, never reactivation.
    env.config["principals"][0]["session_ids"] = []
    env.save()
    assert confirm(env, first, hint).status_code == 403
    assert env.client.put(PREFIX + "/registrations/phone", json=env.body).status_code == 403
    env.config["enabled"] = False
    env.save()
    assert confirm(env, first, hint).status_code == 503
    env.identity[0] = None
    assert confirm(env, first, hint).status_code == 401
