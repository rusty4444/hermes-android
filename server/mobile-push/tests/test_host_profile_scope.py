"""One actual Hermes dashboard mount, many request profiles; no live homes.

The host validates names and stamps a task-local secret-scope home before the
plugin dependency runs. Never replace that seam with separate per-home routers.
"""

import json
import os
import sqlite3
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import pytest
from conftest import PREFIX
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import Depends, FastAPI, HTTPException
from fastapi.testclient import TestClient
from test_host_lifecycle import PLUGIN, SOURCE, host, other_home

from mobile_push.config import Profile
from mobile_push.service import Runtime
from mobile_push.store import Store

pytestmark = pytest.mark.skipif(
    not SOURCE, reason="Set HERMES_AGENT_SOURCE for real host integration"
)
PRINCIPAL = ("fixture", "alice")


def save(profile, config):
    path = profile.directory / "config.json"
    path.write_text(json.dumps(config))
    path.chmod(0o600)


def snapshot(profile):
    if not profile.database.exists():
        return None
    with sqlite3.connect(profile.database) as db:
        return {
            table: db.execute(f"SELECT * FROM {table} ORDER BY rowid").fetchall()
            for table in ("registrations", "events", "outbox", "attention")
        }


@pytest.fixture
def mounted(env, monkeypatch):
    host(env, monkeypatch)
    import hermes_cli.plugin_isolation as isolation
    import hermes_cli.web_server_dashboard as dashboard
    import hermes_cli.web_server_profiles as profiles
    import hermes_constants
    from agent.secret_scope import current_secret_scope_home

    second = Profile(other_home(env))
    config_b = json.loads(json.dumps(env.config))
    # Distinct operator keys prove capabilities and workers use the selected policy.
    key = ec.generate_private_key(ec.SECP256R1())
    key_file = second.directory / "vapid-private.pem"
    key_file.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    key_file.chmod(0o600)
    config_b["vapid_private_key_file"] = str(key_file)
    save(second, config_b)
    homes = {"launch-profile": env.profile.home, "selected-work-profile": second.home}

    def resolve(name):
        if name not in homes:
            raise HTTPException(404, "Unknown test profile")
        return homes[name]

    # Only discovery/name resolution and authentication are fixture-owned. The
    # real mount/dependency/contextvars/threadpool propagation are exercised intact.
    monkeypatch.setattr(profiles, "get_process_hermes_home", lambda: env.profile.home)
    monkeypatch.setattr(profiles, "_resolve_profile_dir", resolve)
    monkeypatch.setattr(isolation, "isolation_mode", lambda: isolation.ISOLATION_IN_PROCESS)
    app = FastAPI()

    @app.middleware("http")
    async def verified_fixture(request, call_next):
        if env.identity[0] is not None:
            request.state.session = env.identity[0]
        return await call_next(request)

    @app.get("/probe-home", dependencies=[Depends(dashboard._plugin_route_secret_scope)])
    def probe_home():
        return {
            "home": str(hermes_constants.get_hermes_home()),
            "vetted": current_secret_scope_home(),
        }

    plugin = {
        "name": "mobile-push",
        "source": "user",
        "_api_file": "plugin_api.py",
        "_dir": str(PLUGIN / "dashboard"),
    }
    token = hermes_constants.set_hermes_home_override(env.profile.home)
    try:
        assert dashboard._mount_one_plugin_api(app, plugin, {"mobile-push"}, set())
    finally:
        hermes_constants.reset_hermes_home_override(token)
    loaded = sys.modules["hermes_dashboard_plugin_mobile-push"]
    assert len(loaded.router.routes) == 5
    monkeypatch.setattr(sys.modules[loaded._name + ".transport"], "resolve_addresses", env.lookup)
    with TestClient(app) as client:
        for name, home in homes.items():
            scoped = client.get("/probe-home", params={"profile": name}).json()
            assert scoped == {"home": str(home), "vetted": str(home)}
        yield SimpleNamespace(
            client=client,
            profiles=(env.profile, second),
            configs=(env.config, config_b),
            names=(None, "selected-work-profile"),
            loaded=loaded,
            environment_home=os.environ["HERMES_HOME"],
        )
    assert os.environ["HERMES_HOME"] == str(env.profile.home)


