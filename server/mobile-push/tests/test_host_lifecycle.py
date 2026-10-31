"""Optional installed-Hermes integration; enable with HERMES_AGENT_SOURCE on PYTHONPATH.

Uses real PluginManager/PluginContext and same physical plugin source for both profiles.
Never discovers plugins or opens the operator's real home.
"""

import importlib.util
import json
import os
import shutil
import sys
import threading
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

SOURCE = os.environ.get("HERMES_AGENT_SOURCE")
pytestmark = pytest.mark.skipif(
    not SOURCE, reason="Set HERMES_AGENT_SOURCE for real host integration"
)
PLUGIN = Path(__file__).resolve().parents[1]


def host(env, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(env.profile.home))
    monkeypatch.syspath_prepend(SOURCE)
    for path in os.environ.get("HERMES_AGENT_SITE_PACKAGES", "").split(os.pathsep):
        if path and path not in sys.path:
            sys.path.append(path)
    from hermes_cli.plugins import PluginManager
    from hermes_cli.plugins_manifest import PluginManifest

    manifest = PluginManifest(name="mobile-push", version="0.1.0", source="user", path=str(PLUGIN))
    return PluginManager, manifest


def other_home(env):
    home = env.profile.home.parent / "other-profile"
    directory = home / "plugin-data" / "mobile-push"
    directory.mkdir(parents=True)
    shutil.copyfile(env.profile.home / "state.db", home / "state.db")
    path = directory / "config.json"
    path.write_text(json.dumps(env.config))
    path.chmod(0o600)
    return home


class InspectSender:
    def __init__(self):
        self.seen = []
        self.sent = threading.Event()

    def send(self, registration, payload, policy):
        from hermes_constants import get_hermes_home

        self.seen.append((Path(get_hermes_home()).resolve(), json.loads(payload)))
        self.sent.set()
        return 201


def test_real_manager_same_source_profiles_unload_and_unchanged_reload(env, monkeypatch):
    Manager, manifest = host(env, monkeypatch)
    first = Manager(scope_key=str(env.profile.home))
    second = Manager(scope_key=str(other_home(env)))
    try:
        first._load_plugin(manifest)
        assert first._plugins["mobile-push"].enabled, first._plugins["mobile-push"].error
        runtime_a = first._hooks["on_session_end"][0].__self__
        sender_a = InspectSender()
        runtime_a.sender = sender_a
        second._load_plugin(manifest)
        assert second._plugins["mobile-push"].enabled, second._plugins["mobile-push"].error
        runtime_b = second._hooks["on_session_end"][0].__self__
        sender_b = InspectSender()
        runtime_b.sender = sender_b
        assert runtime_a is not runtime_b
        assert runtime_a.profile.home != runtime_b.profile.home
        runtime_a.store.put(("fixture", "alice"), "phone", env.body, runtime_a.profile.policy())
        runtime_b.store.put(("fixture", "alice"), "phone", env.body, runtime_b.profile.policy())
        assert sender_a.sent.wait(4) and sender_b.sent.wait(4)
        assert sender_a.seen[0][0] == runtime_a.profile.home
        assert sender_b.seen[0][0] == runtime_b.profile.home
        assert second.unload("mobile-push")
        assert not runtime_b.thread.is_alive()
        assert runtime_a.thread.is_alive()
        # Dispose/re-import unchanged bytes through the real manager's registration ledger.
        assert first.unload("mobile-push")
        assert not runtime_a.thread.is_alive()
        first._load_plugin(manifest)
        assert first._plugins["mobile-push"].enabled
        replacement = first._hooks["on_session_end"][0].__self__
        assert replacement is not runtime_a and replacement.thread.is_alive()
        assert replacement.profile.home == runtime_a.profile.home
    finally:
        first.unload()
        second.unload()
    assert not replacement.thread.is_alive()


def test_real_manager_rolls_back_initialisation_failure(env, monkeypatch):
    Manager, manifest = host(env, monkeypatch)
    # An invalid durable directory fails AFTER ctx.on_unload was registered.
    home = other_home(env)
    (home / "plugin-data" / "mobile-push" / "outbox.sqlite3").mkdir()
    manager = Manager(scope_key=str(home))
    manager._load_plugin(manifest)
    assert not manager._plugins["mobile-push"].enabled
    assert not manager._hooks
    assert not manager._registration_order
    manager.unload()


def test_dashboard_without_host_profile_scope_fails_closed(env, monkeypatch):
    host(env, monkeypatch)
    spec = importlib.util.spec_from_file_location(
        "test_mobile_api_unscoped", PLUGIN / "dashboard" / "plugin_api.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    app = FastAPI()

    @app.middleware("http")
    async def authenticated(request, call_next):
        if env.identity[0] is not None:
            request.state.session = env.identity[0]
        return await call_next(request)

    # Intentionally NOT the host mount: no vetted request home is available.
    app.include_router(module.router)
    with TestClient(app) as client:
        assert client.get("/capabilities").status_code == 503
        assert client.get("/events", params={"profile": "other-profile"}).status_code == 503
        env.identity[0] = None
        assert (
            client.get(
                "/capabilities",
                headers={"X-User-ID": "alice", "Authorization": "Bearer not-trusted"},
            ).status_code
            == 401
        )
