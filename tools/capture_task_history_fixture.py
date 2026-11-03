"""Capture stock Dashboard contracts in an isolated disposable SessionDB.

Run with the backend's Python: python tools/capture_task_history_fixture.py BACKEND_ROOT.
No server is contacted and no existing profile or conversation is modified.
"""
import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch
from types import SimpleNamespace
from typing import cast

# Establish an isolated home before importing any backend module: rotation can
# carry per-session state and must never inspect the operator's profile.
sandbox = tempfile.TemporaryDirectory(prefix="task-history-contract-", dir=os.environ["TMPDIR"])
os.environ["HERMES_HOME"] = sandbox.name
os.environ["HERMES_SESSION_PROFILE"] = "fixture"
backend = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(backend))
# Use the supplied interpreter's installed dependencies, not the application's
# launcher/update lifecycle. The fixture must not run checkout maintenance.
with patch("hermes_cli.venv_sync.prepare_launch", return_value=None), \
     patch("pm.environments.activate_dependencies"), \
     patch("hermes_cli._early_recovery.recover_if_needed"), \
     patch("hermes_cli._early_recovery.restore_interrupted_pull", return_value=False):
    import hermes_bootstrap  # noqa: F401
from hermes_state import SessionDB  # noqa: E402
from hermes_cli.web_routers import sessions  # noqa: E402
from tools import delegate_tool_registry as registry  # noqa: E402
from agent import conversation_compression as cc  # noqa: E402
from agent.delegation_context import delegated_child_context  # noqa: E402