def request(mounted, index, method, path, **kwargs):
    name = mounted.names[index]
    return mounted.client.request(
        method, PREFIX + path, params={"profile": name} if name else {}, **kwargs
    )


def register(mounted, env, index, installation="phone", **changes):
    response = request(
        mounted, index, "PUT", "/registrations/" + installation, json={**env.body, **changes}
    )
    assert response.status_code == 200, response.text
    store = Store(mounted.profiles[index].database)
    with store.connection() as db:
        row = db.execute(
            "SELECT payload FROM outbox WHERE installation=? AND done=0", (installation,)
        ).fetchone()
    return response.json(), json.loads(row[0])


def activate(mounted, env, index, installation="phone"):
    registration, hint = register(mounted, env, index, installation)
    proof = {"generation": registration["generation"], "challenge": hint["challenge"]}
    response = request(mounted, index, "POST", f"/registrations/{installation}/confirm", json=proof)
    assert response.status_code == 200, response.text
    return proof


@pytest.mark.parametrize("enabled_a", [True, False])
def test_once_mounted_opposite_policies_and_disabled_revocation(env, mounted, enabled_a):
    for index, enabled in enumerate((enabled_a, not enabled_a)):
        mounted.configs[index]["enabled"] = enabled
        save(mounted.profiles[index], mounted.configs[index])
    enabled_index, disabled_index = (0, 1) if enabled_a else (1, 0)
    before = snapshot(mounted.profiles[enabled_index])
    for index in (0, 1):
        caps = request(mounted, index, "GET", "/capabilities")
        assert caps.status_code == 200
        assert caps.json()["enabled"] is mounted.configs[index]["enabled"]
        assert caps.json()["vapid_public_key"] == (
            mounted.profiles[index].policy().public_key() if caps.json()["enabled"] else ""
        )
    assert (
        request(mounted, disabled_index, "PUT", "/registrations/phone", json=env.body).status_code
        == 503
    )
    assert (
        request(
            mounted,
            disabled_index,
            "POST",
            "/registrations/phone/confirm",
            json={"generation": 1, "challenge": "proof_that_is_not_authority"},
        ).status_code
        == 503
    )
    assert request(mounted, disabled_index, "GET", "/events").status_code == 503
    assert snapshot(mounted.profiles[enabled_index]) == before
    # DELETE intentionally remains available when disabled, but only in THAT home.
    assert request(mounted, disabled_index, "DELETE", "/registrations/phone").status_code == 200
    assert snapshot(mounted.profiles[enabled_index]) == before
    assert (
        Store(mounted.profiles[disabled_index].database).registration(PRINCIPAL, "phone")["status"]
        == "revoked"
    )
    activate(mounted, env, enabled_index)
    assert (
        Store(mounted.profiles[enabled_index].database).registration(PRINCIPAL, "phone")["status"]
        == "active"
    )


