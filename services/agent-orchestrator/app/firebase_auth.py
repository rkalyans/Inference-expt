"""Firebase ID-token verification + lazy user provisioning.

End-user flow (Phase 1.5):
  1. Browser obtains an ID token from Firebase Auth (email link / Google sign-in).
  2. Browser sends `Authorization: Bearer <idToken>` to /api/* and /chat.
  3. This module verifies the JWT (signature, expiry, audience = project_id),
     extracts (`firebase_uid`, `email`), and looks up the inventory user row by
     email. If missing, it creates one (idempotent POST /users on inventory).
  4. The resolved inventory `user_id` is attached to the request via the
     returned `CurrentUser` model.

The verification keys are fetched + cached by `firebase-admin`.

We **decouple Firebase UID from inventory user_id** so a future migration
(swap Firebase for another IdP) only re-links the `email -> inventory_uuid`
mapping without rewriting clothing rows.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from functools import lru_cache
from typing import Optional

import firebase_admin
import httpx
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth as fb_auth

from .auth import auth_headers
from .settings import Settings, get_settings

log = logging.getLogger(__name__)

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class CurrentUser:
    firebase_uid: str
    email: str
    inventory_user_id: str  # UUID string from the inventory DB


@lru_cache(maxsize=1)
def _init_firebase(project_id: str) -> firebase_admin.App:
    """Initialize the firebase-admin SDK using Application Default Credentials.

    On Cloud Run, ADC resolves to the runtime SA. The project id must be passed
    explicitly so token audience verification matches.
    """
    try:
        return firebase_admin.get_app()
    except ValueError:
        return firebase_admin.initialize_app(options={"projectId": project_id})


# In-process cache: firebase_uid -> inventory_user_id.
# Bounded so memory stays flat even under churn (e.g. expired tokens, rotated uids).
_uid_cache: dict[str, str] = {}
_UID_CACHE_MAX = 10_000


async def _resolve_inventory_user(
    request: Request, settings: Settings, *, email: str
) -> str:
    base = (settings.inventory_base_url or "").rstrip("/")
    if not base:
        raise HTTPException(500, "INVENTORY_BASE_URL not configured")
    http: httpx.AsyncClient = request.app.state.http
    headers = auth_headers(base)
    headers["content-type"] = "application/json"
    r = await http.post(
        f"{base}/users", json={"email": email, "preferences": {}}, headers=headers
    )
    if r.status_code >= 400:
        log.warning("auth.resolve_user_failed status=%s body=%s", r.status_code, r.text)
        raise HTTPException(502, f"inventory /users failed: {r.status_code}")
    return r.json()["id"]


async def get_current_user(
    request: Request,
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    settings: Settings = Depends(get_settings),
) -> CurrentUser:
    if creds is None or creds.scheme.lower() != "bearer":
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not settings.firebase_project_id:
        # Allows dev runs in stub mode without a Firebase project. In any real
        # deploy `FIREBASE_PROJECT_ID` is set by Terraform.
        raise HTTPException(500, "FIREBASE_PROJECT_ID not configured")

    _init_firebase(settings.firebase_project_id)

    try:
        decoded = fb_auth.verify_id_token(creds.credentials, check_revoked=False)
    except fb_auth.ExpiredIdTokenError:
        raise HTTPException(401, "token expired")
    except fb_auth.InvalidIdTokenError as exc:
        raise HTTPException(401, f"invalid token: {exc}")
    except Exception as exc:  # network / clock issues
        log.exception("auth.verify_failed")
        raise HTTPException(401, f"token verification failed: {exc}")

    uid = decoded.get("uid") or decoded.get("user_id") or decoded.get("sub")
    email = decoded.get("email")
    if not uid or not email:
        raise HTTPException(401, "token missing uid or email")

    inv_id = _uid_cache.get(uid)
    if inv_id is None:
        inv_id = await _resolve_inventory_user(request, settings, email=email)
        if len(_uid_cache) >= _UID_CACHE_MAX:
            _uid_cache.clear()
        _uid_cache[uid] = inv_id

    return CurrentUser(firebase_uid=uid, email=email, inventory_user_id=inv_id)
