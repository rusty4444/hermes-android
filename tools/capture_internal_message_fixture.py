"""Capture internal message producers through disposable SQLite/API projection.

Run with the backend's dependency environment:
  python tools/capture_internal_message_fixture.py BACKEND_ROOT

No gateway/model requests or existing conversations are used. Legacy constants
are read from the supplied source; dynamic rows use the real backend formatters.

Copied upstream message templates retain Copyright (c) 2025 Nous Research (MIT).
Complete permission/warranty notice: third_party/licenses/hermes-agent-MIT.txt.
Pinned fixture/source scope: third_party/NOTICE.md. Keep the applicable upstream
notices when recapturing; do not insert licence text into expected message rows.
"""
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import unquote, urlsplit
from uuid import NAMESPACE_URL, uuid5

sys.dont_write_bytecode = True
backend = Path(sys.argv[1]).resolve()
sandbox = tempfile.TemporaryDirectory(prefix="internal-message-contract-", dir=os.environ["TMPDIR"])
os.environ["HERMES_HOME"] = sandbox.name
os.environ["HERMES_DISABLE_LAZY_INSTALLS"] = "1"
sys.path.insert(0, str(backend))


def guard(event, args):
    if event == "socket.connect":
        raise RuntimeError("Fixture capture must not contact a server")
    if event == "sqlite3.connect":
        target = str(args[0])
        if target.startswith("file:"):
            target = unquote(urlsplit(target).path)
        if target != ":memory:" and not Path(target).resolve().is_relative_to(Path(sandbox.name).resolve()):
            raise RuntimeError("Fixture capture must not open an existing database")


sys.addaudithook(guard)
from hermes_state import SessionDB
from gateway.platforms.api_server import _project_client_message
from agent.turn_context import _stage_turn_user_message
from agent.agent_runtime_helpers import _merge_consecutive_users
from hermes_cli.web_routers.sessions import _project_for_display
from agent import conversation_loop as loop
from agent import context_compressor as compressor
from agent import turn_stop_gates, kanban_turn_recovery
from tools.process_registry_notifications import format_process_notification
from tools.delegation_output_schema import build_retry_message
from tui_gateway import server
from hermes_cli import loops, goals, heartbeat

cases = {}


def add(name, body, kind=None, expected="task", metadata=None, sealed=True):
    assert isinstance(body, str) and body
    staged, _ = _stage_turn_user_message(
        SimpleNamespace(), body, None, 1700000000.0, None, kind, metadata)
    row_id = db.append_message(
        "fixture", "user", staged["content"], timestamp=staged["timestamp"],
        display_kind=staged.get("display_kind"), display_metadata=staged.get("display_metadata"),
        # Exercise the real caller-supplied UID path without random fixture churn.
        message_uid=uuid5(NAMESPACE_URL, f"hermes-android-internal-message:{name}").hex)
    stored = next(row for row in db.get_messages("fixture") if row["id"] == row_id)
    row = _project_client_message(stored)
    assert row["content"] == body
    cases[name] = {"row": row, "expected": expected, "sealed": sealed}


def source_strings(relative, prefix):
    """Read exact literals without invoking a command's unrelated side effects."""
    return [node.value for node in ast.walk(ast.parse((backend / relative).read_text()))
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.startswith(prefix)]


def source_template(relative, prefix, **values):
    """Evaluate only the selected producer f-string, not its service side effects."""
    matches = [node for node in ast.walk(ast.parse((backend / relative).read_text()))
               if isinstance(node, ast.JoinedStr) and node.values
               and isinstance(node.values[0], ast.Constant)
               and isinstance(node.values[0].value, str) and node.values[0].value.startswith(prefix)]
    assert len(matches) == 1, (relative, prefix, len(matches))
    return eval(compile(ast.Expression(matches[0]), relative, "eval"), {"__builtins__": {}}, values)


