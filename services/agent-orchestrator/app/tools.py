"""Tool registry. Each tool is an async callable that returns JSON-serializable
data. Tools are kept narrow (single responsibility) so the LLM can compose them.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

import httpx
from google.cloud import firestore

from .auth import auth_headers
from .settings import Settings

logger = logging.getLogger(__name__)


class ToolError(RuntimeError):
    pass


# ---------- weather ----------

async def get_weather(http: httpx.AsyncClient, settings: Settings, *, zone: str, forecast: bool = False) -> Dict[str, Any]:
    if not settings.weather_base_url:
        raise ToolError("WEATHER_BASE_URL not configured")
    url = f"{settings.weather_base_url.rstrip('/')}/weather"
    r = await http.get(url, params={"zone": zone, "forecast": forecast}, headers=auth_headers(settings.weather_base_url))
    r.raise_for_status()
    return r.json()


# ---------- inventory ----------

async def search_inventory(
    http: httpx.AsyncClient,
    settings: Settings,
    *,
    user_id: str,
    category: Optional[str] = None,
    limit: int = 50,
) -> Dict[str, Any]:
    if not settings.inventory_base_url:
        raise ToolError("INVENTORY_BASE_URL not configured")
    url = f"{settings.inventory_base_url.rstrip('/')}/items"
    params: Dict[str, Any] = {"user_id": user_id, "limit": limit}
    if category:
        params["category"] = category
    r = await http.get(url, params=params, headers=auth_headers(settings.inventory_base_url))
    r.raise_for_status()
    return r.json()


# ---------- user history ----------

def _firestore_client(settings: Settings) -> firestore.Client:
    return firestore.Client(project=settings.project_id, database=settings.firestore_database)


async def get_user_history(settings: Settings, *, user_id: str, limit: int = 5) -> List[Dict[str, Any]]:
    db = _firestore_client(settings)
    coll = db.collection("recommendations")
    docs = (
        coll.where("user_id", "==", user_id)
        .order_by("created_at", direction=firestore.Query.DESCENDING)
        .limit(limit)
        .stream()
    )
    out: List[Dict[str, Any]] = []
    for d in docs:
        x = d.to_dict() or {}
        x["id"] = d.id
        out.append(x)
    return out


async def save_recommendation(
    settings: Settings,
    *,
    user_id: str,
    request_payload: Dict[str, Any],
    response_payload: Dict[str, Any],
    trace_id: Optional[str] = None,
) -> str:
    db = _firestore_client(settings)
    doc = db.collection("recommendations").document()
    doc.set(
        {
            "user_id": user_id,
            "request": request_payload,
            "response": response_payload,
            "trace_id": trace_id,
            "created_at": datetime.now(timezone.utc),
        }
    )
    return doc.id


# ---------- registry ----------

ToolFn = Callable[..., Any]

TOOL_SCHEMAS: List[Dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get current (or forecast) weather for an NYC zone with microclimate adjustments.",
            "parameters": {
                "type": "object",
                "properties": {
                    "zone": {"type": "string", "enum": ["midtown", "waterfront", "downtown", "uptown"]},
                    "forecast": {"type": "boolean", "default": False},
                },
                "required": ["zone"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_inventory",
            "description": "List a user's clothing items, optionally filtered by category.",
            "parameters": {
                "type": "object",
                "properties": {
                    "user_id": {"type": "string", "format": "uuid"},
                    "category": {"type": "string", "enum": ["top", "bottom", "footwear", "outerwear", "accessory"]},
                    "limit": {"type": "integer", "default": 50},
                },
                "required": ["user_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_user_history",
            "description": "Most recent recommendations for the user (helps personalize).",
            "parameters": {
                "type": "object",
                "properties": {
                    "user_id": {"type": "string", "format": "uuid"},
                    "limit": {"type": "integer", "default": 5},
                },
                "required": ["user_id"],
            },
        },
    },
]
