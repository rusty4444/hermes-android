"""Optional real-host launch-profile contract, not a cross-profile router bypass.

Run with HERMES_AGENT_SOURCE (and, if needed, HERMES_AGENT_SITE_PACKAGES).
Only disposable homes and generated credentials are used. Current Hermes refuses
secondary user plugins in the launch process; older host probes predate that gate.
"""

import importlib
import json
import os
import secrets
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from conftest import PREFIX
from fastapi import FastAPI
from fastapi.testclient import TestClient

SOURCE = os.environ.get("HERMES_AGENT_SOURCE")
PLUGIN = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.skipif(not SOURCE, reason="Set HERMES_AGENT_SOURCE for host contract")


@pytest.fixture
def current_host(env, monkeypatch):
    # Set the disposable launch home BEFORE importing any host code. In a suite
    # other fixtures can already have imported modules with their own home seams.
    monkeypatch.setenv("HERMES_HOME", str(env.profile.home))
    monkeypatch.setenv("HERMES_DISABLE_LAZY_INSTALLS", "1")
    monkeypatch.setenv("HERMES_ENABLE_PROJECT_PLUGINS", "0")
    monkeypatch.syspath_prepend(SOURCE)
    for path in os.environ.get("HERMES_AGENT_SITE_PACKAGES", "").split(os.pathsep):
        if path and path not in sys.path:
            sys.path.append(path)

    from hermes_cli import profiles, web_server_profiles
    from hermes_cli import web_server_dashboard as loader
    from hermes_cli.dashboard_auth import registry
    from hermes_cli.dashboard_auth.middleware import gated_auth_middleware
    from hermes_cli.dashboard_auth.routes import router as auth_router
    from hermes_constants import reset_hermes_home_override, set_hermes_home_override
    from plugins.dashboard_auth.basic import BasicAuthProvider, hash_password

    monkeypatch.setattr(profiles, "_get_default_hermes_home", lambda: env.profile.home)
    monkeypatch.setattr(profiles, "_get_profiles_root", lambda: env.profile.home / "profiles")
    for module in (loader, web_server_profiles):
        monkeypatch.setattr(module, "get_process_hermes_home", lambda: env.profile.home)
    try:
        plugin_profiles = importlib.import_module("hermes_cli.web_server_plugin_profiles")
    except ModuleNotFoundError as error:
        if error.name != "hermes_cli.web_server_plugin_profiles":
            raise
        plugin_profiles = None
    if plugin_profiles is not None:
        # This is another separately imported launch-home reference, NOT a mock
        # of in_process_router_refused. Keep the host's real security decision.
        monkeypatch.setattr(plugin_profiles, "get_process_hermes_home", lambda: env.profile.home)
        monkeypatch.setattr(plugin_profiles, "_profile_plugins", {})
        monkeypatch.setattr(plugin_profiles, "_profile_rescans", {})
        monkeypatch.setattr(plugin_profiles, "_unknown_plugins", {})

    # Actual manifest discovery and actual config enable/disable parsing. A
    # symlink exposes the same source bytes as an installed user plugin.
    plugins = env.profile.home / "plugins"
    plugins.mkdir()
    (plugins / "mobile-push").symlink_to(PLUGIN, target_is_directory=True)
    (env.profile.home / "config.yaml").write_text(
        json.dumps(
            {"plugins": {"enabled": ["mobile-push"], "disabled": [], "isolation": "in_process"}}
        )
    )
    sibling = env.profile.home / "profiles" / "sibling"
    sibling.mkdir(parents=True)
    (sibling / "config.yaml").write_text(
        json.dumps(
            {"plugins": {"enabled": ["mobile-push"], "disabled": [], "isolation": "in_process"}}
        )
    )
    sentinel = sibling / "sentinel.txt"
    sentinel.write_text("must not change")
    # Hermes may seed SOUL.md and a known-good config backup on the first
    # profile read. Finish that host-owned bootstrap before comparing stores.
    from hermes_cli.config import load_config_readonly

    with web_server_profiles._config_profile_scope("sibling"):
        load_config_readonly()

    password = secrets.token_urlsafe(24)
    provider = BasicAuthProvider(
        username="alice", password_hash=hash_password(password), secret=secrets.token_bytes(32)
    )
    monkeypatch.setattr(registry, "_providers", {"basic": provider})
    monkeypatch.setattr(registry, "_scoped_providers", {})
    env.config["principals"][0]["provider"] = "basic"
    env.save()
    app = FastAPI()
    app.state.auth_required = True
    app.include_router(auth_router)
    app.middleware("http")(gated_auth_middleware)
    # No fixture middleware stamps a principal: only BasicAuthProvider can do so.
    token = set_hermes_home_override(str(env.profile.home))
    try:
        discovered = loader._discover_dashboard_plugins()
        plugin = next(item for item in discovered if item["name"] == "mobile-push")
        assert plugin["source"] == "user"
        from hermes_cli.plugins_cmd import _get_disabled_set, _get_enabled_set

        enabled, disabled = _get_enabled_set(), _get_disabled_set()
        assert "mobile-push" in enabled and "mobile-push" not in disabled
        assert not loader._mount_one_plugin_api(FastAPI(), plugin, set(), disabled)
        assert not loader._mount_one_plugin_api(FastAPI(), plugin, enabled, {"mobile-push"})
        assert loader._mount_one_plugin_api(app, plugin, enabled, disabled)
        private_api = sys.modules["hermes_dashboard_plugin_mobile-push"]._api
        transport = importlib.import_module(private_api.__package__ + ".transport")
        monkeypatch.setattr(transport, "resolve_addresses", env.lookup)
        with TestClient(app) as client:
            yield SimpleNamespace(
                client=client,
                password=password,
                sibling=sibling,
                secondary_gate=plugin_profiles is not None,
            )
    finally:
        reset_hermes_home_override(token)


