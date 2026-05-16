"""BFF (Backend-For-Frontend) proxy.

Inventory + weather are `INGRESS_TRAFFIC_INTERNAL_ONLY` — the browser cannot
reach them directly. The Next.js frontend therefore talks to the agent only;
the agent proxies the subset of inventory endpoints the UI needs, attaching
the OIDC token that gives it `run.invoker` permission.

Endpoints (mounted under `/api`):
  POST   /api/users                    -> get-or-create
  GET    /api/items                    -> list current user's wardrobe
  POST   /api/items                    -> create item
  GET    /api/items/{id}               -> get
  PUT    /api/items/{id}               -> update
  DELETE /api/items/{id}               -> delete
  POST   /api/items/upload-url         -> signed-URL minting

Phase 1.4 still uses a `user_id` query/body param. Phase 1.5 swaps in the
Firebase JWT claim and removes the param entirely.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

import httpx
from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel
from uuid import UUID  # noqa: F401  (kept for backwards-compat imports)

from fastapi import Depends

from .auth import auth_headers
from .firebase_auth import CurrentUser, get_current_user

log = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["bff"])


def _inv_base(request: Request) -> str:
    base = request.app.state.settings.inventory_base_url
    if not base:
        raise HTTPException(500, "INVENTORY_BASE_URL not configured")
    return base.rstrip("/")


async def _forward(
    request: Request,
    method: str,
    path: str,
    *,
    params: Optional[dict] = None,
    json: Any = None,
) -> Any:
    base = _inv_base(request)
    url = f"{base}{path}"
    headers = auth_headers(base)
    http: httpx.AsyncClient = request.app.state.http
    try:
        r = await http.request(method, url, params=params, json=json, headers=headers)
    except httpx.RequestError as exc:
        log.exception("bff.upstream_error")
        raise HTTPException(502, f"upstream inventory request failed: {exc}") from exc
    if r.status_code >= 400:
        raise HTTPException(r.status_code, r.text)
    if r.status_code == 204:
        return None
    return r.json()


# ---------- users ----------

@router.get("/users/me")
async def me(user: CurrentUser = Depends(get_current_user)):
    """Return the authenticated user's id + email. Triggers lazy provisioning
    on the inventory side on first call after sign-up."""
    return {"id": user.inventory_user_id, "email": user.email, "firebase_uid": user.firebase_uid}


class PreferencesUpdate(BaseModel):
    preferences: dict


@router.put("/users/me/preferences")
async def update_preferences(
    payload: PreferencesUpdate,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
):
    # Inventory's POST /users is upsert-by-email. Reuse it to update preferences.
    return await _forward(
        request,
        "POST",
        "/users",
        json={"email": user.email, "preferences": payload.preferences},
    )


# ---------- items ----------

@router.get("/items")
async def get_items(
    request: Request,
    user: CurrentUser = Depends(get_current_user),
    category: Optional[str] = None,
    limit: int = Query(50, le=200),
):
    params: dict = {"user_id": user.inventory_user_id, "limit": limit}
    if category:
        params["category"] = category
    return await _forward(request, "GET", "/items", params=params)


class ItemCreate(BaseModel):
    name: str
    category: str
    attributes: dict = {}
    photo_url: Optional[str] = None


@router.post("/items", status_code=201)
async def post_item(
    payload: ItemCreate,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
):
    return await _forward(
        request,
        "POST",
        "/items",
        params={"user_id": user.inventory_user_id},
        json=payload.model_dump(),
    )


@router.get("/items/{item_id}")
async def get_one(
    item_id: str,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
):
    return await _forward(
        request, "GET", f"/items/{item_id}", params={"user_id": user.inventory_user_id}
    )


class ItemUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    attributes: Optional[dict] = None
    photo_url: Optional[str] = None


@router.put("/items/{item_id}")
async def put_item(
    item_id: str,
    payload: ItemUpdate,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
):
    return await _forward(
        request,
        "PUT",
        f"/items/{item_id}",
        params={"user_id": user.inventory_user_id},
        json=payload.model_dump(exclude_unset=True),
    )


@router.delete("/items/{item_id}", status_code=204)
async def del_item(
    item_id: str,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
):
    await _forward(
        request,
        "DELETE",
        f"/items/{item_id}",
        params={"user_id": user.inventory_user_id},
    )
    return None


# ---------- upload helper ----------

class UploadUrlRequest(BaseModel):
    content_type: str = "image/jpeg"


@router.post("/items/upload-url")
async def upload_url(
    payload: UploadUrlRequest,
    request: Request,
    user: CurrentUser = Depends(get_current_user),  # auth gate only
):
    return await _forward(
        request, "POST", "/items/upload-url", json=payload.model_dump()
    )
