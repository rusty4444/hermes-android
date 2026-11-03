"""Authenticated API. request.state.session is the sole principal authority."""

from __future__ import annotations

import re
import sqlite3
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.routing import APIRoute
from pydantic import BaseModel, ConfigDict, Field

from .config import Profile, Rejected, identifier, validate_keys
from .scope import SessionScope
from .store import Store
from .transport import validate_endpoint


class BoundedRoute(APIRoute):
    def get_route_handler(self):
        handler = super().get_route_handler()

        async def bounded(request):
            if request.method in {"PUT", "POST"}:
                data = bytearray()
                async for chunk in request.stream():
                    data.extend(chunk)
                    if len(data) > 32768:
                        raise HTTPException(413, "Request too large")
                request._body = bytes(data)
            return await handler(request)

        return bounded


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Keys(StrictModel):
    p256dh: str = Field(min_length=80, max_length=100)
    auth: str = Field(min_length=20, max_length=24)


class Registration(StrictModel):
    registration_revision: int = Field(ge=1, le=9007199254740991)
    endpoint: str = Field(min_length=8, max_length=2048)
    keys: Keys
    registration_nonce: str = Field(pattern=r"^[A-Za-z0-9_-]{16,128}$")
    event_kinds: list[Literal["turn_done", "turn_error", "input", "input_resolved"]] = Field(
        min_length=1, max_length=4
    )
    session_scope: Literal["explicit", "authorized"] = "explicit"
    session_ids: list[str] | None = Field(default=None, min_length=1, max_length=128)


class Confirmation(StrictModel):
    generation: int = Field(ge=1, le=9223372036854775807)
    challenge: str = Field(pattern=r"^[A-Za-z0-9_-]{16,128}$")


def principal(request: Request) -> tuple[str, str]:
    # Never fall back to bearer text, X-User headers, request.state.principal, body or query.
    session = getattr(request.state, "session", None)
    provider, user_id = getattr(session, "provider", None), getattr(session, "user_id", None)
    if not all(isinstance(item, str) and item and len(item) <= 500 for item in (provider, user_id)):
        raise HTTPException(401, "Verified dashboard session required")
    return provider, user_id


def guarded(function, *args):
    try:
        return function(*args)
    except Rejected as error:
        raise HTTPException(error.status, str(error)) from None
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error):
        raise HTTPException(503, "Mobile push unavailable") from None


Identity = Annotated[tuple[str, str], Depends(principal)]


def create_router(profile_source):
    router = APIRouter(route_class=BoundedRoute)

    def profile_for_request(identity: Identity):
        # Resolve only AFTER verified principal authentication, within the host's
        # request-local scope. Capture an immutable Profile for the whole request,
        # never a query-derived path or a shared "current" profile/store slot.
        return guarded(profile_source) if callable(profile_source) else profile_source

    def policy_for(profile, identity):
        policy = profile.policy()
        if not policy.enabled:
            raise Rejected(503, "Mobile push disabled")
        if not policy.admitted(identity):
            raise Rejected(403, "Principal not authorised for mobile push")
        return policy

    @router.get("/capabilities")
    def capabilities(identity: Identity, profile: Profile = Depends(profile_for_request)):
        def read():
            policy = profile.policy()
            enabled = policy.enabled and policy.admitted(identity)
            return {
                "schema": 1,
                "registration_fence": 1,
                "session_scope_modes": ["explicit", "authorized"],
                "transports": ["webpush"],
                "enabled": enabled,
                "vapid_public_key": policy.public_key() if enabled else "",
            }

        return guarded(read)

    @router.put("/registrations/{installation_id}")
    def register(
        installation_id: str,
        body: Registration,
        identity: Identity,
        profile: Profile = Depends(profile_for_request),
    ):
        def update():
            policy = policy_for(profile, identity)
            registration = body.model_dump(exclude_unset=True)
            scope = SessionScope.from_body(registration)
            if not identifier(installation_id):
                raise Rejected(422, "Invalid installation ID")
            if len(set(body.event_kinds)) != len(body.event_kinds):
                raise Rejected(422, "Duplicate subscription scope")
            # Authorisation before DNS: unauthorised callers cannot use this as a lookup oracle.
            if not scope.ready(identity, policy, profile.durable):
                raise Rejected(403, "Session scope not authorised or not durable")
            validate_keys(body.keys.model_dump())
            validate_endpoint(body.endpoint, policy)
            return Store(profile.database).put(identity, installation_id, registration, policy)

        return guarded(update)

    @router.post("/registrations/{installation_id}/confirm")
    def confirm(
        installation_id: str,
        body: Confirmation,
        identity: Identity,
        profile: Profile = Depends(profile_for_request),
    ):
        def activate():
            policy = policy_for(profile, identity)
            return Store(profile.database).confirm(
                identity, installation_id, body.generation, body.challenge, policy, profile.durable
            )

        return guarded(activate)

    @router.delete("/registrations/{installation_id}")
    def revoke(
        installation_id: str,
        identity: Identity,
        profile: Profile = Depends(profile_for_request),
    ):
        def remove():
            # Revocation remains possible after an operator disables/removes a grant.
            if not identifier(installation_id):
                raise Rejected(422, "Invalid installation ID")
            return Store(profile.database).revoke(identity, installation_id, profile.policy)

        return guarded(remove)

    @router.get("/events")
    def events(
        request: Request,
        identity: Identity,
        profile: Profile = Depends(profile_for_request),
        after: int = Query(default=0, ge=0, le=9223372036854775807),
        limit: int = Query(default=100, ge=1, le=200),
        installation_id: str | None = Query(default=None),
        generation: str | None = Query(default=None),
    ):
        def read():
            policy = policy_for(profile, identity)
            bound_generation = None
            if installation_id is not None or generation is not None:
                if (
                    not identifier(installation_id)
                    or generation is None
                    or not re.fullmatch(r"[1-9][0-9]{0,18}", generation)
                    or int(generation) > 9223372036854775807
                    or len(request.query_params.getlist("installation_id")) != 1
                    or len(request.query_params.getlist("generation")) != 1
                ):
                    raise Rejected(
                        422, "Exact installation_id and positive generation required together"
                    )
                bound_generation = int(generation)
            return Store(profile.database).events(
                identity, after, limit, policy, profile.durable, installation_id, bound_generation
            )

        return guarded(read)

    return router