def login(host):
    response = host.client.post(
        "/auth/password-login",
        json={"provider": "basic", "username": "alice", "password": host.password},
    )
    assert response.status_code == 200, response.text
    assert "hermes_session_at" in host.client.cookies


def snapshot(directory):
    return {
        str(path.relative_to(directory)): path.read_bytes()
        for path in directory.rglob("*")
        if path.is_file()
    }


def test_real_default_mount_password_cookie_and_registration(env, current_host):
    client = current_host.client
    caps = PREFIX + "/capabilities"
    sibling_before = snapshot(current_host.sibling)
    assert client.get(caps).status_code == 401
    assert (
        client.get(
            caps,
            headers={
                "X-User-ID": "alice",
                "Authorization": "Bearer alice",
            },
        ).status_code
        == 401
    )
    login(current_host)
    for profile in ("current", "default"):
        response = client.get(caps, params={"profile": profile})
        assert response.status_code == 200, response.text
        payload = response.json()
        assert payload["enabled"] is True
        assert payload["registration_fence"] == 1
        assert "authorized" in payload["session_scope_modes"]
        assert payload["vapid_public_key"]

    body = {**env.body, "session_scope": "authorized"}
    body.pop("session_ids")
    path = PREFIX + "/registrations/current-host-phone?profile=default"
    response = client.put(path, json=body)
    assert response.status_code == 200, response.text
    # Read the committed result from the launch home's real SQLite store, not
    # a synthetic HTTP response. This test does not claim phone/TLS delivery.
    record = env.runtime.store.registration(("basic", "alice"), "current-host-phone")
    assert record is not None
    assert record["generation"] == response.json()["generation"]
    assert record["status"] == "pending"
    assert client.put(path, json=body).status_code == 409
    assert client.delete(path).status_code == 200
    assert (
        env.runtime.store.registration(("basic", "alice"), "current-host-phone")["status"]
        == "revoked"
    )
    assert snapshot(current_host.sibling) == sibling_before
    assert not (current_host.sibling / "plugin-data").exists()
    client.cookies.clear()
    assert client.get(caps).status_code == 401


def test_secondary_user_router_is_rejected_without_sibling_writes(env, current_host):
    if not current_host.secondary_gate:
        pytest.skip("Older Hermes has no secondary user-plugin in-process refusal gate")
    login(current_host)
    before = snapshot(current_host.sibling)
    for method, suffix, body in (
        ("GET", "/capabilities", None),
        ("PUT", "/registrations/wrong-profile", env.body),
    ):
        response = current_host.client.request(
            method,
            PREFIX + suffix,
            params={"profile": "sibling"},
            json=body,
        )
        assert response.status_code == 404, response.text
    assert (
        current_host.client.get(
            PREFIX + "/capabilities",
            params={"profile": "does-not-exist"},
        ).status_code
        == 404
    )
    assert (
        current_host.client.get(
            PREFIX + "/capabilities",
            params={"profile": "../sibling"},
        ).status_code
        == 400
    )
    assert snapshot(current_host.sibling) == before
    assert not (current_host.sibling / "plugin-data").exists()
    with env.runtime.store.connection() as db:
        assert (
            db.execute(
                "SELECT count(*) FROM registrations WHERE installation=?", ("wrong-profile",)
            ).fetchone()[0]
            == 0
        )
