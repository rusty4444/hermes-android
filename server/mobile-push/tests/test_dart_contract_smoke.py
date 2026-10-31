"""Opt-in production Dart -> real Python router TCP contract, ephemeral homes only.

Run from repository root after `flutter pub get`:
  MOBILE_PUSH_DART_SMOKE=1 python -m pytest -q -s server/mobile-push/tests/test_dart_contract_smoke.py
Requires Python mobile-push test dependencies plus uvicorn, and Flutter on PATH
(or FLUTTER_BIN). Ordinary pytest skips this test and does not invoke Flutter.

Boundaries: real MobilePushApi/DashboardClient serialization, strict Python models,
SQLite authority, Runtime events, TLS Web Push encryption and independent subscriber
/VAPID verification. Password login/cookie verification is a TEST-OWNED provider,
not installed Hermes auth. The router is fixed to one disposable Profile; query
assertions are NOT proof of the host's profile resolver. Subscriber key provisioning
and passing the decrypted challenge to Dart replace Android connector/MethodChannel.
No real distributor, GMS, notification UI, native persistence or device is tested.
"""

import json
import os
import secrets
import shutil
import socket
import sqlite3
import subprocess
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
from conftest import PREFIX
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from test_transport import decrypt
from test_transport import receiver as receiver

from mobile_push.api import create_router

pytestmark = pytest.mark.skipif(
    os.environ.get("MOBILE_PUSH_DART_SMOKE") != "1", reason="opt-in Dart TCP smoke"
)


