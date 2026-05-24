"""Weather Tool API.

Endpoints:
  GET  /api/health
  GET  /weather?zone=midtown                  -> current weather for the zone
  GET  /weather?zone=midtown&forecast=true    -> 24h forecast (TODO: hourly)

Cached in Redis with separate TTLs for current vs forecast.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from typing import Optional

import httpx
import structlog
from fastapi import FastAPI, HTTPException, Query

from .cache import Cache
from .microclimate import ZONES, apply
from .providers import fetch_current_openmeteo, fetch_current_owm
from .settings import get_settings

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    app.state.settings = s
    app.state.cache = Cache(s.redis_host, s.redis_port, s.redis_auth)
    app.state.http = httpx.AsyncClient(timeout=s.http_timeout_seconds)
    log.info("weather.startup", env=s.app_env, zones=list(ZONES))
    try:
        yield
    finally:
        await app.state.http.aclose()


app = FastAPI(title="Stylist Weather Tool", lifespan=lifespan)


# NOTE: `/api/health` not `/healthz` — Cloud Run's edge frontend intercepts
# `/healthz`, `/health`, `/ready` and serves its own 404 before traffic reaches
# the container. See PHASE-1-RUNBOOK.md Troubleshooting (1.3).
@app.get("/api/health")
async def healthz():
    return {"status": "ok", "service": "weather-api"}


@app.get("/")
async def root():
    s = app.state.settings
    return {
        "service": "weather-api",
        "version": os.getenv("VERSION", "manual"),
        "env": s.app_env,
        "zones": list(ZONES),
    }


@app.get("/weather")
async def get_weather(
    zone: str = Query(..., description="midtown|waterfront|downtown|uptown"),
    forecast: bool = False,
):
    s = app.state.settings
    if zone not in ZONES:
        raise HTTPException(status_code=400, detail=f"unknown zone: {zone}")

    cache_key = f"weather:{zone}:{'forecast' if forecast else 'current'}"
    cached = app.state.cache.get_json(cache_key)
    if cached is not None:
        return {"cached": True, **cached}

    coords = ZONES[zone]
    raw: Optional[dict] = await fetch_current_owm(
        app.state.http, coords["lat"], coords["lon"], s.openweathermap_api_key or ""
    )
    if raw is None:
        raw = await fetch_current_openmeteo(app.state.http, coords["lat"], coords["lon"])
    if raw is None:
        raise HTTPException(status_code=502, detail="all upstream weather providers failed")

    adjusted = apply(zone, raw)
    payload = {"zone": zone, "forecast": forecast, "observation": adjusted}
    app.state.cache.set_json(
        cache_key,
        payload,
        s.forecast_ttl_seconds if forecast else s.current_ttl_seconds,
    )
    return {"cached": False, **payload}
