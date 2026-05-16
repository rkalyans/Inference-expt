# inventory-api

CRUD for users and their clothing items. Backed by Cloud SQL (Postgres 15)
via the Cloud Run unix-socket integration. Photo uploads use V4 signed PUT
URLs minted by the runtime service account.

| Method | Path | Notes |
|---|---|---|
| GET | `/healthz` | liveness |
| POST | `/users` | get-or-create by email |
| POST | `/items?user_id=...` | create item (photo URL optional) |
| GET | `/items?user_id=...&category=...` | list items |
| GET | `/items/{id}?user_id=...` | fetch one |
| PUT | `/items/{id}?user_id=...` | update |
| DELETE | `/items/{id}?user_id=...` | delete |
| POST | `/items/upload-url` | mint a signed PUT URL for the clothing-photos bucket |

Auto-tagging via CLIP/FashionCLIP runs in Phase 1.2 once Triton is up; the
Cloud Run env vars `TRITON_BASE_URL` and `QDRANT_BASE_URL` will activate it.

## Required env

| Var | Source |
|---|---|
| `APP_ENV` | Cloud Run |
| `DB_USER` | runtime SA email **without** `.gserviceaccount.com` (Postgres IAM auth) |
| `DB_NAME` | `stylist` |
| `DB_CONNECTION_NAME` | `<project>:<region>:stylist-<env>-pg` |
| `CLOTHING_BUCKET` | `stylist-<env>-clothing-photos` |

## Ingress / IAM

The service is private (`ingress=INGRESS_TRAFFIC_ALL` but no public invoker
binding). Only the agent orchestrator's runtime SA holds `roles/run.invoker`.
