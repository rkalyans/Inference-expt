"""Upstream weather providers with automatic fallback.

Order:
  1. OpenWeatherMap (paid, accurate)
  2. Open-Meteo  (free, no key, used as fallback)

Each returns a normalized dict:
  { temp_f, feels_like_f, wind_mph, humidity_pct, condition, observed_at }
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


def _c_to_f(c: float) -> float:
    return round(c * 9 / 5 + 32, 1)


def _ms_to_mph(ms: float) -> float:
    return round(ms * 2.23694, 1)


async def fetch_current_owm(client: httpx.AsyncClient, lat: float, lon: float, api_key: str) -> Optional[dict]:
    if not api_key:
        return None
    try:
        r = await client.get(
            "https://api.openweathermap.org/data/2.5/weather",
            params={"lat": lat, "lon": lon, "appid": api_key, "units": "imperial"},
            timeout=5.0,
        )
        r.raise_for_status()
        data = r.json()
        return {
            "temp_f": data["main"]["temp"],
            "feels_like_f": data["main"]["feels_like"],
            "wind_mph": data.get("wind", {}).get("speed", 0.0),
            "humidity_pct": data["main"]["humidity"],
            "condition": data["weather"][0]["main"] if data.get("weather") else "unknown",
            "observed_at": datetime.fromtimestamp(data["dt"], tz=timezone.utc).isoformat(),
            "provider": "openweathermap",
        }
    except Exception as exc:
        logger.warning("openweathermap failed: %s", exc)
        return None


async def fetch_current_openmeteo(client: httpx.AsyncClient, lat: float, lon: float) -> Optional[dict]:
    try:
        r = await client.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,relative_humidity_2m,apparent_temperature,wind_speed_10m,weather_code",
                "wind_speed_unit": "ms",
            },
            timeout=5.0,
        )
        r.raise_for_status()
        cur = r.json().get("current") or {}
        return {
            "temp_f": _c_to_f(cur["temperature_2m"]),
            "feels_like_f": _c_to_f(cur["apparent_temperature"]),
            "wind_mph": _ms_to_mph(cur["wind_speed_10m"]),
            "humidity_pct": cur["relative_humidity_2m"],
            "condition": _open_meteo_code_to_label(cur.get("weather_code", 0)),
            "observed_at": datetime.now(timezone.utc).isoformat(),
            "provider": "open-meteo",
        }
    except Exception as exc:
        logger.warning("open-meteo failed: %s", exc)
        return None


def _open_meteo_code_to_label(code: int) -> str:
    # WMO weather codes -> coarse label
    if code in (0,):
        return "Clear"
    if code in (1, 2, 3):
        return "Clouds"
    if 45 <= code <= 48:
        return "Fog"
    if 51 <= code <= 67:
        return "Rain"
    if 71 <= code <= 77:
        return "Snow"
    if 80 <= code <= 82:
        return "Rain"
    if 85 <= code <= 86:
        return "Snow"
    if code in (95, 96, 99):
        return "Thunderstorm"
    return "unknown"
