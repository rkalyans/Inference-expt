# agent-orchestrator

The Stylist agent's runtime. Receives chat requests, calls tools (weather,
inventory, history), and streams a recommendation back as Server-Sent Events.

## LLM modes

| Mode | When | Behavior |
|---|---|---|
| `stub` | Phase 1.3 first deploy, integration tests | Deterministic flow: `get_weather` → `search_inventory` → rule-based pick. No LLM required. |
| `openai` | Phase 1.2 onwards (vLLM up) | ChatOpenAI with tool calling against `LLM_BASE_URL`. Loop bounded by `MAX_TOOL_CALLS`. |

## Endpoints

| Method | Path | Notes |
|---|---|---|
| GET | `/api/health` | liveness (renamed from `/healthz` — Cloud Run GFE intercepts `/healthz`) |
| POST | `/chat` | SSE stream of `{event, data}` frames |

`/chat` body:

```json
{ "user_id": "<uuid>", "query": "what should I wear?", "zone": "midtown" }
```

SSE event types: `thought | tool_call | tool_result | final | error | saved`.

## Required env

| Var | Source |
|---|---|
| `APP_ENV` | Cloud Run |
| `INVENTORY_BASE_URL` | terraform output of `inventory` Cloud Run service URI |
| `WEATHER_BASE_URL` | terraform output of `weather` Cloud Run service URI |
| `FIRESTORE_DATABASE` | `stylist-<env>` |
| `SESSIONS_BUCKET` | `stylist-<env>-agent-sessions` |
| `LLM_MODE` | `stub` (default) or `openai` |
| `LLM_BASE_URL` | vLLM URL when `LLM_MODE=openai` |
| `LLM_MODEL` | e.g. `mistralai/Mistral-7B-Instruct-v0.3` |

The runtime SA needs `roles/run.invoker` on the inventory and weather
services (granted in env Terraform).
