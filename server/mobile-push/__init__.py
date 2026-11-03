"""Hermes lifecycle entrypoint. No live work on import."""

from pathlib import Path


def register(ctx):
    from hermes_constants import get_hermes_home

    from .mobile_push.config import Profile
    from .mobile_push.service import Runtime

    profile = Profile(Path(get_hermes_home()).resolve())
    policy = profile.policy()
    if not policy.enabled:
        return
    policy.public_key()  # fail before hooks/worker acquisition on invalid key
    runtime = Runtime(profile)
    ctx.on_unload(runtime.stop)  # teardown recorded BEFORE resources or callbacks
    runtime.initialise()
    ctx.register_hook("on_session_end", runtime.session_end)
    ctx.register_hook("on_human_input_request", runtime.human_input)
    ctx.register_hook("on_human_input_resolved", runtime.human_resolved)
    runtime.start()
