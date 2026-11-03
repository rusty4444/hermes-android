"""Capture real backend persistence + route projections without live config/network.

Run with the backend interpreter:
  python tools/capture_main_model_route_fixture.py BACKEND_ROOT
Writes test/fixtures/main_model_routes.json. No credentials are read or retained.
The switch result is the network/credential boundary; persistence and response
producers execute unchanged. This is not a full authenticated HTTP host test.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

backend = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="main-model-routes-", dir=os.environ["TMPDIR"]) as home:
    os.environ["HERMES_HOME"] = home
    os.environ["HERMES_DISABLE_LAZY_INSTALLS"] = "1"
    sys.path.insert(0, str(backend))

    def guard(event, args):
        if event in {"socket.connect", "socket.getaddrinfo"}:
            raise RuntimeError("Contract capture must not contact any server")
    sys.addaudithook(guard)

    from hermes_cli.auth import PROVIDER_REGISTRY
    from hermes_cli.model_switch import ModelSwitchResult
    from hermes_cli.web_server_config import _apply_main_model_assignment
    from hermes_cli.web_routers import config_env, models

    # Test every shipped allowlist entry against authoritative backend metadata.
    dart = Path("lib/core/services/main_model_route.dart").read_text()
    import re
    defaults = dict(re.findall(r"  '([^']+)': '([^']+)',", dart))
    for slug, url in defaults.items():
        if slug == "openrouter":
            # OpenRouter is supplied by its provider profile, not auth registry.
            profile = backend / "plugins/model-providers/openrouter/__init__.py"
            assert f'base_url="{url}"' in profile.read_text()
        else:
            registry_slug = {"vercel": "ai-gateway", "opencode": "opencode-zen", "kilo": "kilocode"}.get(slug) or slug
            assert PROVIDER_REGISTRY[registry_slug].inference_base_url == url, slug

    def snapshot(model_cfg, providers=None):
        cfg = {"model": model_cfg, "providers": providers or {}}
        with patch.object(models, "_load_config_scoped", return_value=cfg), \
             patch.object(models, "_bounded_context_length_probe", return_value=0), \
             patch("agent.models_dev.get_model_capabilities", return_value=None):
            info = models.get_model_info(profile="fixture")
        route = config_env._custom_endpoint_response(cfg)
        assert "base_url" not in info
        # Retain safe routing only; endpoint row credential previews stay out.
        return {"info": info, "route": {
            "current": route["current"],
            "endpoints": [{"is_current": row["is_current"]} for row in route["endpoints"]],
        }}

    scenarios = {}
    for slug in ["openrouter", "openai-api", "anthropic", "nous", "openai-codex", "deepseek"]:
        cfg = {"provider": slug, "default": "old-model", "base_url": defaults[slug]}
        before = snapshot(cfg)
        result = ModelSwitchResult(success=True, target_provider=slug,
                                   new_model="new-model", base_url=defaults[slug])
        cfg = _apply_main_model_assignment(cfg, result)
        assert cfg["base_url"] == defaults[slug]
        # Exercise physical persistence/readback on a disposable file as well.
        path = Path(home) / "selection.json"
        path.write_text(json.dumps(cfg))
        after = snapshot(json.loads(path.read_text()))
        scenarios[slug] = {"before": before, "after": after}
    scenarios["override"] = snapshot({"provider": "openai-api", "default": "old-model",
                                      "base_url": "https://private.example/v1"})
    scenarios["unknown"] = snapshot({"provider": "future-provider", "default": "old-model",
                                     "base_url": defaults["openai-api"]})
    scenarios["custom"] = snapshot({"provider": "custom", "default": "old-model",
                                    "base_url": defaults["openai-api"]})
    scenarios["named"] = snapshot({"provider": "openai-api", "default": "old-model",
                                   "base_url": defaults["openai-api"]}, {
        "openai-api": {"base_url": defaults["openai-api"], "models": ["old-model"]},
    })
    payload = {"backend_commit": subprocess.check_output(
        ["git", "-C", str(backend), "rev-parse", "HEAD"], text=True).strip(),
        "scenarios": scenarios}
    out = Path("test/fixtures/main_model_routes.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Captured {len(scenarios)} scenarios; verified {len(defaults)} canonical defaults; {out}")