async def capture(home):
    db = SessionDB(db_path=home / "fixture.db")
    db.create_session("parent-chat", source="cli", profile_name="fixture")
    db.append_message("parent-chat", "assistant", "PARENT transcript must not leak")
    db.create_session("stored-child", source="subagent", profile_name="fixture",
                      parent_session_id="parent-chat", model_config={"_delegate_from": "parent-chat"})
    db.append_message("stored-child", "user", "Inspect the fixture")
    db.append_message("stored-child", "assistant", "", reasoning="Archived exposed reasoning",
                      tool_calls=[{"id": "archived-call", "type": "function", "function": {
                          "name": "terminal", "arguments": '{"command":"pwd"}'}}])
    db.append_message("stored-child", "tool", "Archived tool result", tool_call_id="archived-call")
    db.append_message("stored-child", "assistant", "Before compaction")
    db.append_message("stored-child", "user", "Continue")
    db.append_message("stored-child", "assistant", "Tail answer")
    tail = db.get_messages("stored-child")[-2:]
    db.archive_and_compact("stored-child", [{"role": "user", "content": "[summary]"}, *tail], tail_count=2)
    commentary = {"type": "message", "role": "assistant", "phase": "commentary",
                  "content": [{"type": "output_text", "text": "Public progress"}]}
    db.append_message("stored-child", "assistant", "", reasoning="Public progress\n\nExposed reasoning",
                      codex_message_items=[commentary],
                      codex_reasoning_items=[{"summary": [{"type": "summary_text", "text": "Exposed reasoning"}]}])
    def rotate(child, tip, cfg):
        agent = SimpleNamespace(
            _session_db=db, session_id=child, platform="subagent", model="fixture-model",
            _session_init_model_config=cfg, working_directory=None,
            _memory_manager=None, context_compressor=SimpleNamespace(),
            _flush_messages_to_session_db=lambda *a, **k: None,
            _persist_user_message_idx=None, _session_messages=None,
            _gateway_session_key=None, _cached_system_prompt="fixture-system",
        )
        with patch.object(cc, "mint_session_id", return_value=tip), delegated_child_context(child):
            cc._publish_rotated_compaction(
                agent, db.get_messages(child), [{"role": "user", "content": "[handoff]"}],
                new_system_prompt="fixture-system",
                lease=cast(cc._CompressionLease, SimpleNamespace(holder=None, ttl=60.0, watermark=None)),
                old_session_id=child, compressed_user_turn_outcome="none",
            )
        assert agent.session_id == tip

    rotate("stored-child", "compression-tip", {"_delegate_from": "parent-chat"})
    db.append_message("compression-tip", "assistant", "After rotation")
    for source in ["subagent", "tool"]:
        parent, child, tip = f"parent-{source}", f"child-{source}", f"tip-{source}"
        cfg = {"max_iterations": 50, "_delegate_from": parent}
        db.create_session(parent, source="desktop", profile_name="fixture")
        db.append_message(parent, "assistant", "PARENT PRIVATE: must not cross delegation boundary")
        db.create_session(child, source=source, profile_name="fixture",
                          parent_session_id=parent, model_config=cfg)
        db.append_message(child, "user", "Child task")
        db.append_message(child, "assistant", "BEFORE rotation")
        rotate(child, tip, cfg)
        db.append_message(tip, "assistant", "AFTER rotation: actual child completion")
    db.create_session("missing-child-longer", source="cli", profile_name="fixture")
    db.append_message("missing-child-longer", "assistant", "FOREIGN transcript")

    async def messages(sid, compacted):
        return await sessions.get_session_messages(sid, profile="fixture", limit=50, offset=0,
                                                  order="latest", include_compacted=compacted, inline_images=False)

    try:
        with patch.object(sessions, "_with_db", lambda profile, fn, **kwargs: fn(db)), \
             patch.object(sessions, "_serving_profile", lambda profile: profile), \
             patch.object(sessions, "_history_profile_home", lambda profile: home), \
             patch("hermes_cli.config.load_config", return_value={"display": {"show_commentary": True}}):
            result = {"backend_commit": subprocess.check_output(["git", "-C", str(backend), "rev-parse", "HEAD"], text=True).strip(),
                      "detail": await sessions.get_session_detail("stored-child", profile="fixture"),
                      "tip_detail": await sessions.get_session_detail("compression-tip", profile="fixture"),
                      "tip_messages": await messages("compression-tip", True),
                      "prefix_detail": await sessions.get_session_detail("missing-child", profile="fixture"),
                      "without_compacted": await messages("stored-child", False),
                      "with_compacted": await messages("stored-child", True),
                      "prefix_messages": await messages("missing-child", True)}
            result["rotations"] = {}
            for source in ["subagent", "tool"]:
                child, tip = f"child-{source}", f"tip-{source}"
                result["rotations"][source] = {
                    "detail": await sessions.get_session_detail(child, profile="fixture"),
                    "tip_detail": await sessions.get_session_detail(tip, profile="fixture"),
                    "original_page": await messages(child, True),
                    "tip_page": await messages(tip, True),
                    "latest_descendant": await sessions.get_session_latest_descendant(child, profile="fixture"),
                }
            # Exercise the actual listing route on a disposable DB. Disable its
            # auto-archive hook and reopen only this fixture read-only. This is
            # evidence about discovery, NOT a production polling strategy.
            with patch.object(sessions, "_maybe_auto_archive_for_profile", lambda *a: None), \
                 patch.object(sessions, "_open_session_db_for_profile", lambda *a, **k: SessionDB(db_path=home / "fixture.db", read_only=True)), \
                 patch.object(sessions, "_cron_profile_home", lambda p: (p, home)):
                result["source_scoped_listing"] = sessions.get_sessions(
                    limit=100, offset=0, min_messages=0, archived="include", order="created",
                    sources="subagent,tool", full=True, profile="fixture")
            with patch("hermes_cli.config.load_config", return_value={"display": {"show_commentary": False}}):
                result["commentary_disabled"] = await messages("stored-child", True)
        with patch.dict(registry._active_subagents, {"runtime": {"subagent_id": "runtime"}}, clear=True), \
             patch.object(registry, "_owns_subagent_record", return_value=True), \
             patch.object(registry, "steer_subagent", return_value=True), \
             patch.object(registry, "interrupt_subagent", return_value=True):
            result["steer_ack"] = json.loads(registry._handle_control_action("steer", "runtime", "Keep going", None))
            result["stop_ack"] = json.loads(registry._handle_control_action("stop", "runtime", None, None))
        archived = result["with_compacted"]["messages"]
        assert any(m.get("content") == "Archived tool result" for m in archived)
        assert not any("PARENT transcript" in (m.get("content") or "") for m in archived)
        assert not any(m.get("content") == "Archived tool result" for m in result["without_compacted"]["messages"])
        assert result["prefix_detail"]["id"] == "missing-child-longer"
        assert result["with_compacted"]["session_id"] == "stored-child"
        for source, scenario in result["rotations"].items():
            assert scenario["original_page"]["session_id"] == f"child-{source}"
            assert scenario["latest_descendant"]["session_id"] == f"child-{source}"
            assert scenario["tip_detail"]["source"] == source
            assert json.loads(scenario["tip_detail"]["model_config"])["_delegate_from"] == f"parent-{source}"
        return result
    finally:
        db.close()


with sandbox as directory:
    captured = asyncio.run(capture(Path(directory)))
output = Path(__file__).resolve().parents[1] / "test/fixtures/delegated_task_dashboard.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(captured, ensure_ascii=False, indent=2) + "\n")
print(f"Captured actual Dashboard detail/messages, compacted history, prefix resolution and control ACKs: {output}")
