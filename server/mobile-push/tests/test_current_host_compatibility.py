"""Exact-host diagnostics: supported launch flow and fail-closed hosted identity.

These do not replace the older cross-profile positive gates. A green result here
means the limitation is reproduced, not that hosted mobile-push is supported.
"""

import asyncio
import importlib
import json
import sys

import pytest
from conftest import PREFIX
from test_current_host_default import current_host as current_host
from test_current_host_default import login
from test_host_lifecycle import PLUGIN, SOURCE, host
from test_transport import decrypt
from test_transport import receiver as receiver

pytestmark = pytest.mark.skipif(not SOURCE, reason="Set HERMES_AGENT_SOURCE for host contract")


def test_launch_password_cookie_encrypted_ack_recovery(env, current_host, receiver, monkeypatch):
    """Keep real cookie auth, TLS proof decryption and all replay/revoke denials."""
    client = current_host.client
    caps = PREFIX + "/capabilities?profile=default"
    assert client.get(caps).status_code == 401
    assert client.get(caps, headers={"X-User-ID": "alice", "Authorization": "Bearer alice"}).status_code == 401
    login(current_host)
    response = client.get(caps)
    assert response.status_code == 200, response.text
    assert response.json()["enabled"] is True
    endpoint, received, _ = receiver
    private_api = sys.modules["hermes_dashboard_plugin_mobile-push"]._api
    private_transport = importlib.import_module(private_api.__package__ + ".transport")
    from mobile_push import transport

    monkeypatch.setattr(private_transport, "resolve_addresses", transport.resolve_addresses)
    body = {**env.body, "endpoint": endpoint}
    path = PREFIX + "/registrations/phone?profile=default"
    first = client.put(path, json=body)
    assert first.status_code == 200, first.text
    assert env.runtime.deliver_one()
    proof = decrypt(env, received[0])
    assert client.put(path, json=body).status_code == 409
    body = {**body, "registration_revision": 2,
            "registration_nonce": "tls_recovered_nonce_0123456789"}
    recovered = client.put(path, json=body)
    assert recovered.status_code == 200, recovered.text
    assert recovered.json()["generation"] == first.json()["generation"] + 1
    assert env.runtime.deliver_one()
    fresh = decrypt(env, received[-1])
    assert fresh["challenge"] != proof["challenge"]
    confirm = PREFIX + "/registrations/phone/confirm?profile=default"
    assert client.post(confirm, json={"generation": first.json()["generation"],
                                     "challenge": proof["challenge"]}).status_code == 409
    confirmation = {"generation": recovered.json()["generation"], "challenge": fresh["challenge"]}
    assert client.post(confirm, json=confirmation).status_code == 200
    assert client.post(confirm, json=confirmation).status_code == 409
    assert client.delete(path).status_code == 200
    assert client.post(confirm, json=confirmation).status_code == 409
    assert client.put(path, json=body).status_code == 409
    record = env.runtime.store.registration(("basic", "alice"), "phone")
    assert record["status"] == "revoked"
    client.cookies.clear()
    assert client.get(PREFIX + "/events").status_code == 401


def test_plugin_scope_dependency_rejects_non_plugin_probe(env, current_host):
    """The legacy /scope and /probe-home paths cannot identify a plugin."""
    from fastapi import Depends
    from hermes_cli.web_server_dashboard import _plugin_route_secret_scope

    @current_host.client.app.get("/probe-home", dependencies=[Depends(_plugin_route_secret_scope)])
    def probe():
        pytest.fail("A non-plugin probe must not enter its handler")

    login(current_host)
    response = current_host.client.get("/probe-home", params={"profile": "sibling"})
    assert response.status_code == 404
    assert response.json() == {"detail": "Plugin not found"}


def test_real_hosted_asgi_admission_does_not_supply_verified_principal(env, monkeypatch):
    """Execute the actual child ASGI handler, not a guessed IPC response.

    Transport seam: invoke op_asgi in this process without a Channel/subprocess;
    the real child app builder, admission wrapper and ASGI request remain intact.
    Even authenticated=True is insufficient to identify a policy principal.
    """
    host(env, monkeypatch)
    from hermes_cli.plugin_host_child import HostRuntime
    from hermes_cli.plugin_host_wire import decode, encode

    runtime = object.__new__(HostRuntime)
    runtime.asgi_apps = {}
    runtime._run = asyncio.run
    before = env.profile.database.read_bytes()
    calls = [
        ("GET", "/capabilities", None),
        ("PUT", "/registrations/hosted-phone", env.body),
        ("POST", "/registrations/hosted-phone/confirm",
         {"generation": 1, "challenge": "not_an_authorised_proof"}),
        ("DELETE", "/registrations/hosted-phone", None),
        ("GET", "/events", None),
    ]
    for authenticated in (False, True):
        for method, path, body in calls:
            result = decode(runtime.op_asgi({
                "plugin": "mobile-push", "dashboard_dir": str(PLUGIN / "dashboard"),
                "api_file": "plugin_api.py", "method": method, "path": path,
                "query": "provider=fixture&user_id=alice&profile=default",
                "headers": [["X-User-ID", "alice"], ["Authorization", "Bearer alice"],
                            ["Content-Type", "application/json"]],
                "body": encode(json.dumps(body).encode() if body is not None else b""),
                "authenticated": authenticated,
            }))
            assert result["status"] == 401, result
            assert json.loads(result["body"]) == {"detail": "Verified dashboard session required"}
    assert env.profile.database.read_bytes() == before
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM registrations").fetchone()[0] == 0
