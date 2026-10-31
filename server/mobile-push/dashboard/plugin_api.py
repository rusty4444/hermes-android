"""Dashboard imports this as a standalone module, outside the lifecycle package."""

import hashlib
import importlib.util
import sys
from pathlib import Path

from agent.secret_scope import current_secret_scope_home
from fastapi import HTTPException

# Load only our private library, not __init__.py (register must remain host-owned).
# A path-qualified name avoids adopting another installed copy's globals.
_source = Path(__file__).resolve().parents[1] / "mobile_push"
_name = "_hermes_mobile_push_" + hashlib.sha256(str(_source).encode()).hexdigest()[:16]
if _name not in sys.modules:
    _spec = importlib.util.spec_from_file_location(
        _name, _source / "__init__.py", submodule_search_locations=[str(_source)]
    )
    _package = importlib.util.module_from_spec(_spec)
    sys.modules[_name] = _package
    _spec.loader.exec_module(_package)
_api = importlib.import_module(_name + ".api")
_config = importlib.import_module(_name + ".config")


def request_profile():
    # The real dashboard mount enters _plugin_route_secret_scope first. Its
    # secret-scope home is stamped by the host AFTER profile-name validation,
    # including launch/current requests that do not set a home override. Do not
    # read the query or fall back to process environment/import-time launch home.
    home = current_secret_scope_home()
    if not home:
        raise HTTPException(503, "Vetted dashboard profile scope required")
    return _config.Profile(Path(home).resolve())


# No resources/workers/cache on import. Each request owns immutable paths; Store
# opens only bounded context-managed connections and retains none after the call.
router = _api.create_router(request_profile)
