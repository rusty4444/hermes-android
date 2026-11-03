"""Capture real LCM context assembly and persisted public projections offline.

Run in the backend dependency environment:
  python tools/capture_lcm_summary_fixture.py BACKEND_ROOT LCM_ROOT

Synthetic DAG content only; no inference, network, or existing databases.
"""
import hashlib
import importlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
from urllib.parse import unquote, urlsplit
from uuid import NAMESPACE_URL, uuid5

sys.dont_write_bytecode = True
backend, plugin = (Path(arg).resolve() for arg in sys.argv[1:3])
sandbox = tempfile.TemporaryDirectory(prefix="lcm-summary-contract-", dir=os.environ["TMPDIR"])
home = Path(sandbox.name).resolve()
os.environ["HERMES_HOME"] = str(home)
os.environ["HERMES_DISABLE_LAZY_INSTALLS"] = "1"
sys.path.insert(0, str(backend))


def guard(event, args):
    if event == "socket.connect":
        raise RuntimeError("Fixture capture must not contact a server")
    if event == "sqlite3.connect":
        target = str(args[0])
        if target.startswith("file:"):
            target = unquote(urlsplit(target).path)
        if target != ":memory:" and not Path(target).resolve().is_relative_to(home):
            raise RuntimeError("Fixture capture must not open an existing database")


sys.addaudithook(guard)
# Import submodules without invoking the plugin registration entrypoint.
package = types.ModuleType("hermes_lcm")
package.__path__ = [str(plugin)]
sys.modules[package.__name__] = package
LCMEngine = importlib.import_module("hermes_lcm.engine").LCMEngine
LCMConfig = importlib.import_module("hermes_lcm.config").LCMConfig
SummaryNode = importlib.import_module("hermes_lcm.dag").SummaryNode
from hermes_state import SessionDB
from gateway.platforms.api_server import _project_client_message
from hermes_cli.web_routers.sessions import _project_for_display

cases = {}
with sandbox:
    engine = LCMEngine(config=LCMConfig(database_path=str(home / "lcm.db")), hermes_home=str(home))
    db = SessionDB(db_path=home / "fixture.db")
    try:
        engine.context_length = 200000
        engine.threshold_tokens = 180000
        for name, depths, leading_role, anchor in [
            ("recent", [0], "system", False),
            ("session_arc", [1], "system", False),
            ("durable", [2], "system", False),
            ("deep", [12], "system", False),
            ("grouped", [0, 1, 2, 3], "system", False),
            ("user_role", [1], "assistant", False),
            ("objective_and_summaries", [0, 1], "system", True),
            ("large_session_arc", [1], "system", False),
        ]:
            engine._session_id = name
            db.create_session(name, source="desktop")
            for depth in depths:
                summary = "# Current objective\n\nSynthetic fixture: preserve ongoing work.\n"
                if name == "large_session_arc":
                    summary += "Retained detail: paths, tests and approvals.\n" * 800
                summary += "\nLiteral delimiter in the summary:\n\n---\n\nStill summary content.\nEND_OF_SYNTHETIC_SUMMARY"
                engine._dag.add_node(SummaryNode(
                    session_id=name, depth=depth, summary=summary,
                    created_at=1700000000.0, expand_hint="Synthetic [fixture] details" if depth else ""))
            engine._pending_context_anchor_messages = (
                [{"role": "user", "content": "Keep the synthetic objective."}] if anchor else None)
            assembled = engine._assemble_context(
                {"role": leading_role, "content": "Fixture anchor"}, [], include_lcm_note=False)
            assert len(assembled) == 2
            summary_row = assembled[1]
            db.append_message(
                name, summary_row["role"], summary_row["content"], timestamp=1700000000.0,
                message_uid=uuid5(NAMESPACE_URL, f"hermes-android-lcm:{name}").hex)
            stored = db.get_messages(name)[0]
            api = _project_client_message(stored)
            dashboard = _project_for_display([stored], home=home, inline_images=False)[0]
            assert api["content"] == dashboard["content"] == summary_row["content"]
            cases[name] = {"api": api, "dashboard": dashboard}
    finally:
        db.close()
        engine.shutdown()

output = Path(__file__).resolve().parents[1] / "test/fixtures/lcm_summary_messages.json"
output.write_text(json.dumps({
    "backend_commit": subprocess.check_output(["git", "-C", str(backend), "rev-parse", "HEAD"], text=True).strip(),
    "lcm_commit": subprocess.check_output(["git", "-C", str(plugin), "rev-parse", "HEAD"], text=True).strip(),
    "lcm_engine_sha256": hashlib.sha256((plugin / "engine.py").read_bytes()).hexdigest(),
    "producers": "synthetic SummaryNode -> real LCMEngine._assemble_context -> disposable SessionDB -> API and Dashboard projection functions (not HTTP routes)",
    "cases": cases,
}, ensure_ascii=False, indent=2) + "\n")
print(f"Captured {len(cases)} LCM assembly cases: {output}")
