"""NYC microclimate adjustments per zone.

The Stylist agent reasons over zones rather than raw lat/long. Each zone has
a representative coordinate plus per-feature deltas that nudge the upstream
forecast to better match what a person actually feels at street level.
"""

from typing import Dict

ZONES: Dict[str, Dict[str, float]] = {
    # name -> { lat, lon, temp_offset_f, wind_mult, humidity_offset_pct }
    "waterfront": {
        "lat": 40.7048, "lon": -74.0150,
        "temp_offset_f": -2.0,   # waterfront is colder + windier
        "wind_mult": 1.25,
        "humidity_offset_pct": +5.0,
    },
    "midtown": {
        "lat": 40.7549, "lon": -73.9840,
        "temp_offset_f": +1.5,   # urban heat island
        "wind_mult": 0.9,
        "humidity_offset_pct": 0.0,
    },
    "downtown": {
        "lat": 40.7128, "lon": -74.0060,
        "temp_offset_f": +0.5,
        "wind_mult": 1.1,        # canyon effect
        "humidity_offset_pct": 0.0,
    },
    "uptown": {
        "lat": 40.7831, "lon": -73.9712,
        "temp_offset_f": -0.5,   # park cooling
        "wind_mult": 1.0,
        "humidity_offset_pct": +2.0,
    },
}


def apply(zone: str, observation: Dict[str, float]) -> Dict[str, float]:
    z = ZONES.get(zone)
    if not z:
        return observation
    out = dict(observation)
    if "temp_f" in out:
        out["temp_f"] = round(out["temp_f"] + z["temp_offset_f"], 1)
    if "feels_like_f" in out:
        out["feels_like_f"] = round(out["feels_like_f"] + z["temp_offset_f"], 1)
    if "wind_mph" in out:
        out["wind_mph"] = round(out["wind_mph"] * z["wind_mult"], 1)
    if "humidity_pct" in out:
        out["humidity_pct"] = max(0.0, min(100.0, out["humidity_pct"] + z["humidity_offset_pct"]))
    out["zone"] = zone
    return out
