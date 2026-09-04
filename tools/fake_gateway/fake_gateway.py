#!/usr/bin/env python3
"""Deterministic local Hermes REST, Dashboard, and WebSocket fixture."""

from __future__ import annotations

import argparse
import asyncio
import base64
import binascii
import hashlib
import json
import threading
import time
from datetime import datetime, timezone
from ipaddress import ip_address
from pathlib import Path
from urllib.parse import unquote

from aiohttp import WSMsgType, web

try:
    from .turn_recovery_contract import TurnRecoveryContractLedger
except ImportError:
    from turn_recovery_contract import TurnRecoveryContractLedger


FIXTURE_SESSION_ID = "fixture-copy"
DASHBOARD_TOKEN = "fixture-dashboard-token"
DASHBOARD_COOKIE = "fixture-dashboard-cookie"
MAX_ATTACHMENT_BYTES = 16 * 1024 * 1024
DISCONNECT_BEFORE_ACK = "before_ack"
DISCONNECT_AFTER_ACK = "after_ack_before_first_delta"
DISCONNECT_MID_STREAM = "mid_stream_after_2_deltas"
DISCONNECT_SCENARIOS = (
    DISCONNECT_BEFORE_ACK,
    DISCONNECT_AFTER_ACK,
    DISCONNECT_MID_STREAM,
)
MID_STREAM_DISCONNECT_DELTA_COUNT = 2
SESSIONS = [
    {
        "id": FIXTURE_SESSION_ID,
        "title": "UI verification",
        "model": "hermes-agent",
        "source": "emulator-fixture",
        "message_count": 2,
        "preview": "Markdown, copy and attachment controls",
        "started_at": 1785146400.0,
        "ended_at": None,
    }
]
MESSAGES = {
    FIXTURE_SESSION_ID: [
        {
            "role": "user",
            "content": "Show a deterministic message for the Android UI test.",
        },
        {
            "role": "assistant",
            "content": (
                "Text selectabil pentru verificarea funcției Copy.\n\n"
                "```python\nprint(\"Hermes copy test\")\n```\n\n"
                "- Markdown este randat.\n"
                "- Mesajul poate fi copiat."
            ),
        },
    ]
}


class GatewayState:
    def __init__(
        self,
        api_key: str,
        log_path: Path | None,
        turn_recovery_ledger_path: Path | None = None,
    ) -> None:
        self.api_key = api_key
        self.log_path = log_path
        self.log_lock = threading.Lock()
        self.deleted_session_ids: set[str] = set()
        self.messages = json.loads(json.dumps(MESSAGES))
        self.ws_tickets: set[str] = set()
        self.ticket_counter = 0
        self.prompt_counter = 0
        self.default_model = {
            "provider": "fixture",
            "model": "hermes-agent",
        }
        self.session_models: dict[str, dict[str, str]] = {}
        self.session_reasoning: dict[str, str] = {}
        self.attachments: dict[str, list[dict[str, object]]] = {}
        self.disconnect_ledger = self._new_disconnect_ledger()
        self.turn_recovery = TurnRecoveryContractLedger(
            turn_recovery_ledger_path
        )

    @staticmethod
    def _new_disconnect_ledger() -> dict[str, dict[str, object]]:
        return {
            scenario: {
                "prompt_submit_count": 0,
                "disconnect_point": scenario,
                "ack_seen": False,
                "delta_count": 0,
                "turn_end_count": 0,
                "resubmit_count": 0,
            }
            for scenario in DISCONNECT_SCENARIOS
        }

    def reset_disconnect_ledger(self) -> None:
        self.disconnect_ledger = self._new_disconnect_ledger()

    def disconnect_ledger_snapshot(self) -> dict[str, object]:
        return {
            "schema": "hermes.fake_gateway.disconnect_ledger.v1",
            "scenarios": json.loads(json.dumps(self.disconnect_ledger)),
        }

    def begin_disconnect_scenario(self, scenario: str) -> None:
        record = self.disconnect_ledger[scenario]
        record["prompt_submit_count"] = int(record["prompt_submit_count"]) + 1
        record["resubmit_count"] = max(
            0,
            int(record["prompt_submit_count"]) - 1,
        )

    def mark_disconnect_ack(self, scenario: str) -> None:
        self.disconnect_ledger[scenario]["ack_seen"] = True

    def mark_disconnect_delta(self, scenario: str) -> None:
        record = self.disconnect_ledger[scenario]
        record["delta_count"] = int(record["delta_count"]) + 1

    def log(self, event: dict[str, object]) -> None:
        if self.log_path is None:
            return
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            **event,
        }
        with self.log_lock:
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            with self.log_path.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + "\n")

    def mint_ticket(self) -> str:
        self.ticket_counter += 1
        ticket = f"fixture-ticket-{self.ticket_counter}"
        self.ws_tickets.add(ticket)
        return ticket

    def consume_ticket(self, ticket: str) -> bool:
        if ticket not in self.ws_tickets:
            return False
        self.ws_tickets.remove(ticket)
        return True

    def next_prompt_id(self, kind: str) -> str:
        self.prompt_counter += 1
        return f"{kind}-{self.prompt_counter}"


def state_from(request: web.Request) -> GatewayState:
    return request.app["state"]


def bearer_authorized(request: web.Request) -> bool:
    state = state_from(request)
    return request.headers.get("Authorization", "") == f"Bearer {state.api_key}"


def dashboard_authorized(request: web.Request) -> bool:
    if request.headers.get("X-Hermes-Session-Token") == DASHBOARD_TOKEN:
        return True
    return request.cookies.get("hermes_session_at") == DASHBOARD_COOKIE