def test_once_mounted_same_ids_proofs_events_outboxes_and_delete_are_isolated(env, mounted):
    first, hint_a = register(mounted, env, 0)
    second, hint_b = register(mounted, env, 1)
    assert hint_a["challenge"] != hint_b["challenge"]
    snapshots = [snapshot(profile) for profile in mounted.profiles]
    for index, wrong in ((0, hint_b), (1, hint_a)):
        assert (
            request(
                mounted,
                index,
                "POST",
                "/registrations/phone/confirm",
                json={"generation": 1, "challenge": wrong["challenge"]},
            ).status_code
            == 409
        )
    assert [snapshot(profile) for profile in mounted.profiles] == snapshots
    for index, registration, hint in ((0, first, hint_a), (1, second, hint_b)):
        assert (
            request(
                mounted,
                index,
                "POST",
                "/registrations/phone/confirm",
                json={"generation": registration["generation"], "challenge": hint["challenge"]},
            ).status_code
            == 200
        )
        runtime = Runtime(mounted.profiles[index])
        runtime.initialise()
        try:
            runtime.session_end(
                session_id="session-a",
                turn_id=f"profile-{index}-turn",
                completed=True,
                failed=False,
                interrupted=False,
                turn_exit_reason="text_response(stop)",
            )
        finally:
            runtime.stop()
    for index, profile in enumerate(mounted.profiles):
        events = request(mounted, index, "GET", "/events").json()["events"]
        assert [event["turn_id"] for event in events if event["kind"] == "turn_done"] == [
            f"profile-{index}-turn"
        ]
        with Store(profile.database).connection() as db:
            hints = [json.loads(row[0]) for row in db.execute("SELECT payload FROM outbox")]
        assert [hint["kind"] for hint in hints] == ["turn_done"]
    expected_b = snapshot(mounted.profiles[1])
    assert request(mounted, 0, "DELETE", "/registrations/phone").status_code == 200
    assert snapshot(mounted.profiles[1]) == expected_b
    assert (
        Store(mounted.profiles[1].database).registration(PRINCIPAL, "phone")["status"] == "active"
    )
    keys = [
        request(mounted, index, "GET", "/capabilities").json()["vapid_public_key"]
        for index in (0, 1)
    ]
    assert keys[0] != keys[1]


def test_once_mounted_reload_authz_and_readonly_durable_scope(env, mounted):
    a, b = mounted.profiles
    # Both operator grants name it, but only A's read-only session database has it.
    with sqlite3.connect(a.home / "state.db") as db:
        db.execute("INSERT INTO sessions VALUES('only-in-a',NULL)")
    for profile, config in zip(mounted.profiles, mounted.configs):
        config["principals"][0]["session_ids"].append("only-in-a")
        save(profile, config)
    assert (
        request(
            mounted,
            1,
            "PUT",
            "/registrations/phone",
            json={**env.body, "session_ids": ["only-in-a"]},
        ).status_code
        == 403
    )
    assert not b.database.exists()
    assert (
        request(
            mounted,
            0,
            "PUT",
            "/registrations/phone",
            json={**env.body, "session_ids": ["only-in-a"]},
        ).status_code
        == 200
    )
    expected_a = snapshot(a)
    mounted.configs[1]["principals"] = []
    save(b, mounted.configs[1])
    assert not request(mounted, 1, "GET", "/capabilities").json()["enabled"]
    assert request(mounted, 1, "PUT", "/registrations/phone", json=env.body).status_code == 403
    assert request(mounted, 1, "GET", "/events").status_code == 403
    assert request(mounted, 0, "GET", "/capabilities").json()["enabled"]
    assert snapshot(a) == expected_a
    # A verified principal is required even with a valid profile and forged headers.
    env.identity[0] = None
    assert (
        request(
            mounted,
            1,
            "GET",
            "/capabilities",
            headers={"X-User-ID": "alice", "Authorization": "Bearer not-authority"},
        ).status_code
        == 401
    )


@pytest.mark.parametrize("operation", ["capabilities", "register", "confirm", "revoke", "events"])
@pytest.mark.parametrize("held_index", [0, 1])
def test_held_vetted_profile_request_cannot_borrow_concurrent_launch_authority(
    env,
    mounted,
    monkeypatch,
    operation,
    held_index,
):
    concurrent_index = 1 - held_index
    for profile in mounted.profiles:
        Store(profile.database)
    proofs: list[dict | None] = [None, None]
    if operation in {"confirm", "events"}:
        for index in (0, 1):
            if operation == "confirm":
                registration, hint = register(mounted, env, index)
                proofs[index] = {
                    "generation": registration["generation"],
                    "challenge": hint["challenge"],
                }
            else:
                activate(mounted, env, index)
    before_held = snapshot(mounted.profiles[held_index])
    entered, release = threading.Event(), threading.Event()
    original = mounted.loaded._config.Profile.policy

    def held(profile):
        if profile.home == mounted.profiles[held_index].home:
            entered.set()
            assert release.wait(10)
        return original(profile)

    monkeypatch.setattr(mounted.loaded._config.Profile, "policy", held)

    def call(index):
        if operation == "register":
            return request(mounted, index, "PUT", "/registrations/phone", json=env.body)
        if operation == "confirm":
            return request(
                mounted, index, "POST", "/registrations/phone/confirm", json=proofs[index]
            )
        if operation == "revoke":
            return request(mounted, index, "DELETE", "/registrations/phone")
        return request(mounted, index, "GET", "/" + operation)

    with ThreadPoolExecutor(max_workers=1) as executor:
        flight = executor.submit(call, held_index)
        try:
            assert entered.wait(5)
            assert call(concurrent_index).status_code == 200
            expected_other = snapshot(mounted.profiles[concurrent_index])
            assert snapshot(mounted.profiles[held_index]) == before_held
        finally:
            release.set()
        assert flight.result(5).status_code == 200
    assert snapshot(mounted.profiles[concurrent_index]) == expected_other
    assert os.environ["HERMES_HOME"] == mounted.environment_home


