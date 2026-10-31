"""One real Hermes-mounted router, real profile dependency, disposable homes only."""

import importlib
import json
import secrets
import sys
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import pytest
from conftest import PREFIX
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from test_host_lifecycle import PLUGIN, SOURCE, host, other_home
from test_transport import decrypt
from test_transport import receiver as receiver

from mobile_push.config import Profile
from mobile_push.service import Runtime

pytestmark = pytest.mark.skipif(not SOURCE, reason="Set HERMES_AGENT_SOURCE for host contract")


@pytest.fixture
def mounted(env, monkeypatch):
    host(env, monkeypatch)
    from hermes_cli import profiles, web_server_profiles
    from hermes_cli import web_server_dashboard as loader
    from hermes_constants import (
        get_hermes_home,
        reset_hermes_home_override,
        set_hermes_home_override,
    )

    other = other_home(env)
    # Exercise the real name validation/resolver, not a fake profile dependency.
    monkeypatch.setattr(profiles, "_get_default_hermes_home", lambda: env.profile.home)
    monkeypatch.setattr(profiles, "_get_profiles_root", lambda: other.parent)
    monkeypatch.setattr(web_server_profiles, "get_process_hermes_home", lambda: env.profile.home)
    from hermes_cli.dashboard_auth.middleware import gated_auth_middleware
    from hermes_cli.dashboard_auth.routes import router as auth_router

    app = FastAPI()
    app.include_router(auth_router)
    app.middleware("http")(gated_auth_middleware)

    @app.middleware("http")
    async def verified_session(request, call_next):
        if env.identity[0] is not None:
            request.state.session = env.identity[0]
        return await call_next(request)

    @app.get("/scope", dependencies=[Depends(loader._plugin_route_secret_scope)])
    def scope():
        return {"home": str(get_hermes_home())}

    token = set_hermes_home_override(str(env.profile.home))
    try:
        assert loader._mount_one_plugin_api(
            app,
            {
                "name": "mobile-push",
                "source": "user",
                "_dir": str(PLUGIN / "dashboard"),
                "_api_file": "plugin_api.py",
            },
            {"mobile-push"},
            set(),
        )
    finally:
        reset_hermes_home_override(token)
    private_api = sys.modules["hermes_dashboard_plugin_mobile-push"]._api
    transport = importlib.import_module(private_api.__package__ + ".transport")
    monkeypatch.setattr(transport, "resolve_addresses", env.lookup)
    with TestClient(app) as client:
        yield SimpleNamespace(client=client, other=Profile(other), app=app)


def challenge(profile, installation="phone"):
    import sqlite3

    with sqlite3.connect(profile.database) as db:
        return json.loads(
            db.execute(
                "SELECT payload FROM outbox WHERE installation=? AND done=0", (installation,)
            ).fetchone()[0]
        )


def test_one_mounted_router_uses_vetted_profile_for_every_operation(env, mounted):
    client = mounted.client
    query = "?profile=other-profile"
    assert client.get("/scope" + query).json()["home"] == str(mounted.other.home)
    config = mounted.other.directory / "config.json"
    config.write_text(json.dumps({"enabled": False}))
    config.chmod(0o600)
    assert client.get(PREFIX + "/capabilities" + query).json()["enabled"] is False
    assert client.put(PREFIX + "/registrations/phone" + query, json=env.body).status_code == 503
    assert not mounted.other.database.exists()
    config.write_text(json.dumps(env.config))
    # Two homes, same installation and nonce; they must not collide.
    bodies = [env.body, {**env.body, "event_kinds": ["input"]}]
    for suffix, profile, body in [
        ("?profile=default", env.profile, bodies[0]),
        (query, mounted.other, bodies[1]),
    ]:
        assert client.get(PREFIX + "/capabilities" + suffix).json()["enabled"]
        reply = client.put(PREFIX + "/registrations/phone" + suffix, json=body)
        assert reply.status_code == 200
        proof = challenge(profile)
        assert (
            client.post(
                PREFIX + "/registrations/phone/confirm" + suffix,
                json={"generation": 1, "challenge": proof["challenge"]},
            ).status_code
            == 200
        )
    launch = env.runtime.store.registration(("fixture", "alice"), "phone")
    runtime = Runtime(mounted.other)
    runtime.initialise()
    try:
        other = runtime.store.registration(("fixture", "alice"), "phone")
        assert launch["kinds_json"] != other["kinds_json"]
        # Hook delivery stays bound to the lifecycle runtime's immutable home.
        runtime.human_input(kind="approval", session_id="session-a", request_id="other-only")
        events_other = client.get(PREFIX + "/events" + query).json()["events"]
        events_launch = client.get(PREFIX + "/events?profile=default").json()["events"]
        assert any(e.get("request_id") == "other-only" for e in events_other)
        assert not any(e.get("request_id") == "other-only" for e in events_launch)

        # Overlapping async dependency scopes must not bleed into sync workers.
        def has_other_event(profile):
            response = client.get(PREFIX + "/events", params={"profile": profile})
            assert response.status_code == 200
            return any(e.get("request_id") == "other-only" for e in response.json()["events"])

        names = ["default", "other-profile"] * 10
        with ThreadPoolExecutor(max_workers=4) as pool:
            assert list(pool.map(has_other_event, names)) == [
                name == "other-profile" for name in names
            ]
        assert client.delete(PREFIX + "/registrations/phone" + query).status_code == 200
        assert runtime.store.registration(("fixture", "alice"), "phone")["status"] == "revoked"
        assert env.runtime.store.registration(("fixture", "alice"), "phone")["status"] == "active"
    finally:
        runtime.stop()
    assert client.get(PREFIX + "/capabilities?profile=does-not-exist").status_code == 404
    assert client.get(PREFIX + "/capabilities?profile=../other-profile").status_code == 400
    env.identity[0] = None
    assert (
        client.get(
            PREFIX + "/capabilities" + query,
            headers={"X-User-ID": "alice", "Authorization": "Bearer alice"},
        ).status_code
        == 401
    )