def request_is_loopback(request: web.Request) -> bool:
    try:
        return ip_address(request.remote or "").is_loopback
    except ValueError:
        return False


def unauthorized(state: GatewayState, request: web.Request) -> web.Response:
    state.log(
        {
            "transport": "http",
            "method": request.method,
            "path": request.path,
            "authorized": False,
        }
    )
    return web.json_response({"error": "unauthorized"}, status=401)


async def health(request: web.Request) -> web.Response:
    state = state_from(request)
    state.log(
        {
            "transport": "http",
            "method": "GET",
            "path": "/health",
            "authorized": None,
        }
    )
    return web.json_response(
        {
            "status": "ok",
            "service": "hermes-android-fixture",
            "environment": "local-emulator-only",
            "contracts": [
                "mobile-rest",
                "dashboard",
                "json-rpc-websocket",
                "fail-closed-disconnect-fixtures",
                "turn-recovery-v2-fixture",
            ],
        }
    )


async def disconnect_ledger(request: web.Request) -> web.Response:
    if not request_is_loopback(request):
        return web.json_response({"error": "local-only fixture endpoint"}, status=403)
    return web.json_response(state_from(request).disconnect_ledger_snapshot())


async def reset_disconnect_ledger(request: web.Request) -> web.Response:
    if not request_is_loopback(request):
        return web.json_response({"error": "local-only fixture endpoint"}, status=403)
    state = state_from(request)
    state.reset_disconnect_ledger()
    return web.json_response(state.disconnect_ledger_snapshot())


async def dashboard_home(request: web.Request) -> web.Response:
    state_from(request).log(
        {
            "transport": "http",
            "method": "GET",
            "path": "/",
            "authorized": None,
        }
    )
    return web.Response(
        text=(
            "<!doctype html><html><body><script>"
            f'window.__HERMES_SESSION_TOKEN__="{DASHBOARD_TOKEN}";'
            "</script>Hermes Android fixture</body></html>"
        ),
        content_type="text/html",
    )


async def password_login(request: web.Request) -> web.Response:
    state = state_from(request)
    try:
        payload = await request.json()
    except (json.JSONDecodeError, web.HTTPBadRequest):
        payload = {}
    valid = (
        payload.get("provider") == "basic"
        and payload.get("username") == "fixture"
        and payload.get("password") == "fixture"
    )
    state.log(
        {
            "transport": "http",
            "method": "POST",
            "path": "/auth/password-login",
            "authorized": valid,
            "username": payload.get("username"),
        }
    )
    if not valid:
        return web.json_response({"error": "invalid credentials"}, status=401)
    response = web.json_response({"ok": True})
    response.set_cookie(
        "hermes_session_at",
        DASHBOARD_COOKIE,
        httponly=True,
        samesite="Lax",
    )
    return response


async def ws_ticket(request: web.Request) -> web.Response:
    state = state_from(request)
    if not dashboard_authorized(request):
        return unauthorized(state, request)
    ticket = state.mint_ticket()
    state.log(
        {
            "transport": "http",
            "method": "POST",
            "path": "/api/auth/ws-ticket",
            "authorized": True,
            "ticket": ticket,
        }
    )
    return web.json_response({"ticket": ticket})


async def model_info(request: web.Request) -> web.Response:
    state = state_from(request)
    if not dashboard_authorized(request):
        return unauthorized(state, request)
    state.log(
        {
            "transport": "http",
            "method": "GET",
            "path": "/api/model/info",
            "authorized": True,
        }
    )
    return web.json_response(dict(state.default_model))


async def model_options(request: web.Request) -> web.Response:
    state = state_from(request)
    if not dashboard_authorized(request):
        return unauthorized(state, request)
    state.log(
        {
            "transport": "http",
            "method": "GET",
            "path": "/api/model/options",
            "authorized": True,
        }
    )
    return web.json_response(
        {
            "providers": [
                {
                    "slug": "fixture",
                    "name": "Local fixture",
                    "models": [
                        {"id": "hermes-agent", "name": "Hermes Agent"},
                        {"id": "fixture-model", "name": "Fixture Model"},
                    ],
                }
            ]
        }
    )


async def set_default_model(request: web.Request) -> web.Response:
    state = state_from(request)
    if not dashboard_authorized(request):
        return unauthorized(state, request)
    payload = await request.json()
    scope = str(payload.get("scope") or "")
    provider = str(payload.get("provider") or "")
    model = str(payload.get("model") or "")
    accepted = scope == "main" and provider == "fixture" and model in {
        "hermes-agent",
        "fixture-model",
    }
    state.log(
        {
            "transport": "http",
            "method": "POST",
            "path": "/api/model/set",
            "authorized": True,
            "scope": scope,
            "provider": provider,
            "model": model,
            "accepted": accepted,
        }
    )
    if not accepted:
        return web.json_response({"error": "invalid profile model"}, status=400)
    state.default_model = {"provider": provider, "model": model}
    return web.json_response(
        {
            "ok": True,
            "scope": "profile",
            "provider": provider,
            "model": model,
        }
    )


async def list_sessions(request: web.Request) -> web.Response:
    state = state_from(request)
    if not bearer_authorized(request):
        return unauthorized(state, request)
    state.log(
        {
            "transport": "http",
            "method": "GET",
            "path": "/api/sessions",
            "authorized": True,
        }
    )
    sessions = []
    for item in SESSIONS:
        if item["id"] in state.deleted_session_ids:
            continue
        session = dict(item)
        session["message_count"] = len(state.messages.get(item["id"], []))
        sessions.append(session)
    return web.json_response({"data": sessions})


