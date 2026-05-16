from functools import lru_cache
from typing import Optional

from google.cloud import secretmanager
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Values come from env vars (Cloud Run injects)."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "dev"
    app_name: str = "stylist-weather"
    project_id: str = "inference-expt"

    # Redis private host/port from terraform output, mounted as env vars.
    redis_host: Optional[str] = None
    redis_port: int = 6378
    # Either provide the AUTH inline or pass the secret id and we resolve at boot.
    redis_auth: Optional[str] = None
    redis_auth_secret_id: Optional[str] = None

    # OpenWeatherMap key — pulled from Secret Manager.
    openweathermap_secret_id: str = "openweathermap-api-key"
    openweathermap_api_key: Optional[str] = None  # populated at boot

    current_ttl_seconds: int = 15 * 60
    forecast_ttl_seconds: int = 60 * 60
    http_timeout_seconds: float = 5.0


def _read_secret(project_id: str, secret_id: str) -> Optional[str]:
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
        return client.access_secret_version(name=name).payload.data.decode("utf-8")
    except Exception:  # pragma: no cover -- bootstrap-only path
        return None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    s = Settings()
    if s.redis_auth is None and s.redis_auth_secret_id:
        s.redis_auth = _read_secret(s.project_id, s.redis_auth_secret_id)
    if s.openweathermap_api_key is None:
        s.openweathermap_api_key = _read_secret(s.project_id, s.openweathermap_secret_id)
    return s
