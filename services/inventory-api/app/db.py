"""Postgres connection pool for Cloud SQL using the Cloud SQL Python Connector
with IAM database authentication.

The Cloud Run built-in `/cloudsql/<conn>` unix socket does NOT perform IAM auth —
it only exposes the socket. With `cloudsql.iam_authentication` enabled on the
instance, Postgres asks for a cleartext password (the short-lived OAuth2 token),
so a plain asyncpg connection sends `password=None` and crashes with
`'NoneType' object has no attribute 'encode'`.

The Cloud SQL Python Connector mints and auto-refreshes that token, connecting to
the instance's private IP through the VPC connector. The IAM DB username is the
service-account email without the `.gserviceaccount.com` suffix
(e.g. `inventory-dev-sa@inference-expt.iam`).

For local development (no connection_name) we fall back to a plain asyncpg DSN
against a cloud-sql-proxy on 127.0.0.1:5432.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator, Optional

import asyncpg
from google.cloud.sql.connector import Connector, IPTypes
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

logger = logging.getLogger(__name__)


class Database:
    def __init__(self, *, user: str, name: str, connection_name: Optional[str], host_base: str) -> None:
        self._connector: Optional[Connector] = None

        if connection_name:
            # "lazy" refresh suits serverless (Cloud Run) where background tasks
            # may be frozen between requests; the token is refreshed on demand.
            self._connector = Connector(refresh_strategy="lazy")

            async def getconn() -> asyncpg.Connection:
                return await self._connector.connect_async(
                    connection_name,
                    "asyncpg",
                    user=user,
                    db=name,
                    enable_iam_auth=True,
                    ip_type=IPTypes.PRIVATE,
                )

            self.engine = create_async_engine(
                "postgresql+asyncpg://",
                async_creator=getconn,
                pool_size=4,
                max_overflow=4,
                pool_pre_ping=True,
            )
        else:
            # Local development against cloud-sql-proxy on 127.0.0.1:5432.
            dsn = f"postgresql+asyncpg://{user}@127.0.0.1:5432/{name}"
            self.engine = create_async_engine(dsn, pool_size=4, max_overflow=4, pool_pre_ping=True)

        self.session_factory = async_sessionmaker(self.engine, expire_on_commit=False, class_=AsyncSession)

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        async with self.session_factory() as s:
            yield s

    async def close(self) -> None:
        await self.engine.dispose()
        if self._connector is not None:
            await self._connector.close_async()