async def session_messages(request: web.Request) -> web.Response:
    state = state_from(request)
    if not bearer_authorized(request):
        return unauthorized(state, request)
    session_id = unquote(request.match_info["session_id"])
    path = f"/api/sessions/{session_id}/messages"
    state.log(
        {
            "transport": "http",
            "method": "GET",
            "path": path,
            "authorized": True,
        }
    )
    if (
        session_id in state.deleted_session_ids
        or session_id not in state.messages
    ):
        return web.json_response({"error": "not found"}, status=404)
    return web.json_response({"data": state.messages[session_id]})


async def delete_session(request: web.Request) -> web.Response:
    state = state_from(request)
    if not bearer_authorized(request):
        return unauthorized(state, request)
    session_id = unquote(request.match_info["session_id"])
    state.deleted_session_ids.add(session_id)
    state.log(
        {
            "transport": "http",
            "method": "DELETE",
            "path": f"/api/sessions/{session_id}",
            "authorized": True,
            "session_id": session_id,
        }
    )
    return web.json_response({"deleted": True})


async def models(request: web.Request) -> web.Response:
    state = state_from(request)
    if not bearer_authorized(request):
        return unauthorized(state, request)
    state.log(
        {
            "transport": "http",
            "method": "GET",
            "path": "/v1/models",
            "authorized": True,
        }
    )
    return web.json_response(
        {
            "object": "list",
            "data": [
                {"id": "hermes-agent", "object": "model"},
                {"id": "fixture-model", "object": "model"},
            ],
        }
    )


def last_user_text(messages: object) -> str:
    if not isinstance(messages, list):
        return ""
    for item in reversed(messages):
        if not isinstance(item, dict) or item.get("role") != "user":
            continue
        content = item.get("content", "")
        return content if isinstance(content, str) else ""
    return ""


async def chat_completions(request: web.Request) -> web.StreamResponse:
    state = state_from(request)
    if not bearer_authorized(request):
        return unauthorized(state, request)
    payload = await request.json()
    text = last_user_text(payload.get("messages"))
    session_id = request.headers.get("X-Hermes-Session-Id")
    state.log(
        {
            "transport": "http",
            "method": "POST",
            "path": "/v1/chat/completions",
            "authorized": True,
            "session_id": session_id,
            "model": payload.get("model"),
            "stream": payload.get("stream"),
            "last_user_text": text,
        }
    )

    slow_response = "slow stop test" in text.lower()
    response_text = (
        "Acesta este un răspuns intenționat lent pentru verificarea butonului "
        "Stop din aplicația Android. Fluxul nu trebuie să ajungă la final."
        if slow_response
        else "Răspuns streaming primit corect de emulator."
    )

    response = web.StreamResponse(
        status=200,
        headers={
            "Content-Type": "text/event-stream; charset=utf-8",
            "Cache-Control": "no-cache",
        },
    )
    await response.prepare(request)
    try:
        tokens = [token + " " for token in response_text.split(" ")]
        for token in tokens:
            frame = {
                "id": "fixture-completion",
                "object": "chat.completion.chunk",
                "choices": [{"index": 0, "delta": {"content": token}}],
            }
            await response.write(
                ("data: " + json.dumps(frame, ensure_ascii=False) + "\n\n").encode(
                    "utf-8"
                )
            )
            await asyncio.sleep(10.0 if slow_response else 0.08)
        await response.write(b"data: [DONE]\n\n")
        await response.write_eof()
    except (ConnectionResetError, ConnectionAbortedError, asyncio.CancelledError):
        state.log(
            {
                "transport": "http",
                "method": "POST",
                "path": "/v1/chat/completions",
                "session_id": session_id,
                "stream_cancelled": True,
            }
        )
        return response

    if session_id:
        history = state.messages.setdefault(session_id, [])
        history.extend(
            [
                {"role": "user", "content": text},
                {"role": "assistant", "content": response_text},
            ]
        )
    return response


def rpc_result(request_id: object, result: dict[str, object]) -> str:
    return json.dumps(
        {"jsonrpc": "2.0", "id": request_id, "result": result},
        ensure_ascii=False,
    )


def rpc_error(request_id: object, message: str, code: int = -32602) -> str:
    return json.dumps(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": code, "message": message},
        },
        ensure_ascii=False,
    )


def gateway_event(event_type: str, session_id: str, payload: dict) -> str:
    return json.dumps(
        {
            "jsonrpc": "2.0",
            "method": "event",
            "params": {
                "type": event_type,
                "sid": session_id,
                "payload": payload,
            },
        },
        ensure_ascii=False,
    )


def decode_data_url(data_url: str) -> bytes:
    header, separator, encoded = data_url.partition(",")
    if not separator or not header.startswith("data:") or ";base64" not in header:
        raise ValueError("Expected a Base64 data URL")
    try:
        return base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("Invalid Base64 attachment") from error


