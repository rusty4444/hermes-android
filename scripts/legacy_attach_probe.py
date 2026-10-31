#!/usr/bin/env python3
"""Verify the LEGACY (stock-gateway) attach path end-to-end on a real tui_gateway.

Mirrors chat_screen._sendDesktopGatewayMessage on _legacyTransportFallback:
  session.create -> file.attach(real sid) -> prompt.submit
"""
import json, os, subprocess, sys, tempfile, time, base64, select, uuid

REPO = os.path.expanduser("~/.hermes/hermes-agent")
tmp_home = tempfile.mkdtemp(prefix="legacy_attach_")
open(os.path.join(tmp_home, "config.yaml"), "w").write("model:\n  default: probe-model\n")
env = dict(os.environ, HERMES_HOME=tmp_home)
proc = subprocess.Popen(
    [os.path.join(REPO, "venv/bin/python"), "-m", "tui_gateway.entry"],
    cwd=REPO, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL, text=True)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n"); proc.stdin.flush()

def read_id(rid, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([proc.stdout], [], [], 1)
        if r:
            line = proc.stdout.readline()
            if not line: return None
            try: msg = json.loads(line)
            except json.JSONDecodeError: continue
            if msg.get("id") == rid: return msg
    return None

try:
    # wait ready
    deadline = time.time() + 40
    ready = None
    while time.time() < deadline and ready is None:
        r, _, _ = select.select([proc.stdout], [], [], 1)
        if r:
            line = proc.stdout.readline()
            if not line: break
            try: msg = json.loads(line)
            except json.JSONDecodeError: continue
            if msg.get("method") == "event" and msg.get("params", {}).get("type") == "gateway.ready":
                ready = msg
    if not ready: print("FAIL no ready"); sys.exit(1)

    # 1. session.create (what the client does for a new chat)
    send({"jsonrpc": "2.0", "id": 1, "method": "session.create",
          "params": {"source": "android"}})
    r = read_id(1)
    print("session.create ->", json.dumps(r.get("error") or r.get("result"))[:400])
    res = r.get("result") or {}
    sid = res.get("session_id") or (res.get("info") or {}).get("session_id")
    if not sid:
        print("no session_id in create result; keys:", sorted(res.keys())); sys.exit(1)

    # 2. file.attach with the REAL sid (legacy attach path)
    png = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4"
           "2mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    send({"jsonrpc": "2.0", "id": 2, "method": "file.attach",
          "params": {"session_id": sid, "name": "probe.png", "path": "",
                    "data_url": "data:image/png;base64," + png}})
    r = read_id(2)
    print("file.attach(real sid) ->", json.dumps(r.get("error") or r.get("result"))[:400])

    # 3. prompt.submit referencing the attachment (no model call needed to fail?
    #    model is fake so the turn will error — we only care the RPC is accepted)
    send({"jsonrpc": "2.0", "id": 3, "method": "prompt.submit",
          "params": {"session_id": sid, "text": "describe [Attached file: probe.png]"}})
    r = read_id(3, timeout=20)
    print("prompt.submit accepted ->", json.dumps(r.get("error") or r.get("result"))[:300])
finally:
    proc.terminate()
    try: proc.wait(timeout=10)
    except subprocess.TimeoutExpired: proc.kill()
