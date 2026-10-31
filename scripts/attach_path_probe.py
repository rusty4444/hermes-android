#!/usr/bin/env python3
"""Replay the Android client's attach-path frames against a spawned real tui_gateway.

Mirrors GatewayTurnCoordinator._openFreshTransport + stageAttachment:
  1. WS connect -> gateway.ready frame (inspect protocol/capabilities)
  2. session.open {mobile_session_id}
  3. image.attach_bytes {session_id, content_base64, filename}
  4. attachment.detach {session_id, version, attachment_id}
Prints each RPC's error code/message verbatim.
"""
import json, os, subprocess, sys, tempfile, time, base64, uuid

REPO = os.path.expanduser("~/.hermes/hermes-agent")
tmp_home = tempfile.mkdtemp(prefix="attach_probe_")
# seed minimal config so the gateway boots
open(os.path.join(tmp_home, "config.yaml"), "w").write("model:\n  default: probe-model\n")

env = dict(os.environ, HERMES_HOME=tmp_home)
proc = subprocess.Popen(
    [os.path.join(REPO, "venv/bin/python"), "-m", "tui_gateway.entry"],
    cwd=REPO, env=env,
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    text=True,
)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

def read_until(pred, timeout=25):
    deadline = time.time() + timeout
    import select
    while time.time() < deadline:
        r, _, _ = select.select([proc.stdout], [], [], 1)
        if r:
            line = proc.stdout.readline()
            if not line:
                return None
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if pred(msg):
                return msg
    return None

try:
    # 1. gateway.ready
    ready = read_until(lambda m: m.get("method") == "event"
                      and m.get("params", {}).get("type") == "gateway.ready", 40)
    if ready is None:
        print("FAIL: no gateway.ready frame"); sys.exit(1)
    payload = ready["params"].get("payload", {})
    print("gateway.ready payload keys:", sorted(payload.keys()))
    print("  has 'protocol':", "protocol" in payload)
    print("  has 'capabilities':", "capabilities" in payload)

    # 2. session.open (durable-turn coordinator path)
    mob = str(uuid.uuid4())
    send({"jsonrpc": "2.0", "id": 1, "method": "session.open",
          "params": {"mobile_session_id": mob}})
    r = read_until(lambda m: m.get("id") == 1)
    print("session.open ->", json.dumps(r.get("error", r.get("result")))[:300])

    # 3. image.attach_bytes (coordinator image path)
    png = base64.b64encode(bytes.fromhex(
        "89504e470d0a1a0a0000000d494844520000000100000001080600000"
        "01f15c4890000000a49444154789c63000100000500010d0a2db40000"
        "000049454e44ae426082")).decode()
    send({"jsonrpc": "2.0", "id": 2, "method": "image.attach_bytes",
          "params": {"session_id": mob, "content_base64": "iVBORw0KGgo=" + png[8:],
                    "filename": "probe.png"}})
    r = read_until(lambda m: m.get("id") == 2)
    print("image.attach_bytes ->", json.dumps(r.get("error", r.get("result")))[:300])

    # 4. attachment.detach (coordinator detach path)
    send({"jsonrpc": "2.0", "id": 3, "method": "attachment.detach",
          "params": {"session_id": mob, "version": 2, "attachment_id": "att-1"}})
    r = read_until(lambda m: m.get("id") == 3)
    print("attachment.detach ->", json.dumps(r.get("error", r.get("result")))[:300])

    # 5. file.attach (plain path, expected OK)
    send({"jsonrpc": "2.0", "id": 4, "method": "file.attach",
          "params": {"session_id": mob, "name": "probe.png", "path": "",
                    "data_url": "data:image/png;base64," + png}})
    r = read_until(lambda m: m.get("id") == 4)
    print("file.attach ->", json.dumps(r.get("error", r.get("result")))[:300])
finally:
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