def test_host_rejects_unresolved_names_without_any_plugin_effect(env, mounted):
    before = [snapshot(profile) for profile in mounted.profiles]
    for name in ("unknown-profile", "../../outside"):
        response = mounted.client.put(
            PREFIX + "/registrations/phone", params={"profile": name}, json=env.body
        )
        assert response.status_code == 404
    assert [snapshot(profile) for profile in mounted.profiles] == before


class ScopedSender:
    def __init__(self):
        self.condition = threading.Condition()
        self.sent = []

    def send(self, registration, payload, policy):
        from hermes_constants import get_hermes_home

        with self.condition:
            self.sent.append((get_hermes_home().resolve(), policy.vapid_key, json.loads(payload)))
            self.condition.notify_all()
        return 201

    def wait_for(self, kind):
        with self.condition:
            assert self.condition.wait_for(
                lambda: any(item[2]["kind"] == kind for item in self.sent),
                timeout=5,
            )
            return next(item for item in self.sent if item[2]["kind"] == kind)


def test_real_lifecycle_workers_share_only_their_vetted_dashboard_store(env, mounted, monkeypatch):
    Manager, manifest = host(env, monkeypatch)
    managers = [Manager(scope_key=str(profile.home)) for profile in mounted.profiles]
    runtimes = []
    senders = [ScopedSender(), ScopedSender()]
    try:
        for index, manager in enumerate(managers):
            manager._load_plugin(manifest)
            assert manager._plugins["mobile-push"].enabled, manager._plugins["mobile-push"].error
            runtime = manager._hooks["on_session_end"][0].__self__
            runtimes.append(runtime)
            runtime.sender = senders[index]
            assert runtime.profile.home == mounted.profiles[index].home
            registered = request(mounted, index, "PUT", "/registrations/phone", json=env.body)
            assert registered.status_code == 200
            home, key, proof = senders[index].wait_for("challenge")
            assert home == runtime.profile.home
            assert key == mounted.profiles[index].policy().vapid_key
            assert (
                request(
                    mounted,
                    index,
                    "POST",
                    "/registrations/phone/confirm",
                    json={
                        "generation": registered.json()["generation"],
                        "challenge": proof["challenge"],
                    },
                ).status_code
                == 200
            )
        for index, manager in enumerate(managers):
            manager.invoke_hook(
                "on_session_end",
                session_id="session-a",
                turn_id=f"manager-{index}-turn",
                completed=True,
                failed=False,
                interrupted=False,
                turn_exit_reason="text_response(stop)",
            )
            home, key, hint = senders[index].wait_for("turn_done")
            assert home == mounted.profiles[index].home
            assert key == mounted.profiles[index].policy().vapid_key
            assert hint["generation"] == 1
            feed = request(mounted, index, "GET", "/events").json()["events"]
            assert [event["turn_id"] for event in feed if event["kind"] == "turn_done"] == [
                f"manager-{index}-turn"
            ]
        assert managers[1].unload("mobile-push")
        assert not runtimes[1].thread.is_alive()
        assert runtimes[0].thread.is_alive()
    finally:
        for manager in managers:
            manager.unload()
    assert all(not runtime.thread.is_alive() for runtime in runtimes)