async def handle_rpc(
    ws: web.WebSocketResponse,
    state: GatewayState,
    payload: dict,
    active_prompts: dict[str, asyncio.Task],
    pending_approvals: dict[str, asyncio.Future[str]],
    pending_sensitive_prompts: dict[
        str, tuple[str, str, asyncio.Future[str]]
    ],
    pending_clarifications: dict[str, tuple[str, asyncio.Future[str]]],
    pending_batch_clarifications: dict[
        str, tuple[str, list[str], dict[str, str], asyncio.Future[str]]
    ],
) -> None:
    request_id = payload.get("id")
    method = payload.get("method")
    params = payload.get("params")
    if not isinstance(params, dict):
        params = {}

    session_id = str(params.get("session_id") or FIXTURE_SESSION_ID)
    log_record: dict[str, object] = {
        "transport": "websocket",
        "method": method,
        "session_id": session_id,
    }

    if method == "session.create":
        state.messages.setdefault(session_id, [])
        state.log(log_record)
        await ws.send_str(rpc_result(request_id, {"session_id": session_id}))
        return

    if method == "session.resume":
        if session_id not in state.messages:
            state.log({**log_record, "found": False})
            await ws.send_str(rpc_error(request_id, "session not found", 4007))
            return
        state.log({**log_record, "found": True})
        await ws.send_str(rpc_result(request_id, {"session_id": session_id}))
        return

    if method == "session.title":
        title = str(params.get("title") or "").strip()
        if session_id not in state.messages or not title:
            await ws.send_str(rpc_error(request_id, "Invalid session title"))
            return
        state.log({**log_record, "title": title})
        await ws.send_str(rpc_result(request_id, {"ok": True, "title": title}))
        return

    if method == "session.branch":
        name = str(params.get("name") or "").strip()
        if session_id not in state.messages or not name:
            await ws.send_str(rpc_error(request_id, "Invalid session branch"))
            return
        branch_id = f"{session_id}-branch"
        state.messages[branch_id] = list(state.messages[session_id])
        state.log({**log_record, "name": name, "branch_id": branch_id})
        await ws.send_str(
            rpc_result(
                request_id,
                {"session_id": branch_id, "title": name, "parent": session_id},
            )
        )
        return

    if method == "config.get":
        key = str(params.get("key") or "")
        if key != "reasoning":
            await ws.send_str(rpc_error(request_id, "Unsupported fixture config key"))
            return
        effort = state.session_reasoning.get(session_id, "medium")
        state.log({**log_record, "key": key, "value": effort})
        await ws.send_str(rpc_result(request_id, {"key": key, "value": effort}))
        return

    if method == "config.set":
        value = str(params.get("value") or "")
        key = str(params.get("key") or "")
        log_record.update({"key": key, "value": value})
        if key == "reasoning":
            valid_efforts = {
                "none",
                "minimal",
                "low",
                "medium",
                "high",
                "xhigh",
                "max",
                "ultra",
            }
            if value not in valid_efforts:
                state.log({**log_record, "accepted": False})
                await ws.send_str(rpc_error(request_id, "Invalid reasoning effort"))
                return
            state.session_reasoning[session_id] = value
            state.log({**log_record, "accepted": True})
            await ws.send_str(
                rpc_result(
                    request_id,
                    {"updated": True, "scope": "session", "value": value},
                )
            )
            return
        if key != "model" or "--session" not in value:
            state.log({**log_record, "accepted": False})
            await ws.send_str(
                rpc_error(request_id, "Fixture requires a session model override")
            )
            return
        model_part, _, provider_part = value.partition(" --provider ")
        provider = provider_part.replace(" --session", "").strip()
        state.session_models[session_id] = {
            "provider": provider,
            "model": model_part.strip(),
        }
        state.log({**log_record, "accepted": True})
        await ws.send_str(
            rpc_result(
                request_id,
                {
                    "updated": True,
                    "scope": "session",
                    "provider": provider,
                    "model": model_part.strip(),
                },
            )
        )
        return

    if method == "file.attach":
        name = Path(str(params.get("name") or "attachment.bin")).name
        try:
            attachment_bytes = decode_data_url(str(params.get("data_url") or ""))
        except ValueError as error:
            state.log({**log_record, "name": name, "accepted": False})
            await ws.send_str(rpc_error(request_id, str(error)))
            return
        if len(attachment_bytes) > MAX_ATTACHMENT_BYTES:
            state.log(
                {
                    **log_record,
                    "name": name,
                    "bytes": len(attachment_bytes),
                    "accepted": False,
                }
            )
            await ws.send_str(rpc_error(request_id, "Attachment exceeds 16 MiB"))
            return
        digest = hashlib.sha256(attachment_bytes).hexdigest()
        remote_path = (
            f".hermes/desktop-attachments/{session_id}/{name}"
        )
        ref_text = f"@file:{remote_path}"
        metadata: dict[str, object] = {
            "name": name,
            "path": remote_path,
            "ref_text": ref_text,
            "bytes": len(attachment_bytes),
            "sha256": digest,
            "source_channel": str(params.get("source_channel") or ""),
            "source_profile": str(params.get("source_profile") or ""),
        }
        state.attachments.setdefault(session_id, []).append(metadata)
        state.log({**log_record, **metadata, "accepted": True})
        await ws.send_str(
            rpc_result(
                request_id,
                {
                    "attached": True,
                    "uploaded": True,
                    "name": name,
                    "path": remote_path,
                    "ref_text": ref_text,
                    "atlas_intake": {
                        "accepted": True,
                        "status": "accepted",
                        "relative_path": (
                            "00_Inbox/Hermes-Mobile/"
                            f"fixture/{metadata['source_profile']}/{name}"
                        ),
                    },
                },
            )
        )
        return

    if method == "prompt.submit":
        text = str(params.get("text") or "")
        disconnect_scenario = params.get("fixture_disconnect_scenario")
        if disconnect_scenario is not None:
            disconnect_scenario = str(disconnect_scenario)
            if disconnect_scenario not in DISCONNECT_SCENARIOS:
                state.log(
                    {
                        **log_record,
                        "fixture_disconnect_scenario": "invalid",
                        "accepted": False,
                    }
                )
                await ws.send_str(
                    rpc_error(request_id, "Unknown fixture disconnect scenario")
                )
                return

            state.begin_disconnect_scenario(disconnect_scenario)
            state.log(
                {
                    **log_record,
                    "fixture_disconnect_scenario": disconnect_scenario,
                }
            )
            if disconnect_scenario == DISCONNECT_BEFORE_ACK:
                await ws.close(
                    code=1001,
                    message=b"fixture disconnect before ack",
                )
                return

            await ws.send_str(rpc_result(request_id, {"accepted": True}))
            state.mark_disconnect_ack(disconnect_scenario)
            if disconnect_scenario == DISCONNECT_AFTER_ACK:
                await ws.close(
                    code=1001,
                    message=b"fixture disconnect after ack",
                )
                return

            for index in range(MID_STREAM_DISCONNECT_DELTA_COUNT):
                await ws.send_str(
                    gateway_event(
                        "message.delta",
                        session_id,
                        {"text": f"fixture-delta-{index + 1}"},
                    )
                )
                state.mark_disconnect_delta(disconnect_scenario)
            await ws.close(
                code=1001,
                message=b"fixture disconnect mid-stream",
            )
            return

        selected = state.session_models.get(session_id)
        includes_file_ref = "@file:" in text
        log_record.update(
            {
                "text": text,
                "includes_file_ref": includes_file_ref,
                "session_model": selected,
            }
        )
        state.log(log_record)
        await ws.send_str(rpc_result(request_id, {"accepted": True}))

        if includes_file_ref:
            base_response_text = (
                "Fișier primit prin file.attach și referința @file a fost "
                "trimisă corect."
            )
        elif selected:
            base_response_text = (
                f"Modelul {selected['model']} răspunde numai în acest chat."
            )
        else:
            base_response_text = "Răspuns Desktop Gateway primit corect."

        async def stream_prompt() -> None:
            slow_response = "slow stop test" in text.lower()
            approval_test = "approval test" in text.lower()
            sudo_test = "sudo test" in text.lower()
            secret_test = "secret test" in text.lower()
            secret_expire_test = "secret expire test" in text.lower()
            activity_test = "activity test" in text.lower()
            reasoning_test = "reasoning interim test" in text.lower()
            notification_test = "notification subagent test" in text.lower()
            response_text = base_response_text
            approval_future: asyncio.Future[str] | None = None
            sensitive_future: asyncio.Future[str] | None = None
            sensitive_request_id: str | None = None
            clarify_future: asyncio.Future[str] | None = None
            clarify_request_id: str | None = None
            try:
                if notification_test:
                    await ws.send_str(
                        gateway_event(
                            "notification.show",
                            session_id,
                            {
                                "key": "fixture-progress",
                                "level": "info",
                                "text": "Fixture delegation started.",
                                "ttl_ms": 5000,
                            },
                        )
                    )
                    subagent_id = state.next_prompt_id("subagent")
                    await ws.send_str(
                        gateway_event(
                            "subagent.start",
                            session_id,
                            {
                                "subagent_id": subagent_id,
                                "goal": "Inspect fixture transport",
                                "task_index": 1,
                                "task_count": 1,
                                "model": "hermes-android-fixture",
                            },
                        )
                    )
                    await asyncio.sleep(0.15)
                    await ws.send_str(
                        gateway_event(
                            "subagent.complete",
                            session_id,
                            {
                                "subagent_id": subagent_id,
                                "goal": "Inspect fixture transport",
                                "summary": "Fixture transport verified.",
                            },
                        )
                    )
                    await ws.send_str(
                        gateway_event(
                            "notification.clear",
                            session_id,
                            {"key": "fixture-progress"},
                        )
                    )
                    response_text = "Notification and subagent events completed."
                elif reasoning_test:
                    await ws.send_str(
                        gateway_event(
                            "reasoning.delta",
                            session_id,
                            {"text": "Checking the mobile event lifecycle. "},
                        )
                    )
                    await asyncio.sleep(0.15)
                    await ws.send_str(
                        gateway_event(
                            "reasoning.available",
                            session_id,
                            {
                                "text": (
                                    "Verified interim output and delayed "
                                    "background delivery."
                                ),
                                "verbose": False,
                            },
                        )
                    )
                    interim_text = "Interim result: gateway contract verified."
                    await ws.send_str(
                        gateway_event(
                            "message.delta",
                            session_id,
                            {"text": interim_text},
                        )
                    )
                    await ws.send_str(
                        gateway_event(
                            "message.interim",
                            session_id,
                            {
                                "text": interim_text,
                                "already_streamed": True,
                            },
                        )
                    )
                    response_text = (
                        "Final result: Android continued in a new message."
                    )
                elif activity_test:
                    await ws.send_str(
                        gateway_event(
                            "status.update",
                            session_id,
                            {
                                "kind": "working",
                                "text": "Inspecting the gateway activity contract",
                            },
                        )
                    )
                    await asyncio.sleep(0.4)
                    await ws.send_str(
                        gateway_event(
                            "thinking.delta",
                            session_id,
                            {"text": "Planning the synthetic tool run"},
                        )
                    )
                    await asyncio.sleep(0.4)
                    tool_id = state.next_prompt_id("tool")
                    await ws.send_str(
                        gateway_event(
                            "tool.start",
                            session_id,
                            {
                                "tool_id": tool_id,
                                "name": "search_files",
                                "context": "Hermes Android workspace",
                                "args_text": '{"query":"gateway events"}',
                            },
                        )
                    )
                    await asyncio.sleep(2.5)
                    await ws.send_str(
                        gateway_event(
                            "tool.progress",
                            session_id,
                            {
                                "name": "search_files",
                                "preview": "Scanning gateway event handlers",
                            },
                        )
                    )
                    await asyncio.sleep(2.5)
                    await ws.send_str(
                        gateway_event(
                            "tool.complete",
                            session_id,
                            {
                                "tool_id": tool_id,
                                "name": "search_files",
                                "summary": "Found the official activity contract",
                                "duration_s": 5.0,
                            },
                        )
                    )
                    response_text = "Synthetic tool activity completed."
                elif approval_test:
                    approval_future = asyncio.get_running_loop().create_future()
                    pending_approvals[session_id] = approval_future
                    await ws.send_str(
                        gateway_event(
                            "approval.request",
                            session_id,
                            {
                                "command": "echo hermes-android-approval",
                                "description": "Run a synthetic fixture command",
                                "allow_permanent": True,
                                "choices": ["once", "session", "always", "deny"],
                            },
                        )
                    )
                    choice = await approval_future
                    response_text = f"Synthetic command resolved with {choice}."
                elif "batch clarify" in text.lower() and "test" in text.lower():
                    # Mirrors stock Hermes: the clarify tool emits a batch
                    # `questions[]` payload even for a single prompt.
                    clarify_request_id = state.next_prompt_id("clarify")
                    clarify_future = asyncio.get_running_loop().create_future()
                    qids = ["q1", "q2"]
                    pending_batch_clarifications[clarify_request_id] = (
                        session_id,
                        qids,
                        {},
                        clarify_future,
                    )
                    await ws.send_str(
                        gateway_event(
                            "clarify.request",
                            session_id,
                            {
                                "request_id": clarify_request_id,
                                "questions": [
                                    {
                                        "qid": "q1",
                                        "question": (
                                            "Which mobile interface should "
                                            "Hermes use?"
                                        ),
                                        "choices": [
                                            "Compact",
                                            "Balanced",
                                            "Detailed",
                                        ],
                                        "multi_select": False,
                                    },
                                    {
                                        "qid": "q2",
                                        "question": (
                                            "Which features matter most?"
                                        ),
                                        "choices": [
                                            "Voice",
                                            "Notifications",
                                            "Dashboards",
                                        ],
                                        "multi_select": True,
                                    },
                                ],
                            },
                        )
                    )
                    answer = await clarify_future
                    response_text = (
                        f"Synthetic batch clarification received: {answer}."
                        if answer
                        else "Synthetic batch clarification was skipped."
                    )
                elif "clarify" in text.lower() and "test" in text.lower():
                    clarify_request_id = state.next_prompt_id("clarify")
                    clarify_future = asyncio.get_running_loop().create_future()
                    pending_clarifications[clarify_request_id] = (
                        session_id,
                        clarify_future,
                    )
                    is_multi = "multi" in text.lower()
                    is_free_text = "free text" in text.lower()
                    clarify_payload: dict[str, object] = {
                        "request_id": clarify_request_id,
                        "question": (
                            "Which mobile interface should Hermes use?"
                            if not is_free_text
                            else "Describe the Android interface you prefer."
                        ),
                    }
                    if not is_free_text:
                        clarify_payload["choices"] = [
                            "Compact",
                            "Balanced",
                            "Detailed",
                        ]
                    if is_multi:
                        clarify_payload["multi_select"] = True
                    await ws.send_str(
                        gateway_event(
                            "clarify.request",
                            session_id,
                            clarify_payload,
                        )
                    )
                    answer = await clarify_future
                    response_text = (
                        f"Synthetic clarification received: {answer}."
                        if answer
                        else "Synthetic clarification was skipped."
                    )
                elif sudo_test:
                    sensitive_request_id = state.next_prompt_id("sudo")
                    sensitive_future = asyncio.get_running_loop().create_future()
                    pending_sensitive_prompts[sensitive_request_id] = (
                        "sudo",
                        session_id,
                        sensitive_future,
                    )
                    await ws.send_str(
                        gateway_event(
                            "sudo.request",
                            session_id,
                            {"request_id": sensitive_request_id},
                        )
                    )
                    password = await sensitive_future
                    response_text = (
                        "Synthetic sudo password was received."
                        if password
                        else "Synthetic sudo request was cancelled."
                    )
                elif secret_test or secret_expire_test:
                    sensitive_request_id = state.next_prompt_id("secret")
                    sensitive_future = asyncio.get_running_loop().create_future()
                    pending_sensitive_prompts[sensitive_request_id] = (
                        "secret",
                        session_id,
                        sensitive_future,
                    )
                    await ws.send_str(
                        gateway_event(
                            "secret.request",
                            session_id,
                            {
                                "request_id": sensitive_request_id,
                                "env_var": "FIXTURE_API_TOKEN",
                                "prompt": "Enter a synthetic test token",
                            },
                        )
                    )
                    if secret_expire_test:
                        await asyncio.sleep(0.2)
                        pending_sensitive_prompts.pop(
                            sensitive_request_id,
                            None,
                        )
                        await ws.send_str(
                            gateway_event(
                                "secret.expire",
                                session_id,
                                {"request_id": sensitive_request_id},
                            )
                        )
                        response_text = "Synthetic secret request expired."
                    else:
                        secret = await sensitive_future
                        response_text = (
                            "Synthetic secret was received."
                            if secret
                            else "Synthetic secret was skipped."
                        )

                tokens = (
                    [token + " " for token in response_text.split(" ")]
                    if slow_response
                    else [
                        response_text[: max(1, len(response_text) // 2)],
                        response_text[max(1, len(response_text) // 2) :],
                    ]
                )
                for token in tokens:
                    await ws.send_str(
                        gateway_event(
                            "message.delta",
                            session_id,
                            {"text": token},
                        )
                    )
                    await asyncio.sleep(10.0 if slow_response else 0.08)
                history = state.messages.setdefault(session_id, [])
                history.extend(
                    [
                        {"role": "user", "content": text},
                        {"role": "assistant", "content": response_text},
                    ]
                )
                await ws.send_str(
                    gateway_event(
                        "turn.end",
                        session_id,
                        {"status": "completed"},
                    )
                )
                if reasoning_test:
                    async def send_delayed_notices() -> None:
                        await asyncio.sleep(0.4)
                        if ws.closed:
                            return
                        await ws.send_str(
                            gateway_event(
                                "background.complete",
                                session_id,
                                {
                                    "task_id": "bg-fixture-1",
                                    "text": (
                                        "Delayed background result reached "
                                        "Android after turn.end."
                                    ),
                                },
                            )
                        )
                        await asyncio.sleep(0.2)
                        if ws.closed:
                            return
                        await ws.send_str(
                            gateway_event(
                                "review.summary",
                                session_id,
                                {
                                    "text": (
                                        "Synthetic review summary is visible "
                                        "as a persistent system notice."
                                    ),
                                },
                            )
                        )

                    asyncio.create_task(send_delayed_notices())
            except asyncio.CancelledError:
                state.log(
                    {
                        "transport": "websocket",
                        "method": "prompt.cancelled",
                        "session_id": session_id,
                    }
                )
                if not ws.closed:
                    await ws.send_str(
                        gateway_event(
                            "turn.end",
                            session_id,
                            {"status": "interrupted"},
                        )
                    )
                raise
            finally:
                if approval_future is not None:
                    pending_approvals.pop(session_id, None)
                if sensitive_request_id is not None:
                    pending_sensitive_prompts.pop(
                        sensitive_request_id,
                        None,
                    )
                if clarify_request_id is not None:
                    pending_clarifications.pop(clarify_request_id, None)
                    pending_batch_clarifications.pop(
                        clarify_request_id,
                        None,
                    )

        previous = active_prompts.get(session_id)
        if previous is not None and not previous.done():
            previous.cancel()
        task = asyncio.create_task(stream_prompt())
        active_prompts[session_id] = task
        task.add_done_callback(
            lambda completed, sid=session_id: (
                active_prompts.pop(sid, None)
                if active_prompts.get(sid) is completed
                else None
            )
        )
        return

    if method == "approval.respond":
        choice = str(params.get("choice") or "deny")
        if choice not in {"once", "session", "always", "deny"}:
            state.log({**log_record, "choice": choice, "resolved": False})
            await ws.send_str(rpc_error(request_id, "Invalid approval choice"))
            return
        approval = pending_approvals.get(session_id)
        resolved = approval is not None and not approval.done()
        if resolved:
            approval.set_result(choice)
        state.log({**log_record, "choice": choice, "resolved": resolved})
        await ws.send_str(rpc_result(request_id, {"resolved": resolved}))
        return

    if method in {"sudo.respond", "secret.respond"}:
        prompt_request_id = str(params.get("request_id") or "")
        expected_kind = "sudo" if method == "sudo.respond" else "secret"
        value_key = "password" if expected_kind == "sudo" else "value"
        entry = pending_sensitive_prompts.get(prompt_request_id)
        if entry is None or entry[0] != expected_kind:
            state.log(
                {
                    **log_record,
                    "request_id": prompt_request_id,
                    "provided": bool(params.get(value_key)),
                    "status": "expired",
                }
            )
            await ws.send_str(rpc_result(request_id, {"status": "expired"}))
            return
        _, _, prompt_future = entry
        if not prompt_future.done():
            prompt_future.set_result(str(params.get(value_key) or ""))
        state.log(
            {
                **log_record,
                "request_id": prompt_request_id,
                "provided": bool(params.get(value_key)),
                "status": "ok",
            }
        )
        await ws.send_str(rpc_result(request_id, {"status": "ok"}))
        return

    if method == "clarify.respond":
        clarify_request_id = str(params.get("request_id") or "")
        question_id = str(params.get("question_id") or "")
        answer = str(params.get("answer") or "")
        batch = pending_batch_clarifications.get(clarify_request_id)
        if batch is not None:
            _, qids, answers, clarify_future = batch
            if question_id:
                if question_id not in qids:
                    state.log(
                        {
                            **log_record,
                            "request_id": clarify_request_id,
                            "question_id": question_id,
                            "status": "unknown_question",
                        }
                    )
                    await ws.send_str(
                        rpc_result(
                            request_id,
                            {"status": "unknown_question_id"},
                        )
                    )
                    return
                answers[question_id] = answer
                remaining = [qid for qid in qids if qid not in answers]
                if not clarify_future.done() and not remaining:
                    clarify_future.set_result(
                        "; ".join(answers[qid] for qid in qids)
                    )
                state.log(
                    {
                        **log_record,
                        "request_id": clarify_request_id,
                        "question_id": question_id,
                        "answer_length": len(answer),
                        "skipped": not bool(answer),
                        "remaining": remaining,
                        "status": "ok",
                    }
                )
                await ws.send_str(
                    rpc_result(
                        request_id,
                        {"status": "ok", "remaining": remaining},
                    )
                )
                return
            # No question_id on a batch request is a cancel-all, mirroring
            # the gateway's plain-cancel path.
            if not clarify_future.done():
                clarify_future.set_result("")
            state.log(
                {
                    **log_record,
                    "request_id": clarify_request_id,
                    "status": "cancelled",
                }
            )
            await ws.send_str(rpc_result(request_id, {"status": "ok"}))
            return
        entry = pending_clarifications.get(clarify_request_id)
        if entry is None:
            state.log(
                {
                    **log_record,
                    "request_id": clarify_request_id,
                    "answer_length": len(answer),
                    "skipped": not bool(answer),
                    "status": "expired",
                }
            )
            await ws.send_str(rpc_result(request_id, {"status": "expired"}))
            return
        _, clarify_future = entry
        if not clarify_future.done():
            clarify_future.set_result(answer)
        state.log(
            {
                **log_record,
                "request_id": clarify_request_id,
                "answer_length": len(answer),
                "skipped": not bool(answer),
                "status": "ok",
            }
        )
        await ws.send_str(rpc_result(request_id, {"status": "ok"}))
        return

    if method == "session.interrupt":
        task = active_prompts.get(session_id)
        interrupted = task is not None and not task.done()
        if interrupted:
            task.cancel()
        state.log({**log_record, "interrupted": interrupted})
        await ws.send_str(
            rpc_result(request_id, {"status": "interrupted", "active": interrupted})
        )
        return

    state.log({**log_record, "accepted": False})
    await ws.send_str(rpc_error(request_id, f"Unknown method: {method}", -32601))


async def websocket_gateway(request: web.Request) -> web.StreamResponse:
    state = state_from(request)
    ticket = request.query.get("ticket", "")
    token = request.query.get("token", "")
    ticket_valid = state.consume_ticket(ticket) if ticket else False
    token_valid = token == DASHBOARD_TOKEN
    if not ticket_valid and not token_valid:
        state.log(
            {
                "transport": "websocket",
                "method": "connect",
                "authorized": False,
                "ticket": ticket or None,
            }
        )
        return web.json_response({"error": "invalid WebSocket ticket"}, status=401)

    ws = web.WebSocketResponse(max_msg_size=20 * 1024 * 1024)
    await ws.prepare(request)
    recovery_connection_id = f"ws-{id(ws)}"
    state.log(
        {
            "transport": "websocket",
            "method": "connect",
            "authorized": True,
            "ticket": ticket or None,
        }
    )
    active_prompts: dict[str, asyncio.Task] = {}
    pending_approvals: dict[str, asyncio.Future[str]] = {}
    pending_sensitive_prompts: dict[
        str, tuple[str, str, asyncio.Future[str]]
    ] = {}
    pending_clarifications: dict[str, tuple[str, asyncio.Future[str]]] = {}
    pending_batch_clarifications: dict[
        str, tuple[str, list[str], dict[str, str], asyncio.Future[str]]
    ] = {}
    await ws.send_json(state.turn_recovery.ready_frame())
    async for message in ws:
        if message.type == WSMsgType.TEXT:
            try:
                payload = json.loads(message.data)
            except json.JSONDecodeError:
                await ws.send_str(rpc_error(None, "Invalid JSON", -32700))
                continue
            if not isinstance(payload, dict):
                await ws.send_str(rpc_error(None, "Expected JSON object"))
                continue
            if state.turn_recovery.handles(payload):
                await state.turn_recovery.handle(
                    ws,
                    payload,
                    recovery_connection_id,
                )
                continue
            await handle_rpc(
                ws,
                state,
                payload,
                active_prompts,
                pending_approvals,
                pending_sensitive_prompts,
                pending_clarifications,
                pending_batch_clarifications,
            )
        elif message.type == WSMsgType.ERROR:
            break
    for task in active_prompts.values():
        task.cancel()
    for approval in pending_approvals.values():
        if not approval.done():
            approval.cancel()
    for _, _, prompt in pending_sensitive_prompts.values():
        if not prompt.done():
            prompt.cancel()
    for _, prompt in pending_clarifications.values():
        if not prompt.done():
            prompt.cancel()
    state.turn_recovery.detach(ws, recovery_connection_id)
    state.log(
        {
            "transport": "websocket",
            "method": "disconnect",
            "authorized": True,
        }
    )
    return ws


def create_app(state: GatewayState) -> web.Application:
    app = web.Application(client_max_size=20 * 1024 * 1024)
    app["state"] = state
    app.router.add_get("/health", health)
    app.router.add_get("/test/disconnect-ledger", disconnect_ledger)
    app.router.add_post(
        "/test/disconnect-ledger/reset",
        reset_disconnect_ledger,
    )
    app.router.add_get("/", dashboard_home)
    app.router.add_post("/auth/password-login", password_login)
    app.router.add_post("/api/auth/ws-ticket", ws_ticket)
    app.router.add_get("/api/model/info", model_info)
    app.router.add_get("/api/model/options", model_options)
    app.router.add_post("/api/model/set", set_default_model)
    app.router.add_get("/api/ws", websocket_gateway)
    app.router.add_get("/api/sessions", list_sessions)
    app.router.add_get(
        "/api/sessions/{session_id}/messages",
        session_messages,
    )
    app.router.add_delete("/api/sessions/{session_id}", delete_session)
    app.router.add_get("/v1/models", models)
    app.router.add_post("/v1/chat/completions", chat_completions)
    return app


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18642)
    parser.add_argument("--api-key", default="test-key")
    parser.add_argument("--log", type=Path)
    parser.add_argument("--turn-recovery-ledger", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    state = GatewayState(
        args.api_key,
        args.log,
        args.turn_recovery_ledger,
    )
    print(
        f"Hermes Android fixture listening on http://{args.host}:{args.port}",
        flush=True,
    )
    web.run_app(
        create_app(state),
        host=args.host,
        port=args.port,
        print=None,
        handle_signals=False,
    )


if __name__ == "__main__":
    main()
