#!/usr/bin/env python3
"""Live contract probe for the local Hermes Android fixture."""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from aiohttp import ClientSession, WSMsgType

try:
    from .turn_recovery_contract import (
        FAULT_AFTER_ACK_BEFORE_FIRST_DELTA,
        FAULT_AFTER_COMMIT_BEFORE_ACK,
        FAULT_AFTER_COMPLETION,
        FAULT_MIDSTREAM,
        TurnRecoveryContractLedger,
    )
except ImportError:
    from turn_recovery_contract import (
        FAULT_AFTER_ACK_BEFORE_FIRST_DELTA,
        FAULT_AFTER_COMMIT_BEFORE_ACK,
        FAULT_AFTER_COMPLETION,
        FAULT_MIDSTREAM,
        TurnRecoveryContractLedger,
    )


DISCONNECT_CASES = (
    ("before_ack", False, 0),
    ("after_ack_before_first_delta", True, 0),
    ("mid_stream_after_2_deltas", True, 2),
)


async def rpc(ws, request_id: int, method: str, params: dict) -> dict:
    await ws.send_json(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }
    )
    while True:
        message = await ws.receive(timeout=5)
        assert message.type == WSMsgType.TEXT, message
        payload = json.loads(message.data)
        if payload.get("id") == request_id:
            assert "error" not in payload, payload
            return payload["result"]


async def rpc_response(ws, request_id: int, method: str, params: dict) -> dict:
    await ws.send_json(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }
    )
    while True:
        message = await ws.receive(timeout=5)
        assert message.type == WSMsgType.TEXT, message
        payload = json.loads(message.data)
        if payload.get("id") == request_id:
            return payload


class _MemoryWebSocket:
    def __init__(self) -> None:
        self.frames: list[dict] = []
        self.closed = False

    async def send_str(self, value: str) -> None:
        self.frames.append(json.loads(value))

    async def close(self, **_kwargs) -> None:
        self.closed = True


