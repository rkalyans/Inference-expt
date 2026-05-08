"""Phase 0 smoke-test service.

Validates that:
- A container can be built and pushed to Artifact Registry by Cloud Build
- It can be deployed to Cloud Run with mandatory labels
- Cloud Run domain mapping resolves the env subdomain (dev/staging/app .quantum-23.com)
- Cloud Logging picks up structured logs
- Cloud Monitoring receives request_count metric

Intentionally minimal — no external dependencies beyond FastAPI + uvicorn.
"""
from __future__ import annotations

import json
import logging
import os
import sys
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


def _configure_logging() -> None:
    """JSON structured logging compatible with Cloud Logging."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:  # noqa: D401
        payload = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


_configure_logging()
log = logging.getLogger("stylist-hello")

APP_ENV = os.getenv("APP_ENV", "unknown")
APP_NAME = os.getenv("APP_NAME", "stylist-hello")
VERSION = os.getenv("VERSION", "0.1.0")

app = FastAPI(title=APP_NAME, version=VERSION)


@app.get("/")
async def root() -> dict:
    log.info("root_request", extra={"env": APP_ENV})
    return {
        "service": APP_NAME,
        "env": APP_ENV,
        "version": VERSION,
        "message": "NYC Stylist Agent — Phase 0 smoke test is live.",
    }


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "env": APP_ENV}


@app.get("/readyz")
async def readyz() -> dict:
    return {"status": "ready", "env": APP_ENV}


@app.get("/echo")
async def echo(request: Request) -> JSONResponse:
    return JSONResponse(
        {
            "headers": dict(request.headers),
            "method": request.method,
            "url": str(request.url),
            "env": APP_ENV,
        }
    )
