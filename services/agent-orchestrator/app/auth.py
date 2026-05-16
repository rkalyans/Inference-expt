"""OIDC token minting for Cloud Run -> Cloud Run calls.

When the orchestrator calls the inventory or weather service, it needs to
present a Google-signed identity token whose audience is the target service URL.
"""

from __future__ import annotations

from functools import lru_cache

import google.auth
import google.auth.transport.requests
from google.oauth2 import id_token


@lru_cache(maxsize=64)
def _audience_url(base_url: str) -> str:
    # The audience must be the root URL of the target service, no path.
    from urllib.parse import urlparse

    p = urlparse(base_url)
    return f"{p.scheme}://{p.netloc}"


def get_id_token(target_audience: str) -> str:
    request = google.auth.transport.requests.Request()
    return id_token.fetch_id_token(request, target_audience)


def auth_headers(base_url: str) -> dict:
    return {"Authorization": f"Bearer {get_id_token(_audience_url(base_url))}"}