async def probe_persistent_recovery_ledger() -> None:
    with tempfile.TemporaryDirectory(prefix="hermes-s12-fake-") as temporary:
        ledger_path = Path(temporary) / "turn-recovery.json"
        first = await asyncio.to_thread(_run_ledger_worker, ledger_path, "first")
        second = await asyncio.to_thread(_run_ledger_worker, ledger_path, "second")
        assert second["stored_session_id"] == first["stored_session_id"]
        assert second["runtime_session_id"] != first["runtime_session_id"]
        assert second["turn_id"] == first["turn_id"]
        assert second["created"] is False
        assert second["reconcile_mode"] == "events"
        assert second["first_event_seq"] == 1
        assert second["has_more"] is True
        assert second["submit_attempt_count"] == 2
        assert second["execution_count"] == 1
        assert second["turn_execution_count"] == 1
        assert second["profile_mismatch_reason"] == "profile_unavailable"
        encoded = ledger_path.read_text(encoding="utf-8")
        assert "SENTINEL_PROMPT_MUST_NOT_PERSIST" not in encoded
        assert "automatic_resubmit" not in encoded

        corrupted = json.loads(encoded)
        corrupted["bindings"][next(iter(corrupted["bindings"]))][
            "binding_version"
        ] = "not-an-int"
        ledger_path.write_text(json.dumps(corrupted), encoding="utf-8")
        failed = subprocess.run(
            [
                sys.executable,
                str(Path(__file__).resolve()),
                "--ledger-worker",
                str(ledger_path),
                "--ledger-phase",
                "inspect",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        assert failed.returncode != 0
        assert "binding is invalid" in failed.stderr


def _run_ledger_worker(ledger_path: Path, phase: str) -> dict:
    completed = subprocess.run(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            "--ledger-worker",
            str(ledger_path),
            "--ledger-phase",
            phase,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


async def _ledger_worker(ledger_path: Path, phase: str) -> dict:
    mobile_session_id = "11111111-1111-4111-8111-111111111111"
    client_turn_id = "22222222-2222-4222-8222-222222222222"
    ledger = TurnRecoveryContractLedger(
        ledger_path, server_profile="fixture-persistent"
    )
    if phase == "inspect":
        return ledger.inspection()
    socket = _MemoryWebSocket()
    connection_id = f"connection-{phase}"
    await ledger.handle(
        socket,
        {
            "id": 1,
            "method": "session.open",
            "params": {
                "mobile_session_id": mobile_session_id,
                # This selector is accepted only because it exactly echoes the
                # fixture's server-owned scope.
                **(
                    {"profile": "fixture-persistent"}
                    if phase == "second"
                    else {}
                ),
            },
        },
        connection_id,
    )
    binding = socket.frames[-1]["result"]
    await ledger.handle(
        socket,
        {
            "id": 2,
            "method": "prompt.submit",
            "params": {
                "session_id": binding["runtime_session_id"],
                "version": 2,
                "client_turn_id": client_turn_id,
                "text": "SENTINEL_PROMPT_MUST_NOT_PERSIST",
                "attachments": [],
            },
        },
        connection_id,
    )
    ack = next(frame["result"] for frame in socket.frames if frame.get("id") == 2)
    if phase == "first":
        return {
            "runtime_session_id": binding["runtime_session_id"],
            "stored_session_id": binding["stored_session_id"],
            "turn_id": ack["turn_id"],
        }
    await ledger.handle(
        socket,
        {
            "id": 3,
            "method": "turn.reconcile",
            "params": {
                "session_id": binding["runtime_session_id"],
                "turn_id": ack["turn_id"],
                "after_seq": 0,
            },
        },
        connection_id,
    )
    reconcile = socket.frames[-1]["result"]
    mismatch_socket = _MemoryWebSocket()
    await ledger.handle(
        mismatch_socket,
        {
            "id": 4,
            "method": "session.open",
            "params": {
                "mobile_session_id": mobile_session_id,
                "profile": "caller-selected-profile",
            },
        },
        "connection-mismatch",
    )
    inspection = ledger.inspection()
    return {
        "runtime_session_id": binding["runtime_session_id"],
        "stored_session_id": binding["stored_session_id"],
        "turn_id": ack["turn_id"],
        "created": ack["created"],
        "reconcile_mode": reconcile["mode"],
        "first_event_seq": reconcile["events"][0]["seq"],
        "has_more": reconcile["has_more"],
        "submit_attempt_count": inspection["submit_attempt_count"],
        "execution_count": inspection["execution_count"],
        "turn_execution_count": inspection["turns"][0]["execution_count"],
        "profile_mismatch_reason": mismatch_socket.frames[-1]["error"]["data"][
            "reason"
        ],
    }


async def _open_recovery_socket(session: ClientSession, base_url: str):
    async with session.post(
        f"{base_url}/api/auth/ws-ticket",
        headers={"X-Hermes-Session-Token": "fixture-dashboard-token"},
    ) as response:
        assert response.status == 200
        ticket = (await response.json())["ticket"]
    ws_url = (
        base_url.replace("http://", "ws://").replace("https://", "wss://")
        + f"/api/ws?ticket={ticket}"
    )
    ws = await session.ws_connect(ws_url, max_msg_size=20 * 1024 * 1024)
    ready_message = await ws.receive(timeout=5)
    assert ready_message.type == WSMsgType.TEXT
    ready = json.loads(ready_message.data)
    recovery = ready["params"]["payload"]["capabilities"]["turn_recovery"]
    assert recovery["version"] == 2
    assert recovery["prompt_submit_version"] == 2
    assert recovery["shadow_only"] is False
    assert recovery["automatic_resubmit"] is False
    assert recovery["methods"] == [
        "session.open",
        "turn.reconcile",
        "turn.interrupt",
        "attachment.detach@2",
    ]
    return ws


async def _submit_until_disconnect(
    ws,
    request_id: int,
    runtime_session_id: str,
    client_turn_id: str,
) -> tuple[dict | None, list[dict]]:
    await ws.send_json(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "prompt.submit",
            "params": {
                "session_id": runtime_session_id,
                "version": 2,
                "client_turn_id": client_turn_id,
                "text": "Synthetic recovery intent.",
                "attachments": [],
            },
        }
    )
    ack = None
    events: list[dict] = []
    while True:
        message = await ws.receive(timeout=5)
        if message.type == WSMsgType.TEXT:
            frame = json.loads(message.data)
            if frame.get("id") == request_id:
                ack = frame["result"]
            elif frame.get("method") == "event":
                events.append(frame["params"])
            continue
        if message.type in {WSMsgType.CLOSE, WSMsgType.CLOSING, WSMsgType.CLOSED}:
            break
        assert message.type != WSMsgType.ERROR, ws.exception()
    return ack, events


async def probe_turn_recovery_v2(session: ClientSession, base_url: str) -> None:
    mobile_session_id = "33333333-3333-4333-8333-333333333333"
    faults = (
        (FAULT_AFTER_COMMIT_BEFORE_ACK, False),
        (FAULT_AFTER_ACK_BEFORE_FIRST_DELTA, True),
        (FAULT_MIDSTREAM, True),
        (FAULT_AFTER_COMPLETION, True),
    )
    stable_stored_id = None
    previous_runtime_id = None
    last_turn_id = None
    for index, (fault, expect_ack) in enumerate(faults, start=1):
        ws = await _open_recovery_socket(session, base_url)
        binding = await rpc(
            ws,
            index * 100,
            "session.open",
            {
                "mobile_session_id": mobile_session_id,
                "profile": "fixture-recovery-a",
            },
        )
        if stable_stored_id is None:
            stable_stored_id = binding["stored_session_id"]
        assert binding["stored_session_id"] == stable_stored_id
        assert binding["runtime_session_id"] != previous_runtime_id
        previous_runtime_id = binding["runtime_session_id"]
        configured = await rpc(
            ws,
            index * 100 + 1,
            "fixture.turn.next_fault",
            {"session_id": binding["runtime_session_id"], "fault": fault},
        )
        assert configured == {"configured": True, "fault": fault}
        client_turn_id = f"44444444-4444-4444-8444-{index:012d}"
        ack, live_events = await _submit_until_disconnect(
            ws,
            index * 100 + 2,
            binding["runtime_session_id"],
            client_turn_id,
        )
        assert (ack is not None) is expect_ack
        assert all(event["turn_id"] for event in live_events)
        assert all(
            event["session_id"] == binding["runtime_session_id"]
            for event in live_events
        )

        reconnect = await _open_recovery_socket(session, base_url)
        rebound = await rpc(
            reconnect,
            index * 100 + 3,
            "session.open",
            {
                "mobile_session_id": mobile_session_id,
                "profile": "fixture-recovery-a",
            },
        )
        assert rebound["stored_session_id"] == stable_stored_id
        assert rebound["runtime_session_id"] != previous_runtime_id
        previous_runtime_id = rebound["runtime_session_id"]
        after_seq = 0
        replay: list[dict] = []
        while True:
            page = await rpc(
                reconnect,
                index * 100 + 4 + after_seq,
                "turn.reconcile",
                {
                    "session_id": rebound["runtime_session_id"],
                    "client_turn_id": client_turn_id,
                    "after_seq": after_seq,
                },
            )
            assert page["mode"] == "events"
            assert page["automatic_resubmit"] is False
            assert page["next_after_seq"] >= after_seq
            replay.extend(page["events"])
            after_seq = page["next_after_seq"]
            if not page["has_more"]:
                last_turn_id = page["turn_id"]
                assert page["status"] == "completed"
                assert after_seq == page["last_seq"]
                break
        assert [event["seq"] for event in replay] == list(range(1, 8))
        assert replay[-1]["type"] == "message.complete"
        assert replay[-1]["payload"]["status"] == "completed"
        await reconnect.close()

    inspect_socket = await _open_recovery_socket(session, base_url)
    inspected = await rpc(inspect_socket, 900, "fixture.turn.inspect", {})
    assert inspected["submit_attempt_count"] == len(faults)
    assert inspected["execution_count"] == len(faults)
    assert all(turn["execution_count"] == 1 for turn in inspected["turns"])
    binding = await rpc(
        inspect_socket,
        901,
        "session.open",
        {
            "mobile_session_id": mobile_session_id,
            "profile": "fixture-recovery-a",
        },
    )
    pruned = await rpc(
        inspect_socket,
        902,
        "fixture.turn.prune",
        {"session_id": binding["runtime_session_id"], "turn_id": last_turn_id},
    )
    assert pruned["earliest_seq"] == 8
    snapshot = await rpc(
        inspect_socket,
        903,
        "turn.reconcile",
        {
            "session_id": binding["runtime_session_id"],
            "turn_id": last_turn_id,
            "after_seq": 0,
        },
    )
    assert snapshot["mode"] == "snapshot"
    assert snapshot["snapshot"]["assistant"] == {
        "message_id": snapshot["snapshot"]["assistant"]["message_id"],
        "text": "Durable recovery completed.",
        "complete": True,
    }
    restarted = await rpc(inspect_socket, 904, "fixture.turn.restart", {})
    assert restarted["durable_turns"] == len(faults)
    binding = await rpc(
        inspect_socket,
        905,
        "session.open",
        {
            "mobile_session_id": mobile_session_id,
            "profile": "fixture-recovery-a",
        },
    )

    isolated_socket = await _open_recovery_socket(session, base_url)
    isolated = await rpc_response(
        isolated_socket,
        906,
        "session.open",
        {
            "mobile_session_id": mobile_session_id,
            "profile": "fixture-recovery-b",
        },
    )
    assert isolated["error"]["data"] == {
        "reason": "profile_unavailable",
        "safe_to_resubmit": False,
    }
    closed_schema = await rpc_response(
        inspect_socket,
        907,
        "prompt.submit",
        {
            "session_id": binding["runtime_session_id"],
            "version": 2,
            "client_turn_id": "55555555-5555-4555-8555-555555555555",
            "text": "No in-band fixture fields.",
            "attachments": [],
            "fixture_fault": FAULT_MIDSTREAM,
        },
    )
    assert closed_schema["error"]["data"]["reason"] == "closed_prompt_schema"
    without_attachments = await rpc(
        inspect_socket,
        908,
        "prompt.submit",
        {
            "session_id": binding["runtime_session_id"],
            "version": 2,
            "client_turn_id": "66666666-6666-4666-8666-666666666666",
            "text": "Missing attachments defaults to an empty manifest.",
        },
    )
    assert without_attachments["accepted"] is True
    assert without_attachments["created"] is True
    no_attachment_events: list[dict] = []
    while len(no_attachment_events) < 6:
        message = await inspect_socket.receive(timeout=5)
        assert message.type == WSMsgType.TEXT, message
        frame = json.loads(message.data)
        if frame.get("method") == "event":
            no_attachment_events.append(frame["params"])
    assert all(
        event["session_id"] == binding["runtime_session_id"]
        for event in no_attachment_events
    )
    await isolated_socket.close()
    await inspect_socket.close()


async def probe_disconnect_scenario(
    session: ClientSession,
    base_url: str,
    scenario: str,
    expected_ack: bool,
    expected_deltas: int,
    request_id: int,
) -> None:
    async with session.post(
        f"{base_url}/api/auth/ws-ticket",
        headers={"X-Hermes-Session-Token": "fixture-dashboard-token"},
    ) as response:
        assert response.status == 200
        ticket = (await response.json())["ticket"]

    ws_url = (
        base_url.replace("http://", "ws://")
        .replace("https://", "wss://")
        + f"/api/ws?ticket={ticket}"
    )
    session_id = f"fixture-disconnect-{scenario}"
    ack_seen = False
    delta_count = 0
    turn_end_count = 0

    async with session.ws_connect(ws_url) as ws:
        created = await rpc(
            ws,
            request_id,
            "session.create",
            {"session_id": session_id},
        )
        assert created["session_id"] == session_id
        await ws.send_json(
            {
                "jsonrpc": "2.0",
                "id": request_id + 1,
                "method": "prompt.submit",
                "params": {
                    "session_id": session_id,
                    "text": "Synthetic disconnect contract probe.",
                    "fixture_disconnect_scenario": scenario,
                },
            }
        )

        while True:
            message = await ws.receive(timeout=5)
            if message.type == WSMsgType.TEXT:
                payload = json.loads(message.data)
                if payload.get("id") == request_id + 1:
                    assert payload["result"]["accepted"] is True
                    ack_seen = True
                    continue
                if payload.get("method") != "event":
                    continue
                event_type = payload["params"]["type"]
                if event_type == "message.delta":
                    delta_count += 1
                if event_type == "turn.end":
                    turn_end_count += 1
                continue
            if message.type in {
                WSMsgType.CLOSE,
                WSMsgType.CLOSING,
                WSMsgType.CLOSED,
            }:
                break
            assert message.type != WSMsgType.ERROR, ws.exception()
            raise AssertionError(f"Unexpected WebSocket message: {message}")

    assert ack_seen is expected_ack
    assert delta_count == expected_deltas
    assert turn_end_count == 0

    async with session.get(
        f"{base_url}/api/sessions/{session_id}/messages",
        headers={"Authorization": "Bearer test-key"},
    ) as response:
        assert response.status == 200
        history = await response.json()
        assert history["data"] == []


async def probe(base_url: str) -> None:
    await probe_persistent_recovery_ledger()
    dashboard_headers = {
        "X-Hermes-Session-Token": "fixture-dashboard-token"
    }
    async with ClientSession() as session:
        async with session.get(f"{base_url}/health") as response:
            health = await response.json()
            assert response.status == 200
            assert "json-rpc-websocket" in health["contracts"]
            assert "fail-closed-disconnect-fixtures" in health["contracts"]
            assert "turn-recovery-v2-fixture" in health["contracts"]

        async with session.post(
            f"{base_url}/test/disconnect-ledger/reset"
        ) as response:
            assert response.status == 200
            reset_ledger = await response.json()
            assert reset_ledger["schema"] == (
                "hermes.fake_gateway.disconnect_ledger.v1"
            )
            assert all(
                record["prompt_submit_count"] == 0
                for record in reset_ledger["scenarios"].values()
            )

        async with session.get(f"{base_url}/") as response:
            homepage = await response.text()
            assert 'window.__HERMES_SESSION_TOKEN__="fixture-dashboard-token";' in homepage

        async with session.get(
            f"{base_url}/api/model/info",
            headers=dashboard_headers,
        ) as response:
            model_info = await response.json()
            assert model_info == {
                "model": "hermes-agent",
                "provider": "fixture",
            }

        async with session.get(
            f"{base_url}/api/model/options",
            headers=dashboard_headers,
        ) as response:
            options = await response.json()
            assert options["providers"][0]["models"][1]["id"] == "fixture-model"

        async with session.post(
            f"{base_url}/api/model/set",
            headers=dashboard_headers,
            json={
                "scope": "main",
                "provider": "fixture",
                "model": "fixture-model",
            },
        ) as response:
            profile_default = await response.json()
            assert profile_default["scope"] == "profile"
            assert profile_default["model"] == "fixture-model"

        async with session.get(
            f"{base_url}/api/model/info",
            headers=dashboard_headers,
        ) as response:
            updated_info = await response.json()
            assert updated_info["model"] == "fixture-model"

        async with session.post(
            f"{base_url}/api/model/set",
            headers=dashboard_headers,
            json={
                "scope": "main",
                "provider": "fixture",
                "model": "hermes-agent",
            },
        ) as response:
            reset_default = await response.json()
            assert reset_default["model"] == "hermes-agent"

        async with session.post(
            f"{base_url}/api/auth/ws-ticket",
            headers=dashboard_headers,
        ) as response:
            ticket = (await response.json())["ticket"]

        ws_url = (
            base_url.replace("http://", "ws://")
            .replace("https://", "wss://")
            + f"/api/ws?ticket={ticket}"
        )
        async with session.ws_connect(ws_url, max_msg_size=20 * 1024 * 1024) as ws:
            session_id = "fixture-contract-test"
            created = await rpc(
                ws,
                1,
                "session.create",
                {"session_id": session_id},
            )
            assert created["session_id"] == session_id
            resumed = await rpc(
                ws,
                101,
                "session.resume",
                {"session_id": session_id},
            )
            assert resumed["session_id"] == session_id
            renamed = await rpc(
                ws,
                102,
                "session.title",
                {"session_id": session_id, "title": "Fixture renamed"},
            )
            assert renamed["title"] == "Fixture renamed"
            branched = await rpc(
                ws,
                103,
                "session.branch",
                {"session_id": session_id, "name": "Fixture branch"},
            )
            assert branched["parent"] == session_id
            assert branched["session_id"].endswith("-branch")

            configured = await rpc(
                ws,
                2,
                "config.set",
                {
                    "session_id": session_id,
                    "key": "model",
                    "value": "fixture-model --provider fixture --session",
                },
            )
            assert configured["scope"] == "session"
            reasoning_configured = await rpc(
                ws,
                104,
                "config.set",
                {
                    "session_id": session_id,
                    "key": "reasoning",
                    "value": "xhigh",
                },
            )
            assert reasoning_configured["value"] == "xhigh"
            reasoning = await rpc(
                ws,
                105,
                "config.get",
                {"session_id": session_id, "key": "reasoning"},
            )
            assert reasoning["value"] == "xhigh"

            fixture_bytes = b"Hermes Android fixture attachment\n"
            attachment = await rpc(
                ws,
                3,
                "file.attach",
                {
                    "session_id": session_id,
                    "name": "contract-probe.txt",
                    "path": "",
                    "source_channel": "hermes_mobile",
                    "source_profile": "pro",
                    "data_url": (
                        "data:text/plain;base64,"
                        + base64.b64encode(fixture_bytes).decode("ascii")
                    ),
                },
            )
            assert attachment["attached"] is True
            assert attachment["ref_text"].startswith("@file:")
            assert attachment["atlas_intake"]["accepted"] is True
            assert attachment["atlas_intake"]["status"] == "accepted"

            await ws.send_json(
                {
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "prompt.submit",
                    "params": {
                        "session_id": session_id,
                        "text": f"Inspect this fixture.\n\n{attachment['ref_text']}",
                    },
                }
            )
            response_seen = False
            delta_text = ""
            turn_end_seen = False
            while not turn_end_seen:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("id") == 4:
                    assert payload["result"]["accepted"] is True
                    response_seen = True
                    continue
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    delta_text += params["payload"]["text"]
                if params["type"] == "turn.end":
                    turn_end_seen = True

            assert response_seen
            assert "file.attach" in delta_text
            assert turn_end_seen

            slow_prompt = await rpc(
                ws,
                5,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "slow stop test",
                },
            )
            assert slow_prompt["accepted"] is True
            first_delta = await ws.receive(timeout=5)
            first_delta_payload = json.loads(first_delta.data)
            assert first_delta_payload["params"]["type"] == "message.delta"

            interrupted = await rpc(
                ws,
                6,
                "session.interrupt",
                {"session_id": session_id},
            )
            assert interrupted["status"] == "interrupted"
            assert interrupted["active"] is True

            terminal = await ws.receive(timeout=5)
            terminal_payload = json.loads(terminal.data)
            assert terminal_payload["params"]["type"] == "turn.end"
            assert terminal_payload["params"]["payload"]["status"] == "interrupted"

            approval_prompt = await rpc(
                ws,
                7,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "approval test",
                },
            )
            assert approval_prompt["accepted"] is True
            approval_message = await ws.receive(timeout=5)
            approval_payload = json.loads(approval_message.data)
            assert approval_payload["params"]["type"] == "approval.request"
            approval_request = approval_payload["params"]["payload"]
            assert approval_request["command"] == "echo hermes-android-approval"
            assert approval_request["choices"] == [
                "once",
                "session",
                "always",
                "deny",
            ]

            approved = await rpc(
                ws,
                8,
                "approval.respond",
                {
                    "session_id": session_id,
                    "choice": "session",
                },
            )
            assert approved["resolved"] is True

            approval_delta = ""
            approval_turn_end = False
            while not approval_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    approval_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    approval_turn_end = True
            assert "resolved with session" in approval_delta

            sudo_prompt = await rpc(
                ws,
                9,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "sudo test",
                },
            )
            assert sudo_prompt["accepted"] is True
            sudo_message = await ws.receive(timeout=5)
            sudo_payload = json.loads(sudo_message.data)
            assert sudo_payload["params"]["type"] == "sudo.request"
            sudo_request_id = sudo_payload["params"]["payload"]["request_id"]
            sudo_result = await rpc(
                ws,
                10,
                "sudo.respond",
                {
                    "request_id": sudo_request_id,
                    "password": "fixture-sudo-password",
                },
            )
            assert sudo_result["status"] == "ok"

            sudo_delta = ""
            sudo_turn_end = False
            while not sudo_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    sudo_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    sudo_turn_end = True
            assert "sudo password was received" in sudo_delta

            secret_prompt = await rpc(
                ws,
                11,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "secret test",
                },
            )
            assert secret_prompt["accepted"] is True
            secret_message = await ws.receive(timeout=5)
            secret_payload = json.loads(secret_message.data)
            assert secret_payload["params"]["type"] == "secret.request"
            secret_request = secret_payload["params"]["payload"]
            assert secret_request["env_var"] == "FIXTURE_API_TOKEN"
            secret_result = await rpc(
                ws,
                12,
                "secret.respond",
                {
                    "request_id": secret_request["request_id"],
                    "value": "fixture-secret-value",
                },
            )
            assert secret_result["status"] == "ok"

            secret_delta = ""
            secret_turn_end = False
            while not secret_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    secret_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    secret_turn_end = True
            assert "secret was received" in secret_delta

            expiring_prompt = await rpc(
                ws,
                13,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "secret expire test",
                },
            )
            assert expiring_prompt["accepted"] is True
            expiring_request = await ws.receive(timeout=5)
            expiring_payload = json.loads(expiring_request.data)
            assert expiring_payload["params"]["type"] == "secret.request"
            expiring_request_id = expiring_payload["params"]["payload"]["request_id"]

            expire_seen = False
            expire_turn_end = False
            while not expire_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "secret.expire":
                    assert params["payload"]["request_id"] == expiring_request_id
                    expire_seen = True
                if params["type"] == "turn.end":
                    expire_turn_end = True
            assert expire_seen

            expired_result = await rpc(
                ws,
                14,
                "secret.respond",
                {
                    "request_id": expiring_request_id,
                    "value": "late-secret-value",
                },
            )
            assert expired_result["status"] == "expired"

            clarify_prompt = await rpc(
                ws,
                15,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "clarify test",
                },
            )
            assert clarify_prompt["accepted"] is True
            clarify_message = await ws.receive(timeout=5)
            clarify_payload = json.loads(clarify_message.data)
            assert clarify_payload["params"]["type"] == "clarify.request"
            clarify_request = clarify_payload["params"]["payload"]
            assert clarify_request["choices"] == [
                "Compact",
                "Balanced",
                "Detailed",
            ]
            assert "request_id" in clarify_request

            clarified = await rpc(
                ws,
                16,
                "clarify.respond",
                {
                    "request_id": clarify_request["request_id"],
                    "answer": "Balanced",
                },
            )
            assert clarified["status"] == "ok"

            clarify_delta = ""
            clarify_turn_end = False
            while not clarify_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    clarify_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    clarify_turn_end = True
            assert "clarification received: Balanced" in clarify_delta

            multi_prompt = await rpc(
                ws,
                17,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "clarify multi test",
                },
            )
            assert multi_prompt["accepted"] is True
            multi_message = await ws.receive(timeout=5)
            multi_payload = json.loads(multi_message.data)
            assert multi_payload["params"]["type"] == "clarify.request"
            multi_request = multi_payload["params"]["payload"]
            assert multi_request["multi_select"] is True

            multi_result = await rpc(
                ws,
                18,
                "clarify.respond",
                {
                    "request_id": multi_request["request_id"],
                    "answer": "Compact, Detailed",
                },
            )
            assert multi_result["status"] == "ok"

            multi_delta = ""
            multi_turn_end = False
            while not multi_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    multi_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    multi_turn_end = True
            assert "Compact, Detailed" in multi_delta

            free_text_prompt = await rpc(
                ws,
                19,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "clarify free text test",
                },
            )
            assert free_text_prompt["accepted"] is True
            free_text_message = await ws.receive(timeout=5)
            free_text_payload = json.loads(free_text_message.data)
            assert free_text_payload["params"]["type"] == "clarify.request"
            free_text_request = free_text_payload["params"]["payload"]
            assert "choices" not in free_text_request

            skipped = await rpc(
                ws,
                20,
                "clarify.respond",
                {
                    "request_id": free_text_request["request_id"],
                    "answer": "",
                },
            )
            assert skipped["status"] == "ok"

            skipped_delta = ""
            skipped_turn_end = False
            while not skipped_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    skipped_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    skipped_turn_end = True
            assert "clarification was skipped" in skipped_delta

            batch_prompt = await rpc(
                ws,
                121,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "batch clarify test",
                },
            )
            assert batch_prompt["accepted"] is True
            batch_message = await ws.receive(timeout=5)
            batch_payload = json.loads(batch_message.data)
            assert batch_payload["params"]["type"] == "clarify.request"
            batch_request = batch_payload["params"]["payload"]
            assert batch_request["questions"][0]["qid"] == "q1"
            assert batch_request["questions"][1]["qid"] == "q2"
            assert "question" not in batch_request

            q1_result = await rpc(
                ws,
                122,
                "clarify.respond",
                {
                    "request_id": batch_request["request_id"],
                    "question_id": "q1",
                    "answer": "Balanced",
                },
            )
            assert q1_result["status"] == "ok"
            assert q1_result["remaining"] == ["q2"]

            q2_result = await rpc(
                ws,
                123,
                "clarify.respond",
                {
                    "request_id": batch_request["request_id"],
                    "question_id": "q2",
                    "answer": "Voice, Notifications",
                },
            )
            assert q2_result["status"] == "ok"
            assert q2_result["remaining"] == []

            batch_delta = ""
            batch_turn_end = False
            while not batch_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                if params["type"] == "message.delta":
                    batch_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    batch_turn_end = True
            assert "batch clarification received: Balanced" in batch_delta
            assert "Voice, Notifications" in batch_delta

            late_clarify = await rpc(
                ws,
                21,
                "clarify.respond",
                {
                    "request_id": "clarify-expired",
                    "answer": "Late answer",
                },
            )
            assert late_clarify["status"] == "expired"

            activity_prompt = await rpc(
                ws,
                22,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "activity test",
                },
            )
            assert activity_prompt["accepted"] is True
            activity_events: list[dict] = []
            activity_delta = ""
            activity_turn_end = False
            while not activity_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                activity_events.append(params)
                if params["type"] == "message.delta":
                    activity_delta += params["payload"]["text"]
                if params["type"] == "turn.end":
                    activity_turn_end = True

            activity_types = [event["type"] for event in activity_events]
            assert activity_types[:5] == [
                "status.update",
                "thinking.delta",
                "tool.start",
                "tool.progress",
                "tool.complete",
            ]
            tool_start = activity_events[2]["payload"]
            tool_progress = activity_events[3]["payload"]
            tool_complete = activity_events[4]["payload"]
            assert tool_start["tool_id"].startswith("tool-")
            assert tool_start["name"] == "search_files"
            assert tool_progress == {
                "name": "search_files",
                "preview": "Scanning gateway event handlers",
            }
            assert tool_complete["tool_id"] == tool_start["tool_id"]
            assert tool_complete["summary"] == (
                "Found the official activity contract"
            )
            assert "tool activity completed" in activity_delta

            reasoning_prompt = await rpc(
                ws,
                23,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "reasoning interim test",
                },
            )
            assert reasoning_prompt["accepted"] is True
            reasoning_events: list[dict] = []
            reasoning_turn_end = False
            delayed_types: set[str] = set()
            while not (
                reasoning_turn_end
                and delayed_types
                == {"background.complete", "review.summary"}
            ):
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                params = payload["params"]
                reasoning_events.append(params)
                if params["type"] == "turn.end":
                    reasoning_turn_end = True
                if reasoning_turn_end and params["type"] in {
                    "background.complete",
                    "review.summary",
                }:
                    delayed_types.add(params["type"])

            reasoning_types = [event["type"] for event in reasoning_events]
            assert reasoning_types[:5] == [
                "reasoning.delta",
                "reasoning.available",
                "message.delta",
                "message.interim",
                "message.delta",
            ]
            interim_payload = reasoning_events[3]["payload"]
            assert interim_payload["already_streamed"] is True
            assert interim_payload["text"].startswith("Interim result:")
            assert reasoning_types.index("background.complete") > (
                reasoning_types.index("turn.end")
            )
            assert reasoning_types.index("review.summary") > (
                reasoning_types.index("turn.end")
            )

            notification_prompt = await rpc(
                ws,
                24,
                "prompt.submit",
                {
                    "session_id": session_id,
                    "text": "notification subagent test",
                },
            )
            assert notification_prompt["accepted"] is True
            notification_types: list[str] = []
            notification_turn_end = False
            while not notification_turn_end:
                message = await ws.receive(timeout=5)
                assert message.type == WSMsgType.TEXT, message
                payload = json.loads(message.data)
                if payload.get("method") != "event":
                    continue
                event_type = payload["params"]["type"]
                notification_types.append(event_type)
                if event_type == "turn.end":
                    notification_turn_end = True
            assert notification_types[:4] == [
                "notification.show",
                "subagent.start",
                "subagent.complete",
                "notification.clear",
            ]

        for index, (scenario, expected_ack, expected_deltas) in enumerate(
            DISCONNECT_CASES
        ):
            await probe_disconnect_scenario(
                session,
                base_url,
                scenario,
                expected_ack,
                expected_deltas,
                200 + index * 10,
            )

        async with session.get(
            f"{base_url}/test/disconnect-ledger"
        ) as response:
            assert response.status == 200
            ledger = await response.json()

        assert ledger == {
            "schema": "hermes.fake_gateway.disconnect_ledger.v1",
            "scenarios": {
                scenario: {
                    "prompt_submit_count": 1,
                    "disconnect_point": scenario,
                    "ack_seen": expected_ack,
                    "delta_count": expected_deltas,
                    "turn_end_count": 0,
                    "resubmit_count": 0,
                }
                for scenario, expected_ack, expected_deltas in DISCONNECT_CASES
            },
        }
        ledger_json = json.dumps(ledger)
        assert "Synthetic disconnect contract probe" not in ledger_json
        assert "test-key" not in ledger_json

        async with session.post(
            f"{base_url}/test/disconnect-ledger/reset"
        ) as response:
            assert response.status == 200
            cleared_ledger = await response.json()
        assert all(
            record == {
                "prompt_submit_count": 0,
                "disconnect_point": scenario,
                "ack_seen": False,
                "delta_count": 0,
                "turn_end_count": 0,
                "resubmit_count": 0,
            }
            for scenario, record in cleared_ledger["scenarios"].items()
        )

        await probe_turn_recovery_v2(session, base_url)

    print(
        json.dumps(
            {
                "status": "ok",
                "contracts": [
                    "dashboard-token",
                    "profile-default-model",
                    "ws-ticket",
                    "session.create",
                    "session.resume",
                    "session.title",
                    "session.branch",
                    "config.set",
                    "config.get",
                    "file.attach",
                    "prompt.submit",
                    "message.delta",
                    "turn.end",
                    "session.interrupt",
                    "approval.request",
                    "approval.respond",
                    "sudo.request",
                    "sudo.respond",
                    "secret.request",
                    "secret.respond",
                    "secret.expire",
                    "clarify.request",
                    "clarify.respond",
                    "status.update",
                    "thinking.delta",
                    "tool.start",
                    "tool.progress",
                    "tool.complete",
                    "reasoning.delta",
                    "reasoning.available",
                    "message.interim",
                    "background.complete",
                    "review.summary",
                    "notification.show",
                    "notification.clear",
                    "subagent.start",
                    "subagent.complete",
                    "disconnect.before_ack",
                    "disconnect.after_ack_before_first_delta",
                    "disconnect.mid_stream_after_2_deltas",
                    "disconnect-ledger-v1",
                    "turn-recovery-v2",
                ],
            }
        )
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:18642")
    parser.add_argument("--ledger-worker", type=Path)
    parser.add_argument(
        "--ledger-phase", choices=("first", "second", "inspect")
    )
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    if arguments.ledger_worker is not None:
        if arguments.ledger_phase is None:
            raise SystemExit("--ledger-phase is required with --ledger-worker")
        print(
            json.dumps(
                asyncio.run(
                    _ledger_worker(arguments.ledger_worker, arguments.ledger_phase)
                ),
                sort_keys=True,
            )
        )
    else:
        asyncio.run(probe(arguments.url.rstrip("/")))
