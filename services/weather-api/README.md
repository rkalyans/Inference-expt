# weather-api

NYC-aware weather tool for the Stylist agent. Single endpoint:

```
GET /weather?zone=<midtown|waterfront|downtown|uptown>[&forecast=true]
```

Behavior:

1. Cache hit (Redis) → return immediately.
2. OpenWeatherMap call → adjust for microclimate → cache → return.
3. Fall back to Open-Meteo (no key) → adjust → cache → return.
4. If both upstreams fail, return HTTP 502 (do not cache failures).

Environment:

| Var | Source |
|---|---|
| `APP_ENV` | Cloud Run env var |
| `PROJECT_ID` | Cloud Run env var (defaults to `inference-expt`) |
| `REDIS_HOST` / `REDIS_PORT` | from `module.memorystore` outputs |
| `REDIS_AUTH_SECRET_ID` | resolved at boot via Secret Manager |
| `OPENWEATHERMAP_SECRET_ID` | default `openweathermap-api-key` |

The service is private (no `--allow-unauthenticated`); only the Agent
Orchestrator's service account can invoke it via `roles/run.invoker`.
