"""Postgres connection pool over the Cloud SQL Auth Proxy unix socket.

We connect via `/cloudsql/<connection_name>/.s.PGSQL.5432` (the standard
Cloud Run integration). With IAM authentication enabled, the password is the
short-lived OAuth token; asyncpg handles that via the `cloud-sql-python-connector`
flow elsewhere, but for the simple unix-socket path Cloud Run injects identity
automatically — we just need to set the username to the service-account email
(without the `.gserviceaccount.com` suffix) and asyncpg will use peer auth.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator, Optional

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

logger = logging.getLogger(__name__)


def _build_dsn(*, user: str, name: str, connection_name: Optional[str], host_base: str) -> str:
    if connection_name:
        # Cloud Run unix socket
        socket_dir = f"{host_base}/{connection_name}"
        return f"postgresql+asyncpg://{user}@/{name}?host={socket_dir}"
    # Local development (e.g. cloud-sql-proxy on 127.0.0.1:5432)
    return f"postgresql+asyncpg://{user}@127.0.0.1:5432/{name}"


class Database:
    def __init__(self, *, user: str, name: str, connection_name: Optional[str], host_base: str) -> None:
        self.dsn = _build_dsn(user=user, name=name, connection_name=connection_name, host_base=host_base)
        self.engine = create_async_engine(self.dsn, pool_size=4, max_overflow=4, pool_pre_ping=True)
        self.session_factory = async_sessionmaker(self.engine, expire_on_commit=False, class_=AsyncSession)

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        async with self.session_factory() as s:
            yield s

    async def close(self) -> None:
        await self.engine.dispose()