def test_real_password_cookie_mounted_api_and_encrypted_ack_recovery(
    env, mounted, receiver, monkeypatch
):
    from hermes_cli.dashboard_auth import registry
    from plugins.dashboard_auth.basic import BasicAuthProvider, hash_password

    # Ephemeral test credentials: the real provider signs/verifies cookies, not
    # client headers or a middleware-created principal. No live settings change.
    password = secrets.token_urlsafe(24)
    provider = BasicAuthProvider(
        username="alice", password_hash=hash_password(password), secret=secrets.token_bytes(32)
    )
    monkeypatch.setattr(registry, "_providers", {"basic": provider})
    monkeypatch.setattr(registry, "_scoped_providers", {})
    env.identity[0] = None
    mounted.app.state.auth_required = True
    env.config["principals"][0]["provider"] = "basic"
    env.save()
    client = mounted.client
    assert (
        client.get(
            PREFIX + "/capabilities",
            headers={"X-User-ID": "alice", "Authorization": "Bearer alice"},
        ).status_code
        == 401
    )
    login = client.post(
        "/auth/password-login",
        json={"provider": "basic", "username": "alice", "password": password},
    )
    assert login.status_code == 200
    assert "hermes_session_at" in client.cookies
    assert client.get(PREFIX + "/capabilities?profile=default").json()["enabled"]
    endpoint, received, _ = receiver
    private_api = sys.modules["hermes_dashboard_plugin_mobile-push"]._api
    private_transport = importlib.import_module(private_api.__package__ + ".transport")
    from mobile_push import transport

    monkeypatch.setattr(private_transport, "resolve_addresses", transport.resolve_addresses)
    body = {**env.body, "endpoint": endpoint}
    path = PREFIX + "/registrations/phone?profile=default"
    first = client.put(path, json=body)
    assert first.status_code == 200
    assert env.runtime.deliver_one()
    proof = decrypt(env, received[0])  # Genuine encrypted payload, not DB plaintext.
    assert client.put(path, json=body).status_code == 409
    # Lost ACK recovery rotates already-consented native authority; require a
    # genuinely new TLS-decrypted proof, never re-use a consumed challenge.
    body = {**body, "registration_revision": 2,
            "registration_nonce": "tls_recovered_nonce_0123456789"}
    recovered = client.put(path, json=body)
    assert recovered.status_code == 200
    assert recovered.json()["generation"] == first.json()["generation"] + 1
    assert env.runtime.deliver_one()
    fresh = decrypt(env, received[-1])
    assert fresh["challenge"] != proof["challenge"]
    proof = fresh
    first = recovered
    confirm_path = PREFIX + "/registrations/phone/confirm?profile=default"
    confirmation = {"generation": first.json()["generation"], "challenge": proof["challenge"]}
    assert client.post(confirm_path, json=confirmation).status_code == 200
    assert client.post(confirm_path, json=confirmation).status_code == 409
    assert client.delete(path).status_code == 200
    assert client.post(confirm_path, json=confirmation).status_code == 409
    assert client.put(path, json=body).status_code == 409
    client.cookies.clear()
    assert client.get(PREFIX + "/events").status_code == 401


def test_real_mounted_ack_recovery_after_client_process_death(env, mounted):
    client = mounted.client
    path = PREFIX + "/registrations/phone?profile=other-profile"
    # PUT commits; imagine the process dies before native generation persistence.
    first = client.put(path, json=env.body)
    assert first.status_code == 200
    proof = challenge(mounted.other)
    assert client.put(path, json=env.body).status_code == 409
    recovery_body = {**env.body, "registration_revision": 2,
                     "registration_nonce": "process_recovered_nonce_012345"}
    recovered = client.put(path, json=recovery_body)
    assert recovered.status_code == 200
    assert recovered.json()["generation"] == first.json()["generation"] + 1
    fresh = challenge(mounted.other)
    assert fresh["challenge"] != proof["challenge"]
    confirm = PREFIX + "/registrations/phone/confirm?profile=other-profile"
    assert client.post(confirm, json={"generation": first.json()["generation"],
                                     "challenge": proof["challenge"]}).status_code == 409
    body = {"generation": recovered.json()["generation"], "challenge": fresh["challenge"]}
    # Confirmation commits; process dies before native active persistence.
    assert client.post(confirm, json=body).json()["status"] == "active"
    assert client.put(path, json=recovery_body).status_code == 409
    assert client.post(confirm, json=body).status_code == 409
    recovery_body = {**recovery_body, "registration_revision": 3,
                     "registration_nonce": "confirm_recovered_nonce_012345"}
    third = client.put(path, json=recovery_body)
    assert third.status_code == 200
    fresh = challenge(mounted.other)
    body = {"generation": third.json()["generation"], "challenge": fresh["challenge"]}
    assert client.post(confirm, json=body).json()["status"] == "active"
    assert client.delete(path).status_code == 200
    assert client.post(confirm, json=body).status_code == 409
    assert client.put(path, json=recovery_body).status_code == 409
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM registrations").fetchone()[0] == 0
