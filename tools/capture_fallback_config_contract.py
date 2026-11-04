"""Capture real FastAPI config capabilities and the older ignored-query trap.

Run with a backend interpreter (FastAPI/httpx installed), from the Android root:
  python tools/capture_fallback_config_contract.py BACKEND_ROOT

Current schema: actual imported config_router. Older schema/HTTP handler and
save-template transform: AST-extracted verbatim from the pinned Git revision.
The config-loader/thread/profile seams are bounded fake data, NOT persistence
or authentication coverage. All sockets are forbidden; no live config is read.
"""
import ast
import asyncio
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any, Dict, Optional


OLD_REVISION = "5d2d5e906d62e326e600855277403b8595325b38"
backend = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="fallback-contract-", dir=os.environ["TMPDIR"]) as home:
    os.environ["HERMES_HOME"] = home
    os.environ["HOME"] = home
    os.environ["HERMES_DISABLE_LAZY_INSTALLS"] = "1"
    sys.path.insert(0, str(backend))

    def guard(event, args):
        if event in {"socket.connect", "socket.getaddrinfo"}:
            raise RuntimeError("Contract capture cannot use network")
    sys.addaudithook(guard)

    import httpx
    from fastapi import APIRouter, FastAPI
    from hermes_cli.web_routers import config_env

    app = FastAPI()
    app.include_router(config_env.config_router)
    current_operation = app.openapi()["paths"]["/api/config"]["get"]
    assert next(p for p in current_operation["parameters"] if p["name"] == "include_defaults")["schema"]["type"] == "boolean"

    def source(path):
        return subprocess.check_output(
            ["git", "-C", str(backend), "show", f"{OLD_REVISION}:{path}"], text=True)

    def extract(text, names, scope):
        nodes: list[ast.stmt] = [n for n in ast.parse(text).body
                 if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in names]
        assert {n.name for n in nodes if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))} == set(names)
        exec(compile(ast.Module(body=nodes, type_ignores=[]), "<pinned production functions>", "exec"), scope)

    raw = {"fallback_providers": [
        {"provider": "standard", "model": "a"},
        {"provider": "custom", "model": "b", "api_key": "${FAKE_REVIEW_KEY}"},
    ]}
    effective = copy.deepcopy(raw)
    effective["fallback_providers"][1]["api_key"] = "fake-expanded-review-value"

    async def scoped_to_thread(profile, function):
        assert profile == "selected-fixture"
        return function()

    old_router = APIRouter()
    scope = {"config_router": old_router, "Optional": Optional, "Dict": Dict, "Any": Any,
             "load_config": lambda: copy.deepcopy(effective),
             "scoped_to_thread": scoped_to_thread,
             "_ENV_REF_RE": re.compile(r"\$\{([^}]+)\}"),
             # The save guard's expansion seam uses only this fake variable.
             "_expand_env_vars": lambda value: value.replace("${FAKE_REVIEW_KEY}", "fake-expanded-review-value")}
    extract(source("hermes_cli/web_server_config.py"), ["_normalize_config_for_web"], scope)
    extract(source("hermes_cli/web_routers/config_env.py"), ["get_config"], scope)
    extract(source("hermes_cli/config.py"), ["_items_by_unique_name", "_preserve_env_ref_templates"], scope)
    old_app = FastAPI()
    old_app.include_router(old_router)
    old_operation = old_app.openapi()["paths"]["/api/config"]["get"]
    assert all(p["name"] != "include_defaults" for p in old_operation["parameters"])

    async def ignored_query():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=old_app), base_url="http://fixture") as client:
            response = await client.get("/api/config", params={"profile": "selected-fixture", "include_defaults": "false"})
            assert response.status_code == 200
            assert response.json()["fallback_providers"] == effective["fallback_providers"]
            return response.json()

    old_response = asyncio.run(ignored_query())
    reordered = {"fallback_providers": list(reversed(old_response["fallback_providers"]))}
    after_guard = scope["_preserve_env_ref_templates"](reordered, raw, effective)
    assert after_guard["fallback_providers"][0]["api_key"] == "fake-expanded-review-value"
    assert after_guard["fallback_providers"] == reordered["fallback_providers"]

    result = {
        "current_revision": subprocess.check_output(["git", "-C", str(backend), "rev-parse", "HEAD"], text=True).strip(),
        "old_revision": OLD_REVISION,
        "current_schema": {"openapi": app.openapi()["openapi"], "paths": {"/api/config": {"get": current_operation}}},
        "old_schema": {"openapi": old_app.openapi()["openapi"], "paths": {"/api/config": {"get": old_operation}}},
        "old_ignored_query": {"status": 200, "raw": raw, "response": old_response,
                              "reordered_after_actual_template_guard": after_guard},
    }
    out = Path("test/fixtures/fallback_config_contract.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Captured actual current/old GET schemas, ignored-query HTTP 200 and reorder template loss: {out}")
