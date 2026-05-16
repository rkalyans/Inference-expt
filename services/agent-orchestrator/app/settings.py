from functools import lru_cache
from typing import Literal, Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", populate_by_name=True)

    app_env: str = "dev"
    app_name: str = "stylist-agent"
    project_id: str = "inference-expt"
    region: str = "us-east4"

    # Internal service URLs (Cloud Run -> Cloud Run, OIDC-authenticated).
    inventory_base_url: Optional[str] = None
    weather_base_url: Optional[str] = None

    # Firestore database name (`stylist-<env>`).
    firestore_database: str = "stylist-dev"

    # GCS bucket where the agent persists per-session filesystem state.
    sessions_bucket: Optional[str] = None

    # Brain. Three modes:
    #   stub  : deterministic responses, no LLM (default for first deploy)
    #   openai: ChatOpenAI against LLM_BASE_URL (vLLM compatible)
    llm_mode: Literal["stub", "openai"] = "stub"
    llm_base_url: Optional[str] = None
    llm_model: str = "mistralai/Mistral-7B-Instruct-v0.3"
    llm_api_key: str = "not-needed-for-vllm"
    llm_temperature: float = 0.3
    llm_max_tokens: int = 512

    # Tool-loop guard (Phase 2.5 alarm at >15).
    max_tool_calls: int = 10

    # Firebase project id used to verify ID tokens. Same as `project_id` in
    # production (one Firebase project per GCP project), but we keep it separate
    # so dev can point at a shared "firebase-dev" project if needed.
    firebase_project_id: Optional[str] = None

    # Comma-separated origins for CORS. Empty -> "*".
    cors_allow_origins_raw: str = Field(default="", alias="CORS_ALLOW_ORIGINS")

    @property
    def cors_allow_origins(self) -> list[str]:
        return [o.strip() for o in self.cors_allow_origins_raw.split(",") if o.strip()]

    # Langfuse tracing (Phase 0 already wired). Optional.
    langfuse_public_key: Optional[str] = None
    langfuse_secret_key: Optional[str] = None
    langfuse_host: Optional[str] = None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
