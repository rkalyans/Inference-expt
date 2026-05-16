from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "dev"
    app_name: str = "stylist-inventory"
    project_id: str = "inference-expt"
    region: str = "us-east4"

    # Postgres connection — Cloud Run uses /cloudsql/<conn> unix socket via the
    # cloudsql_connection_name volume. We always connect with IAM auth so the
    # password is never needed in the runtime.
    db_user: Optional[str] = None  # e.g. agent-orch-dev-sa@inference-expt.iam
    db_name: str = "stylist"
    db_host: str = "/cloudsql"      # base path; appended with connection name
    db_connection_name: Optional[str] = None  # <project>:<region>:<instance>

    # Bucket for clothing photo uploads.
    clothing_bucket: Optional[str] = None
    signed_url_ttl_seconds: int = 60 * 15

    # Vision/embedding integrations (Phase 1.2). Optional for now.
    triton_base_url: Optional[str] = None
    qdrant_base_url: Optional[str] = None
    qdrant_collection: str = "clothing_items"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
