"""Agent Orchestrator service.

Endpoints:
  GET  /api/health
  POST /chat                  -> JSON request, SSE response stream

Phase 1 keeps auth simple: pass `user_id` in the body. Phase 1.5 wires
Firebase JWT validation and extracts user_id from the token.
"""

from __future__ import annotations

import json
import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator, Optional

import httpx
import structlog
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sse_starlette.sse import EventSourceResponse

from .agent import run_agent
from .bff import router as bff_router
from .firebase_auth import CurrentUser, get_current_user
from .settings import get_settings
from .tools import save_recommendation

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    app.state.settings = s
    app.state.http = httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=5.0))
    log.info(
        "agent.startup",
        env=s.app_env,
        llm_mode=s.llm_mode,
        llm_base_url=s.llm_base_url or "(none)",
        firestore_db=s.firestore_database,
    )
    try:
        yield
    finally:
        await app.state.http.aclose()


app = FastAPI(title="Stylist Agent Orchestrator", lifespan=lifespan)

_settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=_settings.cors_allow_origins or ["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

app.include_router(bff_router)


# NOTE: We use `/api/health` instead of `/healthz` because Google's edge
# frontend intercepts `/healthz` (and `/health`, `/ready`) and returns its
# own 404 before traffic reaches the Cloud Run container. See Troubleshooting (1.3).
@app.get("/api/health")
async def healthz():
    return {"status": "ok", "service": "agent-orchestrator"}


@app.get("/")
async def root():
    s = app.state.settings
    return {
        "service": "agent-orchestrator",
        "version": os.getenv("VERSION", "manual"),
        "env": s.app_env,
        "llm_mode": s.llm_mode,
    }


class ChatRequest(BaseModel):
    query: str = Field(min_length=1, max_length=2000)
    zone: str = "midtown"


@app.post("/chat")
async def chat(req: ChatRequest, user: CurrentUser = Depends(get_current_user)):
    s = app.state.settings
    user_id = user.inventory_user_id

    async def _stream() -> AsyncIterator[dict]:
        last_final = None
        try:
            async for ev in run_agent(
                app.state.http, s, user_id=user_id, query=req.query, zone=req.zone
            ):
                if ev.get("event") == "final":
                    last_final = ev
                yield {"event": ev.get("event", "message"), "data": json.dumps(ev, default=str)}
        except Exception as exc:
            log.exception("agent.error")
            yield {"event": "error", "data": json.dumps({"error": str(exc)})}
            return

        if last_final:
            try:
                rec_id = await save_recommendation(
                    s,
                    user_id=user_id,
                    request_payload={**req.model_dump(), "user_id": user_id},
                    response_payload=last_final,
                )
                yield {
                    "event": "saved",
                    "data": json.dumps({"recommendation_id": rec_id}),
                }
            except Exception as exc:
                log.warning("agent.save_failed", err=str(exc))

    return EventSourceResponse(_stream())