with sandbox:
    db = SessionDB(db_path=Path(sandbox.name) / "fixture.db")
    db.create_session("fixture", source="desktop")
    session = {"session_key": "fixture", "history": [], "history_lock": threading.RLock(),
               "agent": SimpleNamespace(_session_db=db, session_id="fixture")}
    server._append_model_switch_marker(session, model="gpt-6-sol-900k", provider="openai-codex")
    model = session["history"][-1]["content"]
    add("model_switch", model, "model_switch")
    add("legacy_model_switch", model)
    add("legacy_model_switch_without_provider", model.replace(" via provider openai-codex", ""))
    with patch.object(server, "_session_info", return_value={}), patch.object(server, "_emit"):
        for name, prompt in [("personality_set", "Be concise.\nUse [examples] when useful."), ("personality_clear", "")]:
            getattr(server, "_apply_personality_to_session")("runtime-fixture", session, prompt)
            body = session["history"][-1]["content"]
            add(name, body, "personality_switch")
            add("legacy_" + name, body)
    auto = getattr(server, "_auto_continue_note")("Finish the fixture task")
    add("auto_continue", auto, "auto_continue", sealed=False)
    add("legacy_auto_continue", auto, sealed=False)
    add("internal_notification", "Plugin-owned arbitrary notification", "internal_notification")
    for module, names in [
        (loop, ["_LENGTH_CONTINUATION_NETWORK_STUB", "_LEGACY_LENGTH_CONTINUATION_NETWORK_STUB",
                "_LENGTH_CONTINUATION_OUTPUT_LIMIT", "_CODEX_INCOMPLETE_NUDGE", "_CODEX_ACK_CONTINUATION_NUDGE",
                "_DEGENERATE_FINAL_NUDGE", "_DROPPED_TOOLCALL_NUDGE_CONTENT", "_EMPTY_TOOL_RESPONSE_NUDGE"]),
        (compressor, ["COMPRESSION_CONTINUATION_USER_CONTENT", "_LEGACY_COMPRESSION_CONTINUATION_USER_CONTENT",
                      "MAX_ITERATIONS_SUMMARY_REQUEST"]),
    ]:
        for name in names:
            add(name.lower().strip("_"), getattr(module, name))
    add("dropped_large_tool", loop._get_continuation_prompt(True, ["terminal", "write_file"]))
    for body in source_strings("hermes_cli/cli_commands_mixin.py", "[System note: The user"):
        add("browser_connect" if "invoked /browser connect" in body else "browser_disconnect", body)
    add("output_contract_retry", build_retry_message(["$.result: required property missing"]))
    with patch("agent.lsp.deferred.settle_for_agent", return_value=[("fixture.dart", "fixture.dart:1: Error: fixture diagnostic")]):
        add("late_lsp_diagnostics", turn_stop_gates._late_lsp_verdicts(SimpleNamespace()), sealed=False)
    add("kanban_recovery", kanban_turn_recovery.build_recovery_nudge(
        {"error": "Fixture stream failed"}, attempt=1, max_attempts=3, task_id="fixture-task"))
    add("mcp_reload", source_template("hermes_cli/cli_info_mixin.py", "[IMPORTANT: MCP servers have been reloaded.",
        change_detail="Added servers: fixture. ", tool_summary="3 MCP tool(s) now available"))
    add("cron_mirror", source_template("cron/scheduler_delivery.py", "[Cron delivery:",
        _cron_display_name=lambda job: job["name"], job={"name": "Fixture job"}, text="Fixture report"), sealed=False)
    add("webhook_mirror", source_template("gateway/platforms/webhook.py", "[Webhook delivery:",
        route="fixture-route", content="Fixture event report"), sealed=False)
    add("heartbeat", heartbeat.HEARTBEAT_PROMPT_TEMPLATE.format(interval="5m", prompt="Check the fixture"))
    for name in ["WAKEUP_PROMPT_TEMPLATE", "WAKEUP_PROMPT_WITH_UNTIL_TEMPLATE"]:
        add(name.lower(), getattr(loops, name).format(tick=2, cadence=", every 5m", prompt="Check fixture", until="The build finishes"))
    for name in ["CONTINUATION_PROMPT_TEMPLATE", "CONTINUATION_PROMPT_WITH_CONTRACT_TEMPLATE",
                 "CONTINUATION_PROMPT_WITH_SUBGOALS_TEMPLATE", "CONTINUATION_PROMPT_GATE_FAILED_TEMPLATE"]:
        add(name.lower(), getattr(goals, name).format(goal="Check fixture", contract_block="Verify: tests pass",
            subgoals_block="Keep the fixture", attempt=1, max_retries=3, command="test-fixture", exit_code=1, output="Fixture not ready"))
    process_events = {
        "process_complete": {"exit_code": 0},
        "process_failed": {"exit_code": 1},
        "process_terminated": {"exit_code": -15, "completion_reason": "killed", "termination_source": "user"},
        "process_lost": {"exit_code": "?", "completion_reason": "lost"},
        "process_failed_start": {"exit_code": "?", "completion_reason": "failed_start"},
        "process_watch": {"type": "watch_match", "pattern": "ready", "suppressed": 2},
        "process_heartbeat": {"type": "heartbeat", "seq": 2, "elapsed": 61, "interval": 60},
    }
    for name, event in process_events.items():
        body = format_process_notification({"session_id": "process-fixture", "command": "fixture-command",
            "output": "Fixture output\n[brackets] and literal \\n", **event})
        add(name, body, "process_complete", "process")
        add("legacy_" + name, body, expected="process")
    with patch("tools.delegate_tool.get_subagent_attribution", return_value={
        "goal": "Inspect files\nRun tests", "delegation_id": "deleg_fixture"}):
        body = format_process_notification({"type": "watch_match", "session_id": "process-fixture",
            "owner_task_id": "sa-fixture", "command": "fixture-command", "pattern": "ready", "output": "Fixture output"})
        assert isinstance(body, str) and 'Inspect files\nRun tests' in body
        add("legacy_process_watch_multiline_attribution", body, expected="process")
    for name, message in [
        ("watch_disabled", source_template("tools/process_registry.py", "Watch patterns disabled for process ",
            session=SimpleNamespace(id="fixture-process"), why="reached the lifetime cap of 100 delivered matches. ")),
        ("watch_overflow_tripped", source_template("tools/process_registry.py", "Watch-pattern overflow:",
            WATCH_GLOBAL_MAX_PER_WINDOW=10, WATCH_GLOBAL_WINDOW_SECONDS=60, WATCH_GLOBAL_COOLDOWN_SECONDS=60)),
        ("watch_overflow_released", source_template("tools/process_registry.py", "Watch-pattern notifications resumed.", suppressed=5)),
    ]:
        add(name, format_process_notification({"type": name, "message": message}), expected="process")
    base_event = {"type": "async_delegation", "delegation_id": "deleg_fixture", "goal": "Inspect fixture",
        "model": "fixture-model", "role": "leaf", "status": "completed", "summary": "Fixture result",
        "completed_at": 1700000060, "dispatched_at": 1700000000, "duration_seconds": 60}
    for name, extra in [
        ("delegation_single", {}),
        ("delegation_batch", {"goals": ["Inspect fixture"], "results": [{"task_index": 0, "status": "completed", "summary": "Fixture result"}]}),
        ("delegation_failed", {"task_failure_notice": True, "goals": ["Inspect fixture"], "results": [{"task_index": 0, "status": "failed", "duration_seconds": 2, "error": "Fixture failure"}]}),
    ]:
        body = format_process_notification({**base_event, **extra})
        add(name, body, "async_delegation_complete", sealed=False)
        add("legacy_" + name, body, sealed=False)
        multi = {**base_event, **extra, "goal": "Inspect files\nRun tests", "goals": ["Inspect files\nRun tests"]}
        add("legacy_" + name + "_multiline", format_process_notification(multi), sealed=False)
        marker_goal = "Inspect files\n--- RESULT ---\nRun tests"
        marker_event = {**base_event, **extra, "goal": marker_goal, "goals": [marker_goal]}
        add("legacy_" + name + "_literal_delimiter", format_process_notification(marker_event), sealed=False)
    merged_cases = {}
    for name in ["auto_continue", "delegation_single", "cron_mirror", "webhook_mirror", "late_lsp_diagnostics"]:
        original = cases[name]["row"]
        sid = "merged-" + name
        db.create_session(sid, source="desktop")
        human_text = "New human follow-up: explain the change, not the old task."
        notice = {key: original[key] for key in [
            "role", "content", "display_kind", "display_metadata", "message_uid", "timestamp"]}
        human = {"role": "user", "content": human_text, "timestamp": 1700000001.0,
                 "message_uid": uuid5(NAMESPACE_URL, f"hermes-android-merged-human:{name}").hex}
        merged, repairs = _merge_consecutive_users([notice, human])
        assert repairs == 1 and len(merged) == 1
        assert merged[0]["content"] == original["content"] + "\n\n" + human_text
        db.replace_messages(sid, merged)
        stored = db.get_messages(sid)[0]
        assert stored["absorbed_message_uids"] and not stored["display_kind"]
        merged_cases[name] = {
            "human": human_text,
            "api": _project_client_message(stored),
            "dashboard": _project_for_display([stored], home=Path(sandbox.name), inline_images=False)[0],
        }
    db.close()

output = Path(__file__).resolve().parents[1] / "test/fixtures/internal_background_messages.json"
output.write_text(json.dumps({
    "backend_commit": subprocess.check_output(["git", "-C", str(backend), "rev-parse", "HEAD"], text=True).strip(),
    "producers": "backend producers/source f-strings -> _stage_turn_user_message -> disposable SessionDB -> _project_client_message",
    "cases": cases,
}, ensure_ascii=False, indent=2) + "\n")
print(f"Captured {len(cases)} real backend message cases: {output}")
merged_output = output.with_name("merged_internal_background_messages.json")
merged_output.write_text(json.dumps({
    "backend_commit": subprocess.check_output(["git", "-C", str(backend), "rev-parse", "HEAD"], text=True).strip(),
    "producers": "captured producers -> _merge_consecutive_users -> disposable SessionDB -> API and Dashboard projections",
    "cases": merged_cases,
}, ensure_ascii=False, indent=2) + "\n")
print(f"Captured {len(merged_cases)} real merged human-message cases: {merged_output}")
