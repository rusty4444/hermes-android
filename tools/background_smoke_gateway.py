#!/usr/bin/env python3
"""Local-only, controllable stock Gateway for Android background smoke tests.

This is a test fixture, not an agent or a production-compatible server. All
messages are explicitly labelled fixture content. Nothing calls a model/tool.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import time
from pathlib import Path

from aiohttp import WSMsgType, web

TEST_KEY = "background-smoke-fixture-key"
STATE_KEY = web.AppKey("smoke_state", object)


class SmokeState:
    def __init__(self, log_path: Path | None = None):
        self.log_path = log_path
        self.chats = {}
        self.runtime = {}
        self.sockets = {}
        self.submit_count = 0
        self.connection_count = 0
        self.disconnect_count = 0
        self.next_row = 0
        self.started = asyncio.Event()
        for suffix in ("a", "b"):
            sid = f"smoke-chat-{suffix}"
            self.chats[sid] = {
                "id": sid, "title": f"Background fixture {suffix.upper()}",
                "model": "hermes-agent", "source": "cli", "started_at": time.time(),
                "last_active": time.time(), "ended_at": None, "running": False,
                "phase": 0, "turn_id": None, "rows": [],
            }
            self.append(sid, "user", "Fixture initial question.")
            self.append(sid, "assistant", "Fixture previous reply.")

    def append(self, sid, role, content, **extra):
        self.next_row += 1
        self.chats[sid]["rows"].append({
            "id": self.next_row, "role": role, "content": content,
            "timestamp": time.time(), **extra,
        })
        self.chats[sid]["last_active"] = time.time()

    def record(self, **fields):
        if self.log_path is not None:
            with self.log_path.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps({"at": time.time(), **fields}) + "\n")

    def summary(self, chat):
        return {key: value for key, value in chat.items() if key not in {"rows", "phase"}} | {
            "message_count": len(chat["rows"]), "preview": chat["rows"][-1]["content"],
            "is_active": chat["running"],
        }

    async def emit(self, sid, kind, payload):
        frame = {
            "jsonrpc": "2.0", "method": "event", "params": {
                "type": kind, "session_id": sid,
                "turn_id": self.chats[sid]["turn_id"], "payload": payload,
            },
        }
        delivered = 0
        for socket, subscribed in list(self.sockets.items()):
            if sid not in subscribed or socket.closed:
                continue
            runtime_id = next((rid for rid, value in self.runtime.items()
                               if value == (socket, sid)), sid)
            scoped_frame = {**frame, "params": {**frame["params"], "session_id": runtime_id}}
            try:
                await socket.send_json(scoped_frame)
                delivered += 1
            except ConnectionResetError:
                pass
        self.record(event=kind, session_id=sid, delivered=delivered)

    async def start_turn(self, sid, prompt):
        chat = self.chats[sid]
        if chat["running"]:
            raise ValueError("fixture chat already running")
        self.submit_count += 1
        chat.update(running=True, phase=0, turn_id=f"smoke-turn-{self.submit_count}")
        self.append(sid, "user", str(prompt))
        self.append(sid, "assistant", "Fixture commentary A.", interim=True)
        await self.emit(sid, "turn.start", {"status": "running"})
        await self.emit(sid, "message.delta", {"text": "Fixture commentary A."})
        await self.emit(sid, "message.interim", {"text": "Fixture commentary A.", "already_streamed": True})
        await self.emit(sid, "tool.start", {
            "tool": "fixture_tool_one", "name": "fixture_tool_one", "toolCallId": f"{chat['turn_id']}-tool1",
            "tool_call_id": f"{chat['turn_id']}-tool1", "status": "running", "label": "Fixture first tool",
        })
        self.started.set()

    async def advance(self, sid):
        chat = self.chats[sid]
        if not chat["running"]:
            return
        turn = chat["turn_id"]
        if chat["phase"] == 0:
            chat["phase"] = 1
            self.append(sid, "tool", "Fixture first tool result.", tool_call_id=f"{turn}-tool1", name="fixture_tool_one")
            await self.emit(sid, "tool.complete", {"tool": "fixture_tool_one", "toolCallId": f"{turn}-tool1", "status": "completed"})
            self.append(sid, "assistant", "Fixture commentary B.", interim=True)
            await self.emit(sid, "message.delta", {"text": "Fixture commentary B."})
            await self.emit(sid, "message.interim", {"text": "Fixture commentary B.", "already_streamed": True})
            await self.emit(sid, "reasoning.delta", {"text": "Fixture exposed reasoning between tools."})
            await self.emit(sid, "tool.start", {"tool": "fixture_tool_two", "toolCallId": f"{turn}-tool2", "status": "running", "label": "Fixture second tool"})
        else:
            self.append(sid, "tool", "Fixture second tool result.", tool_call_id=f"{turn}-tool2", name="fixture_tool_two")
            await self.emit(sid, "tool.complete", {"tool": "fixture_tool_two", "toolCallId": f"{turn}-tool2", "status": "completed"})
            self.append(sid, "assistant", "Fixture final answer C.")
            chat["running"] = False
            await self.emit(sid, "message.complete", {"text": "Fixture final answer C.", "status": "complete"})
            await self.emit(sid, "turn.end", {"status": "complete"})


@web.middleware
async def authorization(request, handler):
    if request.path not in {"/health", "/auth/password-login", "/api/auth/ws-ticket", "/api/ws"}:
        if request.headers.get("Authorization") != f"Bearer {TEST_KEY}":
            return web.json_response({"error": "fixture key required"}, status=401)
    return await handler(request)


async def rpc_socket(request):
    state = request.app[STATE_KEY]
    if request.query.get("ticket") != "smoke-ticket":
        return web.json_response({"error": "fixture ticket required"}, status=401)
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    state.connection_count += 1
    state.sockets[ws] = set()
    await ws.send_json({"jsonrpc": "2.0", "method": "event", "params": {"type": "gateway.ready", "payload": {}}})
    try:
        async for message in ws:
            if message.type != WSMsgType.TEXT:
                continue
            frame = json.loads(message.data)
            method, rpc_id, params = frame.get("method"), frame.get("id"), frame.get("params", {})
            state.record(rpc=method, rpc_id=rpc_id)
            result, error = {"ok": True}, None
            if method == "gateway.ping":
                pass
            elif method == "session.resume":
                sid = params.get("session_id")
                if sid not in state.chats:
                    error = {"code": 4007, "message": "fixture session not found"}
                else:
                    runtime = f"runtime-{state.connection_count}-{sid}"
                    state.runtime[runtime] = (ws, sid)
                    state.sockets[ws].add(sid)
                    chat = state.chats[sid]
                    result = {"session_id": runtime, "stored_session_id": sid, "running": chat["running"], "status": "running" if chat["running"] else "idle", "open_requests": []}
            elif method == "session.create":
                error = {"code": 4005, "message": "fixture requires existing test chats"}
            elif method == "prompt.submit":
                binding = state.runtime.get(params.get("session_id"))
                if binding is None or binding[0] is not ws:
                    error = {"code": 4007, "message": "fixture runtime not found"}
                else:
                    try:
                        await state.start_turn(binding[1], params.get("prompt", params.get("text", "Fixture request")))
                    except ValueError as exc:
                        error = {"code": 4005, "message": str(exc)}
            elif method in {"session.model.get", "session.model.set", "session.reasoning.get", "session.reasoning.set"}:
                result = {"provider": "fixture", "model": "hermes-agent", "reasoning_effort": "medium"}
            elif method == "session.history":
                binding = state.runtime.get(params.get("session_id"))
                result = {"messages": state.chats[binding[1]]["rows"] if binding else []}
            elif method.startswith("projects."):
                error = {"code": -32601, "message": "fixture has no projects"}
            if rpc_id is not None:
                await ws.send_json({"jsonrpc": "2.0", "id": rpc_id, **({"error": error} if error else {"result": result})})
    finally:
        state.sockets.pop(ws, None)
        state.disconnect_count += 1
        state.record(event="socket_closed", active_turns=[sid for sid, c in state.chats.items() if c["running"]])
    return ws


def create_app(state):
    app = web.Application(middlewares=[authorization])
    app[STATE_KEY] = state

    async def health(_):
        return web.json_response({"status": "ok", "fixture": True})

    async def login(_):
        response = web.json_response({"ok": True})
        response.set_cookie("hermes_session_at", "smoke-cookie", httponly=True)
        return response

    async def ticket(_):
        return web.json_response({"ticket": "smoke-ticket"})

    async def sessions(_):
        return web.json_response({"object": "list", "data": [state.summary(c) for c in state.chats.values()]})

    async def detail(request):
        chat = state.chats.get(request.match_info["sid"])
        return web.json_response(state.summary(chat) if chat else {"error": "not found"}, status=200 if chat else 404)

    async def messages(request):
        chat = state.chats.get(request.match_info["sid"])
        if chat is None:
            return web.json_response({"error": "not found"}, status=404)
        offset = max(0, int(request.query.get("offset", 0)))
        limit = min(1000, max(1, int(request.query.get("limit", 50))))
        rows = chat["rows"]
        end = max(0, len(rows)-offset)
        return web.json_response({"object": "list", "session_id": chat["id"], "data": rows[max(0, end-limit):end]})

    async def models(_):
        return web.json_response({"data": [{"id": "hermes-agent", "provider": "fixture", "name": "Fixture model (no inference)"}]})

    async def advance(request):
        body = await request.json()
        sid = body.get("session_id")
        if sid not in state.chats:
            return web.json_response({"error": "unknown fixture chat"}, status=404)
        await state.advance(sid)
        return web.json_response({"ok": True, "running": state.chats[sid]["running"]})

    async def status(_):
        return web.json_response({"fixture": True, "submit_count": state.submit_count, "connection_count": state.connection_count, "disconnect_count": state.disconnect_count, "open_sockets": len(state.sockets), "chats": [state.summary(c) for c in state.chats.values()]})

    app.router.add_get("/health", health)
    app.router.add_post("/auth/password-login", login)
    app.router.add_post("/api/auth/ws-ticket", ticket)
    app.router.add_get("/api/ws", rpc_socket)
    app.router.add_get("/api/sessions", sessions)
    app.router.add_get("/api/sessions/{sid}/messages", messages)
    app.router.add_get("/api/sessions/{sid}", detail)
    app.router.add_get("/v1/models", models)
    app.router.add_post("/test/advance", advance)
    app.router.add_get("/test/status", status)
    return app


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18643)
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()
    web.run_app(create_app(SmokeState(args.log)), host="127.0.0.1", port=args.port)
