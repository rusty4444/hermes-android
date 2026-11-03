import json
from types import SimpleNamespace

import pytest
from conftest import PREFIX, activate, end, pending


def test_requires_verified_session_not_client_headers(env):
    env.identity[0] = None
    for method, path in [
        ("get", "/capabilities"),
        ("get", "/events"),
        ("delete", "/registrations/phone"),
    ]:
        response = getattr(env.client, method)(
            PREFIX + path,
            headers={
                "X-User-ID": "alice",
                "X-Provider": "fixture",
                "Authorization": "Bearer alice",
            },
        )
        assert response.status_code == 401
    assert env.client.put(PREFIX + "/registrations/phone", json=env.body).status_code == 401
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm", json={"generation": 1, "challenge": "a" * 32}
        ).status_code
        == 401
    )


def test_capabilities_default_deny_and_explicit_enable(env):
    response = env.client.get(PREFIX + "/capabilities")
    assert response.json() == {
        "schema": 1,
        "registration_fence": 1,
        "session_scope_modes": ["explicit", "authorized"],
        "enabled": True,
        "transports": ["webpush"],
        "vapid_public_key": env.profile.policy().public_key(),
    }
    env.identity[0] = SimpleNamespace(provider="fixture", user_id="unknown")
    assert env.client.get(PREFIX + "/capabilities").json()["enabled"] is False
    assert env.client.get(PREFIX + "/events").status_code == 403
    env.config["enabled"] = False
    env.save()
    assert env.client.get(PREFIX + "/capabilities").json()["enabled"] is False
    assert env.client.put(PREFIX + "/registrations/phone", json=env.body).status_code == 503


@pytest.mark.parametrize(
    "sessions", [["session-b"], ["runtime-alias"], ["*"], ["session-a", "session-b"]]
)
def test_explicit_session_scope_no_parent_lineage_inheritance(env, sessions):
    assert env.client.put(
        PREFIX + "/registrations/phone", json={**env.body, "session_ids": sessions}
    ).status_code in {403, 422}


def test_owner_wildcard_requires_explicit_operator_grant(env):
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    activate(env, session_ids=["session-b"])
    assert env.runtime.store.registration(("fixture", "alice"), "phone")["status"] == "active"
    env.config["principals"][0]["session_ids"] = ["*"]
    env.save()
    assert env.client.get(PREFIX + "/capabilities").status_code == 503


def test_challenge_is_not_revealed_by_events_and_only_correct_proof_activates(env):
    registration, hint = pending(env)
    assert registration == {
        "generation": 1,
        "status": "pending",
        "registration_nonce": env.body["registration_nonce"],
        "registration_revision": env.body["registration_revision"],
    }
    events = env.client.get(PREFIX + "/events").json()
    assert events["events"][0]["kind"] == "challenge"
    assert "challenge" not in events["events"][0]
    assert hint["challenge"] not in json.dumps(events)
    end(env)
    assert len(env.client.get(PREFIX + "/events").json()["events"]) == 1
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": 1, "challenge": "wrong" * 8},
        ).status_code
        == 409
    )
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": 1, "challenge": hint["challenge"]},
        ).json()["status"]
        == "active"
    )
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": 1, "challenge": hint["challenge"]},
        ).status_code
        == 409  # consumed proof cannot reactivate; recovery rotates native revision
    )


def test_rotation_and_revoke_invalidate_all_old_generations(env):
    first, old = pending(env)
    assert env.client.put(PREFIX + "/registrations/phone", json=env.body).status_code == 409
    second, new = pending(env, registration_nonce="fresh_nonce_abcdef012345")
    assert second["generation"] == first["generation"] + 1
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": 1, "challenge": old["challenge"]},
        ).status_code
        == 409
    )
    assert env.client.delete(PREFIX + "/registrations/phone").json() == {
        "generation": 3,
        "status": "revoked",
    }
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": 2, "challenge": new["challenge"]},
        ).status_code
        == 409
    )
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM outbox").fetchone()[0] == 0
    assert (
        env.client.put(
            PREFIX + "/registrations/phone",
            json={
                **env.body,
                "registration_revision": 999,
                "registration_nonce": "fresh_after_revoke_012345",
            },
        ).status_code
        == 409
    )
    third, _ = pending(
        env, installation="new-phone", registration_nonce="another_nonce_abcdef012345"
    )
    assert third["generation"] == 1


def test_foreign_principal_and_provider_cannot_read_update_confirm_delete(env):
    registration, hint = pending(env)
    for principal in [("fixture", "bob"), ("other-provider", "alice")]:
        env.identity[0] = SimpleNamespace(provider=principal[0], user_id=principal[1])
        assert env.client.delete(PREFIX + "/registrations/phone").status_code == 404
        response = env.client.get(PREFIX + "/events")
        assert response.status_code == 403 or response.json()["events"] == []
        if principal[0] == "fixture":
            assert (
                env.client.put(
                    PREFIX + "/registrations/phone", json={**env.body, "session_ids": ["session-b"]}
                ).status_code
                == 404
            )
            assert (
                env.client.post(
                    PREFIX + "/registrations/phone/confirm",
                    json={"generation": 1, "challenge": hint["challenge"]},
                ).status_code
                == 404
            )


def test_minimal_routing_bounded_cursor_and_live_acl(env):
    activate(env)
    for index in range(4):
        end(env, turn=f"turn-{index}", model="secret-model", prompt="secret", approval_code="1234")
    first = env.client.get(PREFIX + "/events?after=0&limit=2").json()
    assert first["has_more"] is True
    second = env.client.get(PREFIX + f"/events?after={first['next_cursor']}&limit=2").json()
    third = env.client.get(PREFIX + f"/events?after={second['next_cursor']}&limit=2").json()
    assert third["has_more"] is False
    events = first["events"] + second["events"] + third["events"]
    assert len(events) == len({event["event_id"] for event in events}) == 5
    assert all("secret" not in json.dumps(event) for event in events)
    assert [event["kind"] for event in events].count("turn_done") == 4
    env.config["principals"][0]["session_ids"] = []
    env.save()
    assert all(
        event["kind"] == "challenge"
        for event in env.client.get(PREFIX + "/events").json()["events"]
    )
    assert env.client.get(PREFIX + "/events?limit=201").status_code == 422
    assert env.client.get(PREFIX + "/events?after=-1").status_code == 422


@pytest.mark.parametrize(
    "change",
    [
        {"event_kinds": ["approval"]},
        {"session_ids": []},
        {"event_kinds": ["turn_done", "turn_done"]},
        {"registration_nonce": "short"},
        {"provider": "fixture"},
        {"keys": {"p256dh": "a" * 87, "auth": "b" * 22}},
    ],
)
def test_rejects_malformed_or_extra_fields(env, change):
    assert (
        env.client.put(PREFIX + "/registrations/phone", json={**env.body, **change}).status_code
        == 422
    )


def test_body_bound(env):
    assert (
        env.client.put(
            PREFIX + "/registrations/phone",
            content=b" " * 32769,
            headers={"Content-Type": "application/json"},
        ).status_code
        == 413
    )


def test_revocation_still_works_after_operator_disables(env):
    activate(env)
    env.config["enabled"] = False
    env.config["principals"] = []
    env.save()
    assert env.client.delete(PREFIX + "/registrations/phone").status_code == 200