def test_consuming_dart_automatic_push(env, receiver, tmp_path):
    import uvicorn

    root = Path(__file__).resolve().parents[3]
    flutter = shutil.which(os.environ.get("FLUTTER_BIN", "flutter"))
    assert flutter, "Install Flutter or set FLUTTER_BIN; opt-in must not silently skip"
    endpoint, received, _ = receiver
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    password, cookie, secret = (secrets.token_urlsafe(24) for _ in range(3))
    identity = ("fixture", "alice")
    records, forced = [], set()
    flags = {"deny": False, "mismatch": None}
    logins = []
    app = FastAPI()

    @app.middleware("http")
    async def fixture_cookie_and_wire_checks(request, call_next):
        if request.url.path.startswith(PREFIX):
            assert dict(request.query_params).get("profile") == "contract-profile"
            operation = request.method + " " + request.url.path
            authenticated = request.cookies.get("hermes_session_at") == cookie
            record = {"operation": operation, "query": dict(request.query_params)}
            if request.method in {"PUT", "POST"}:
                record["body"] = json.loads(await request.body())
            records.append(record)
            if not authenticated or flags["deny"]:
                record["status"] = 401
                return JSONResponse({"detail": "fixture cookie required"}, status_code=401)
            if operation not in forced:
                forced.add(operation)
                record["status"] = 401
                return JSONResponse({"detail": "one fixture expiry per operation"}, status_code=401)
            request.state.session = SimpleNamespace(provider="fixture", user_id="alice")
            response = await call_next(request)
            record["status"] = response.status_code
            if request.url.path.endswith("/events") and response.status_code == 200:
                payload = json.loads(b"".join([chunk async for chunk in response.body_iterator]))
                field = flags.pop("mismatch", None)
                flags["mismatch"] = None
                if field == "missing":
                    payload.pop("installation_id")
                elif field == "string_generation":
                    payload["generation"] = str(payload["generation"])
                elif field:
                    payload[field] = payload[field] + 1 if field == "generation" else "wrong"
                return JSONResponse(payload)
            return response
        return await call_next(request)

    @app.post("/auth/password-login")
    async def login(request: Request):
        body = await request.json()
        assert body == {"provider": "basic", "username": "alice", "password": password}
        logins.append(True)
        response = JSONResponse({"ok": True})
        response.set_cookie("hermes_session_at", cookie, httponly=True, samesite="strict")
        return response

    app.include_router(create_router(env.profile), prefix=PREFIX)

    @app.post("/__smoke/{action}")
    async def control(action: str, request: Request):
        if request.headers.get("x-smoke-secret") != secret:
            raise HTTPException(403)
        args = await request.json()
        if action == "proof":
            previous = len(received)
            assert env.runtime.deliver_one()
            assert len(received) == previous + 1
            # Existing verifier checks aes128gcm, decrypts subscriber ciphertext,
            # verifies actual VAPID signature, audience, contact and expiry.
            proof = decrypt(env, received[-1])
            assert proof["kind"] == "challenge"
            return proof
        if action == "future-events":
            with sqlite3.connect(env.profile.home / "state.db") as db:
                assert not db.execute("SELECT 1 FROM sessions WHERE id='future-session'").fetchone()
                db.execute("INSERT INTO sessions VALUES('future-session', NULL)")
            for index in range(101):
                env.runtime.human_input(
                    kind="approval", session_id="future-session", request_id=f"future-{index}"
                )
            return {"ok": True}
        if action == "mismatch":
            flags["mismatch"] = args["field"]
            return {"ok": True}
        if action in {"deny", "allow"}:
            flags["deny"] = action == "deny"
            return {"ok": True}
        if action == "report":
            with env.runtime.store.connection() as db:
                count = db.execute(
                    "SELECT count(*) FROM events WHERE session_id='future-session'"
                ).fetchone()[0]
            return {
                "revoked": env.runtime.store.registration(identity, "dart-contract-phone")["status"]
                == "revoked",
                "future_event_count": count,
                "forced_401_operations": len(forced),
                "login_count": len(logins),
            }
        raise HTTPException(404)

    # Reserve port until uvicorn owns the same socket; no free-port race.
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(app, log_level="error", lifespan="off"))
    thread = threading.Thread(target=server.run, kwargs={"sockets": [sock]}, daemon=True)
    thread.start()
    try:
        deadline = time.monotonic() + 10
        while not server.started and thread.is_alive() and time.monotonic() < deadline:
            time.sleep(0.02)
        assert server.started, "loopback TCP server failed to start"
        spec = {
            "port": port,
            "password": password,
            "secret": secret,
            "endpoint": endpoint,
            "keys": env.body["keys"],
        }
        child_env = {
            **os.environ,
            "MOBILE_PUSH_SMOKE_SPEC": json.dumps(spec),
            "TMPDIR": str(tmp_path.resolve()),
        }
        result = subprocess.run(
            [
                flutter,
                "test",
                "--no-pub",
                "--reporter",
                "expanded",
                "tools/mobile_push_contract_smoke.dart",
            ],
            cwd=root,
            env=child_env,
            capture_output=True,
            text=True,
            timeout=150,
        )
        print(result.stdout)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "DART_PYTHON_PUSH_CONTRACT_OK" in result.stdout
        puts = [r for r in records if r["operation"].startswith("PUT")]
        assert puts and all(
            r["body"]["session_scope"] == "authorized" and "session_ids" not in r["body"]
            for r in puts
        )
        assert {r["body"]["registration_revision"] for r in puts} == {1, 2}
        pages = [r for r in records if r["operation"].endswith("/events")]
        assert all(
            set(r["query"]) == {"profile", "installation_id", "generation", "after", "limit"}
            for r in pages
        )
        assert all(
            r["query"]["installation_id"] == "dart-contract-phone" and r["query"]["limit"] == "100"
            for r in pages
        )
        assert any(r["query"]["after"] != "0" and r["status"] == 200 for r in pages)
        assert len(forced) == 5
        assert len(logins) == 7  # Initial, five one-shot expiries, one persistent rejection retry.
        assert (
            env.runtime.store.registration(identity, "dart-contract-phone")["status"] == "revoked"
        )
        artifact = tmp_path / "dart_contract_requests.json"
        artifact.write_text(json.dumps(records, indent=2))
        print(f"Actual wire request artifact: {artifact}")
    finally:
        server.should_exit = True
        thread.join(timeout=10)
        sock.close()
        assert not thread.is_alive(), "TCP server leaked after smoke"
