"""Inventory Tool API.

Endpoints:
  GET    /healthz
  POST   /users                                 -> get-or-create user
  POST   /items?user_id=...                     -> create clothing item
  GET    /items?user_id=...&category=...        -> list items
  GET    /items/{id}?user_id=...                -> get
  PUT    /items/{id}?user_id=...                -> update
  DELETE /items/{id}?user_id=...                -> delete
  POST   /items/upload-url                      -> mint signed PUT URL for a photo

Phase 1 keeps user identity simple: the agent passes `user_id` explicitly.
Phase 1.5 introduces Firebase Auth and we'll move to JWT extraction.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from typing import Optional
from uuid import UUID

import structlog
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel

from .db import Database
from .models import (
    Item,
    ItemCreate,
    ItemList,
    ItemUpdate,
    UploadUrlResponse,
    User,
    UserCreate,
)
from .repo import (
    create_item,
    delete_item,
    get_item,
    get_or_create_user,
    list_items,
    update_item,
)
from .settings import get_settings
from .storage import mint_upload_url

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    if not s.db_user:
        raise RuntimeError("DB_USER must be set (the runtime SA email without .gserviceaccount.com)")
    app.state.settings = s
    app.state.db = Database(
        user=s.db_user,
        name=s.db_name,
        connection_name=s.db_connection_name,
        host_base=s.db_host,
    )
    log.info("inventory.startup", env=s.app_env, db_user=s.db_user)
    try:
        yield
    finally:
        await app.state.db.close()


app = FastAPI(title="Stylist Inventory Tool", lifespan=lifespan)


@app.get("/healthz")
async def healthz():
    return {"status": "ok", "service": "inventory-api"}


@app.get("/")
async def root():
    s = app.state.settings
    return {
        "service": "inventory-api",
        "version": os.getenv("VERSION", "manual"),
        "env": s.app_env,
    }


# ---------- users ----------

@app.post("/users", response_model=User)
async def post_user(payload: UserCreate):
    async with app.state.db.session() as s:
        return User(**await get_or_create_user(s, payload.email, payload.preferences))


# ---------- items ----------

@app.get("/items", response_model=ItemList)
async def get_items(user_id: UUID, category: Optional[str] = None, limit: int = Query(50, le=200)):
    async with app.state.db.session() as s:
        items = await list_items(s, user_id, category, limit)
    return ItemList(items=[Item(**i) for i in items])


@app.post("/items", response_model=Item, status_code=201)
async def post_item(payload: ItemCreate, user_id: UUID):
    async with app.state.db.session() as s:
        row = await create_item(
            s, user_id, payload.name, payload.category, payload.attributes, payload.photo_url
        )
    return Item(**row)


@app.get("/items/{item_id}", response_model=Item)
async def get_one(item_id: UUID, user_id: UUID):
    async with app.state.db.session() as s:
        row = await get_item(s, user_id, item_id)
    if not row:
        raise HTTPException(404, "not found")
    return Item(**row)


@app.put("/items/{item_id}", response_model=Item)
async def put_item(item_id: UUID, user_id: UUID, payload: ItemUpdate):
    async with app.state.db.session() as s:
        row = await update_item(
            s,
            user_id,
            item_id,
            name=payload.name,
            category=payload.category,
            attributes=payload.attributes,
            photo_url=payload.photo_url,
        )
    if not row:
        raise HTTPException(404, "not found")
    return Item(**row)


@app.delete("/items/{item_id}", status_code=204)
async def del_item(item_id: UUID, user_id: UUID):
    async with app.state.db.session() as s:
        ok = await delete_item(s, user_id, item_id)
    if not ok:
        raise HTTPException(404, "not found")


# ---------- upload helper ----------

class UploadUrlRequest(BaseModel):
    content_type: str = "image/jpeg"


@app.post("/items/upload-url", response_model=UploadUrlResponse)
async def upload_url(payload: UploadUrlRequest):
    s = app.state.settings
    if not s.clothing_bucket:
        raise HTTPException(500, "CLOTHING_BUCKET env var not configured")
    url, uri = mint_upload_url(s.clothing_bucket, payload.content_type, s.signed_url_ttl_seconds)
    return UploadUrlResponse(
        upload_url=url,
        object_uri=uri,
        expires_in_seconds=s.signed_url_ttl_seconds,
    )