@pytest.mark.parametrize("held_index", [0, 1])
def test_once_mounted_authorized_bound_feed_isolates_profiles_during_sibling_renewal(
    env, mounted, monkeypatch, held_index
):
    body = {key: value for key, value in env.body.items() if key != "session_ids"}
    body["session_scope"] = "authorized"
    proofs = []
    for index, profile in enumerate(mounted.profiles):
        with sqlite3.connect(profile.home / "state.db") as db:
            db.execute("DELETE FROM sessions")
        grant = mounted.configs[index]["principals"][0]
        grant["session_ids"] = []
        grant["owner_all_sessions"] = index == 0
        save(profile, mounted.configs[index])
        assert request(mounted, index, "PUT", "/registrations/phone", json=body).status_code == 200
        with Store(profile.database).connection() as db:
            hint = json.loads(db.execute("SELECT payload FROM outbox").fetchone()[0])
        proofs.append({"generation": 1, "challenge": hint["challenge"]})
    for index, profile in enumerate(mounted.profiles):
        assert (
            request(
                mounted, index, "POST", "/registrations/phone/confirm", json=proofs[1 - index]
            ).status_code
            == 409
        )
        assert (
            request(
                mounted, index, "POST", "/registrations/phone/confirm", json=proofs[index]
            ).status_code
            == 200
        )
        with sqlite3.connect(profile.home / "state.db") as db:
            db.execute("INSERT INTO sessions VALUES('new-durable',NULL)")
        if index == 1:
            mounted.configs[index]["principals"][0]["session_ids"] = ["new-durable"]
            save(profile, mounted.configs[index])
        runtime = Runtime(profile)
        runtime.initialise()
        try:
            runtime.session_end(
                session_id="new-durable",
                turn_id=f"profile-{index}",
                completed=True,
                failed=False,
                interrupted=False,
                turn_exit_reason="stop",
            )
        finally:
            runtime.stop()

    def feed(index, generation=1):
        params = {"installation_id": "phone", "generation": generation, "after": 0, "limit": 100}
        if mounted.names[index]:
            params["profile"] = mounted.names[index]
        return mounted.client.get(PREFIX + "/events", params=params)

    entered, release = threading.Event(), threading.Event()
    original = mounted.loaded._config.Profile.policy

    def held(profile):
        if profile.home == mounted.profiles[held_index].home:
            entered.set()
            assert release.wait(10)
        return original(profile)

    monkeypatch.setattr(mounted.loaded._config.Profile, "policy", held)
    held_before = snapshot(mounted.profiles[held_index])
    sibling = 1 - held_index
    with ThreadPoolExecutor(max_workers=1) as executor:
        flight = executor.submit(feed, held_index)
        try:
            assert entered.wait(5)
            assert [event["turn_id"] for event in feed(sibling).json()["events"]] == [
                f"profile-{sibling}"
            ]
            renewal = {
                **body,
                "registration_revision": 2,
                "registration_nonce": "sibling_renewal_nonce_0123456789",
            }
            assert (
                request(mounted, sibling, "PUT", "/registrations/phone", json=renewal).status_code
                == 200
            )
            assert feed(sibling).status_code == 409
            sibling_after = snapshot(mounted.profiles[sibling])
        finally:
            release.set()
        response = flight.result(5)
        assert response.status_code == 200
        page = response.json()
        assert page["installation_id"] == "phone" and page["generation"] == 1
        assert page["session_scope"] == "authorized"
        assert [event["turn_id"] for event in page["events"]] == [f"profile-{held_index}"]
    assert snapshot(mounted.profiles[held_index]) == held_before
    assert snapshot(mounted.profiles[sibling]) == sibling_after
    grant = mounted.configs[held_index]["principals"][0]
    grant["session_ids"] = []
    grant["owner_all_sessions"] = False
    save(mounted.profiles[held_index], mounted.configs[held_index])
    assert feed(held_index).json()["events"] == []
