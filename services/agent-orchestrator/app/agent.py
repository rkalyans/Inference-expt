"""Agent runtime.

Two modes:

* `stub`   — deterministic flow that calls weather + inventory and produces a
             rule-based recommendation. Used for first deploy and CI tests.
* `openai` — ChatOpenAI against `LLM_BASE_URL` (vLLM-compatible). The LLM is
             allowed to call the tools defined in tools.TOOL_SCHEMAS.

Both yield events as dicts; main.py wraps them as SSE.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, AsyncIterator, Dict, List, Optional

import httpx

from . import tools as t
from .settings import Settings

logger = logging.getLogger(__name__)


SYSTEM_PROMPT = """You are Stylist, a personal outfit assistant for New York City.
Reason step-by-step about weather, occasion, and the user's wardrobe before
recommending an outfit. Use the tools to gather facts; do not invent data.
Always cite the items you chose by id. Keep the response under 200 words."""


# ---------- stub mode ----------

async def _run_stub(
    http: httpx.AsyncClient, settings: Settings, *, user_id: str, query: str, zone: str
) -> AsyncIterator[Dict[str, Any]]:
    yield {"event": "thought", "text": f"Stub agent: planning for user={user_id} zone={zone}"}

    weather = await t.get_weather(http, settings, zone=zone)
    yield {"event": "tool_result", "name": "get_weather", "result": weather}

    inventory = await t.search_inventory(http, settings, user_id=user_id, limit=200)
    yield {"event": "tool_result", "name": "search_inventory", "result": inventory}

    obs = (weather.get("observation") or {})
    temp = float(obs.get("feels_like_f", obs.get("temp_f", 60)))
    cond = (obs.get("condition") or "").lower()

    items = inventory.get("items", [])
    chosen = _stub_pick(items, temp, cond)

    rec = {
        "rationale": (
            f"Feels like {temp:.0f}F in {zone}, condition {obs.get('condition','?')}. "
            "Picked items by warmth + formality match."
        ),
        "items": chosen,
        "weather": weather,
    }
    yield {"event": "final", "recommendation": rec}


def _stub_pick(items: List[Dict[str, Any]], temp_f: float, cond: str) -> List[Dict[str, Any]]:
    by_cat: Dict[str, List[Dict[str, Any]]] = {}
    for it in items:
        by_cat.setdefault(it["category"], []).append(it)

    def pick(cat: str) -> Optional[Dict[str, Any]]:
        candidates = by_cat.get(cat, [])
        if not candidates:
            return None
        # Sort by warmth match: cold weather prefers higher attributes.warmth (0-10).
        target_warmth = 8 if temp_f < 45 else 5 if temp_f < 65 else 2
        candidates = sorted(
            candidates,
            key=lambda x: abs((x.get("attributes", {}).get("warmth", 5)) - target_warmth),
        )
        return candidates[0]

    out: List[Dict[str, Any]] = []
    for cat in ("top", "bottom", "footwear"):
        c = pick(cat)
        if c:
            out.append(c)
    if temp_f < 55 or "rain" in cond:
        c = pick("outerwear")
        if c:
            out.append(c)
    return out


# ---------- openai/vllm mode ----------

async def _run_openai(
    http: httpx.AsyncClient, settings: Settings, *, user_id: str, query: str, zone: str
) -> AsyncIterator[Dict[str, Any]]:
    # Lazy import so the stub path doesn't pay the langchain import cost.
    from langchain_openai import ChatOpenAI

    if not settings.llm_base_url:
        raise RuntimeError("LLM_BASE_URL must be set when LLM_MODE=openai")

    llm = ChatOpenAI(
        base_url=settings.llm_base_url,
        api_key=settings.llm_api_key,
        model=settings.llm_model,
        temperature=settings.llm_temperature,
        max_tokens=settings.llm_max_tokens,
    ).bind_tools(t.TOOL_SCHEMAS)

    messages: List[Dict[str, Any]] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f"user_id={user_id}\nzone={zone}\nrequest: {query}"},
    ]

    for step in range(settings.max_tool_calls):
        ai = await llm.ainvoke(messages)
        messages.append({"role": "assistant", "content": ai.content, "tool_calls": ai.tool_calls})
        if not ai.tool_calls:
            yield {"event": "final", "text": ai.content}
            return

        for call in ai.tool_calls:
            yield {"event": "tool_call", "name": call["name"], "args": call["args"]}
            try:
                result = await _dispatch_tool(http, settings, call["name"], call["args"])
            except Exception as exc:
                result = {"error": str(exc)}
            yield {"event": "tool_result", "name": call["name"], "result": result}
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "name": call["name"],
                    "content": json.dumps(result, default=str),
                }
            )

    yield {"event": "error", "text": f"max_tool_calls={settings.max_tool_calls} exceeded"}


async def _dispatch_tool(http: httpx.AsyncClient, s: Settings, name: str, args: Dict[str, Any]) -> Any:
    if name == "get_weather":
        return await t.get_weather(http, s, zone=args["zone"], forecast=bool(args.get("forecast")))
    if name == "search_inventory":
        return await t.search_inventory(http, s, user_id=args["user_id"], category=args.get("category"), limit=int(args.get("limit", 50)))
    if name == "get_user_history":
        return await t.get_user_history(s, user_id=args["user_id"], limit=int(args.get("limit", 5)))
    raise ValueError(f"unknown tool: {name}")


# ---------- public entrypoint ----------

async def run_agent(
    http: httpx.AsyncClient, settings: Settings, *, user_id: str, query: str, zone: str
) -> AsyncIterator[Dict[str, Any]]:
    if settings.llm_mode == "stub":
        async for ev in _run_stub(http, settings, user_id=user_id, query=query, zone=zone):
            yield ev
    else:
        async for ev in _run_openai(http, settings, user_id=user_id, query=query, zone=zone):
            yield ev
