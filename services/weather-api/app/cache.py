"""Thin Redis wrapper that no-ops when Redis is unavailable.

Phase 1 keeps this resilient — the agent must still respond if the cache is
down. Cache misses fall through to the upstream provider; cache failures log
and continue.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Optional

import redis

logger = logging.getLogger(__name__)


class Cache:
    def __init__(self, host: Optional[str], port: int, auth: Optional[str]) -> None:
        self._client: Optional[redis.Redis] = None
        if not host:
            logger.warning("redis_host not set; cache disabled")
            return
        try:
            self._client = redis.Redis(
                host=host,
                port=port,
                password=auth,
                ssl=True if auth else False,
                ssl_cert_reqs=None,
                decode_responses=True,
                socket_connect_timeout=2.0,
                socket_timeout=2.0,
            )
            self._client.ping()
            logger.info("redis ready", extra={"host": host, "port": port})
        except Exception as exc:  # pragma: no cover - boot resilience
            logger.warning("redis init failed: %s", exc)
            self._client = None

    def get_json(self, key: str) -> Optional[Any]:
        if not self._client:
            return None
        try:
            raw = self._client.get(key)
            return json.loads(raw) if raw else None
        except Exception as exc:
            logger.warning("redis get failed: %s", exc)
            return None

    def set_json(self, key: str, value: Any, ttl_seconds: int) -> None:
        if not self._client:
            return
        try:
            self._client.set(key, json.dumps(value), ex=ttl_seconds)
        except Exception as exc:
            logger.warning("redis set failed: %s", exc)
