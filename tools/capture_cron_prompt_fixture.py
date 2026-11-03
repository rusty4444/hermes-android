"""Capture scheduled prompts without running jobs, skills, models or a gateway.

Use the backend dependency environment:
  python tools/capture_cron_prompt_fixture.py BACKEND_ROOT

The legacy case reproduces the pre-instruction-marker assembly reported by the
user, using the real skill-block producer. The current cases use _build_job_prompt.
All data is synthetic; no private job prompt or skill body is included.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch
from urllib.parse import unquote, urlsplit
from uuid import NAMESPACE_URL, uuid5

sys.dont_write_bytecode = True
backend = Path(sys.argv[1]).resolve()
sandbox = tempfile.TemporaryDirectory(prefix="cron-prompt-contract-", dir=os.environ["TMPDIR"])
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
from cron import scheduler_prompt
from gateway.platforms.api_server import APIServerAdapter
from hermes_cli.web_routers.sessions import _project_for_display
from hermes_state import SessionDB


def skill(name):
    return json.dumps({
        "success": True,
        "name": name,
        "content": f"---\nname: {name}\ndescription: Synthetic fixture skill.\n---\n\n# Fixture skill\nKeep literal \\n and [brackets].",
    })


cases = {}
with sandbox, patch("tools.skills_tool.skill_view", side_effect=skill), patch("tools.skill_usage.bump_use"):
    home = Path(sandbox.name)
    db = SessionDB(db_path=home / "fixture.db")
    job = {"id": "fixture", "name": "Fixture job", "skills": ["fixture-one", "fixture-two"],
           "prompt": "Inspect the synthetic fixture and report the result."}
    runtime = "## Monitor Baseline (first run)\n\n### Current output\n\n```\nFixture data\n```"
    skill_parts = scheduler_prompt._load_cron_skill_parts(job, job["skills"])
    legacy = "\n".join([*skill_parts, "", job["prompt"], "", "## Run Context", runtime])
    prompts = {
        "legacy_skills": ("cron_fixture_20261014_213510", legacy),
        "current_skills": ("local-fixture-skills", scheduler_prompt._build_job_prompt(job, runtime_data_prompt=runtime)),
        "current_plain": ("local-fixture-plain", scheduler_prompt._build_job_prompt({**job, "skills": []})),
    }
    for name, (session_id, body) in prompts.items():
        db.create_session(session_id, source="cron")
        db.append_message(session_id, "user", body, timestamp=1700000000.0,
                          message_uid=uuid5(NAMESPACE_URL, f"hermes-android-cron-prompt:{name}").hex)
        stored = db.get_messages(session_id)[0]
        api = APIServerAdapter._message_response(stored)
        dashboard = _project_for_display([stored], home=home, inline_images=False)[0]
        assert api["content"] == dashboard["content"] == body
        assert api["session_id"] == session_id and not api.get("display_kind")
        cases[name] = {"session_source": "cron", "api": api, "dashboard": dashboard}
    db.close()

output = Path(__file__).resolve().parents[1] / "test/fixtures/cron_task_prompts.json"
output.write_text(json.dumps({
    "backend_commit": subprocess.check_output(["git", "-C", str(backend), "rev-parse", "HEAD"], text=True).strip(),
    "producers": "real cron skill-block producer (historical assembly reconstruction) / current _build_job_prompt -> disposable SessionDB -> complete API message serializer and Dashboard projection, not HTTP routes",
    "cases": cases,
}, ensure_ascii=False, indent=2) + "\n")
print(f"Captured {len(cases)} synthetic scheduled prompt cases: {output}")
