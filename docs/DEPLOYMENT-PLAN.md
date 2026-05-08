# NYC Stylist Agent — Phased Deployment Plan

> Companion to `ARCHITECTURE-AGENTIC.md` (the golden architecture template).
> This document provides concrete, ordered steps to ship the system to GCP across
> three phases. Every component runs in GCP — nothing local in production.

---

## Deployment Philosophy

| Principle | What It Means |
|-----------|---------------|
| **Infra-first** | Provision GCP resources via Terraform before any app code is deployed |
| **Vertical slices** | Each phase delivers a working end-to-end experience, not horizontal layers |
| **Promote through environments** | `dev` → `staging` → `prod`, each in its own GCP project |
| **Everything in CI/CD** | No `gcloud` commands run by hand after Phase 0; all changes flow through Cloud Build |
| **Observability from day one** | Logging, tracing, and metrics enabled before features are added |
| **Reversible** | Every deploy is a versioned container; rollback is one command |

---

## Confirmed Account & Resource Inputs

| Resource | Value | Notes |
|----------|-------|-------|
| **GCP Billing Account** | `Billing-Account-Agentic` | Linked to the single project |
| **GCP Project** | `inference-expt` (existing, **no pre-existing allocations**) | All three environments live in this single project |
| **Cloud Domain** | `quantum-23.com` | Registered via Cloud Domains; used for all public endpoints |
| **Weather Provider** | OpenWeatherMap (account provisioned) | API key stored in Secret Manager as `openweathermap-api-key` |
| **Data Scope** | Clothing photos + minimal account metadata only | **No PII** beyond user email (auth identifier); no photos of people, no addresses, no payment data |

## Data Scope & Privacy Boundary (Locked)

This is a **hard scope constraint** that drives architectural decisions throughout:

| Allowed | Not Allowed |
|---------|-------------|
| Photos of clothing items (no people in frame) | Photos containing people, faces, or identifying backgrounds |
| User email (Firebase Auth identifier only) | Names, addresses, phone numbers, payment info |
| Outfit selections + ratings | Health, biometric, or location history data |
| NYC DOT public street frames (transient, aggregated to trend vectors only) | Persisted images of identifiable individuals from street feeds |

**Enforcement mechanisms:**
- DLP scan on every uploaded clothing photo → reject if a person is detected
- Street feed pipeline: faces blurred at ingestion, raw frames deleted within 24h, only aggregate trend vectors persisted
- Schema-level: Cloud SQL has zero PII columns by design (no `name`, `address`, `phone`, etc.)
- Auth: email is the only user identifier; never logged outside Firebase

## Environments

All three environments run in the **same GCP project** (`inference-expt`). Isolation is enforced via **resource naming**, **GKE namespaces**, **separate VPC subnets**, and **IAM conditions on environment labels** — not project boundaries.

| Env | Resource Prefix | GKE Namespace | VPC Subnet | Purpose | Public URL |
|-----|-----------------|----------------|-------------|---------|------------|
| **dev** | `stylist-dev-*` | `stylist-dev` | `10.10.0.0/20` | Active development, breakable | `dev.quantum-23.com` |
| **staging** | `stylist-staging-*` | `stylist-staging` | `10.20.0.0/20` | Pre-prod validation, load tests | `staging.quantum-23.com` |
| **prod** | `stylist-prod-*` | `stylist-prod` | `10.30.0.0/20` | Live system | `app.quantum-23.com` / `api.quantum-23.com` |

Each env applies the same Terraform module with different variables (sizing, scaling, secret aliases). Resource labels `env=dev|staging|prod` and `app=stylist-agent` are mandatory on every resource for cost attribution and IAM scoping.

### Single-Project Tradeoffs & Mitigations

| Tradeoff | Mitigation |
|----------|------------|
| Smaller blast radius than multi-project | Separate GKE namespaces with NetworkPolicies; separate Cloud SQL instances; per-env service accounts with IAM Conditions on `resource.labels.env` |
| Quota contention across envs | Per-env resource caps in Terraform; Cloud Run max-instances cap per env; GKE node pools tagged per env |
| Harder to grant scoped IAM | Use IAM Conditions: e.g., engineer SA can only act on resources where `resource.labels.env=dev` |
| Cost attribution complexity | Mandatory labels + BigQuery billing export + per-env dashboards |
| Accidental cross-env access | Distinct subnets + private service connect per env; Firebase project per env (separate auth tenants) |

---

# Phase 0 — Foundation (Week 1)

**Goal:** GCP organization, projects, IAM, Terraform state, CI/CD pipeline. No application code yet.

## 0.1 GCP Project Setup

**Steps:**
1. Use existing GCP project `inference-expt` (confirmed empty — no pre-existing allocations)
2. Verify billing account `Billing-Account-Agentic` is linked to `inference-expt`
3. Set **per-environment budget alerts** on `Billing-Account-Agentic` using label filters (`env=dev`, `env=staging`, `env=prod`) at 50% / 80% / 100% thresholds
4. Register / verify domain `quantum-23.com` via **Cloud Domains** in `inference-expt`; create a single Cloud DNS managed zone with subdomains for each env
5. Enable required APIs (one-time, project-wide):
   - `run.googleapis.com`
   - `container.googleapis.com` (GKE)
   - `sqladmin.googleapis.com`
   - `firestore.googleapis.com`
   - `storage.googleapis.com`
   - `bigquery.googleapis.com`
   - `secretmanager.googleapis.com`
   - `cloudbuild.googleapis.com`
   - `artifactregistry.googleapis.com`
   - `aiplatform.googleapis.com`
   - `redis.googleapis.com`
   - `cloudscheduler.googleapis.com`
   - `cloudfunctions.googleapis.com`
   - `pubsub.googleapis.com`

## 0.2 IAM & Service Accounts

Since all envs share one project, every service account is **per-environment** and granted access **only** to resources with the matching `env` label via IAM Conditions.

| Service Account | Role | Used By | IAM Condition |
|-----------------|------|---------|---------------|
| `terraform-sa` | Project Editor | Terraform CI | None (admin) |
| `cloudbuild-sa` | Cloud Build SA + Cloud Run Admin + Artifact Registry Writer | Cloud Build pipelines | None |
| `agent-orch-{env}-sa` | Cloud SQL Client, Firestore User, GCS Object Admin, Secret Accessor | Agent Cloud Run service per env | `resource.labels.env == "{env}"` |
| `inference-{env}-sa` | GCS Object Reader, Artifact Registry Reader | GKE inference pods per env (Workload Identity) | `resource.labels.env == "{env}"` |
| `street-feed-{env}-sa` | GCS Writer, Pub/Sub Publisher | Street feed Cloud Function per env | `resource.labels.env == "{env}"` |
| `training-sa` | BigQuery Reader, GCS Object Admin | LoRA training jobs (prod-only) | `resource.labels.env == "prod"` |

Engineer human accounts get `dev`-scoped roles only; staging/prod access requires break-glass approval.

## 0.3 Terraform Bootstrap

```
infra/
├── modules/
│   ├── network/           (VPC, per-env subnets, Cloud NAT, Private Service Connect)
│   ├── gke-inference/     (GKE Autopilot cluster + GPU node pool, env-scoped)
│   ├── cloud-run-service/ (reusable Cloud Run module)
│   ├── data/              (Cloud SQL instance, Firestore database, BigQuery, Memorystore — all env-suffixed)
│   ├── storage/           (GCS buckets, Artifact Registry)
│   ├── dns/               (Cloud DNS records, managed SSL certs — applied once)
│   ├── iam/               (per-env service accounts with IAM Conditions)
│   └── observability/     (Langfuse on GKE, log sinks, alerting)
├── envs/
│   ├── shared/main.tf     (project-wide: VPC, DNS zone, Artifact Registry, Langfuse)
│   ├── dev/main.tf        (env=dev resources within inference-expt)
│   ├── staging/main.tf    (env=staging resources within inference-expt)
│   └── prod/main.tf       (env=prod resources within inference-expt)
└── backend.tf             (GCS remote state)
```

**Steps:**
1. Manually create one-time TF state bucket in `inference-expt`: `gs://inference-expt-tf-state` (versioning ON, uniform bucket-level access)
2. Grant `terraform-sa` Storage Object Admin on the state bucket
3. Configure remote backend pointing at `gs://inference-expt-tf-state` with per-stack prefixes (`shared/`, `dev/`, `staging/`, `prod/`)
4. Apply `shared` stack first — creates the VPC, DNS managed zone for `quantum-23.com`, Artifact Registry, and shared observability
5. Apply `dev` stack — creates `stylist-dev-*` resources within the shared VPC subnet `10.10.0.0/20`
6. Apply `staging` stack — same module, subnet `10.20.0.0/20`
7. Apply `prod` stack — same module, subnet `10.30.0.0/20`, with stricter sizing/SLA inputs
8. Verify zero drift via `terraform plan` in each stack
9. Confirm `env` and `app=stylist-agent` labels are present on every created resource (CI check)

## 0.4 CI/CD Pipeline (Cloud Build)

**Trigger model:**
| Event | Action |
|-------|--------|
| PR to `main` | Run tests, `terraform plan`, build container, deploy to `dev` |
| Merge to `main` | Deploy to `staging`, run smoke tests |
| Tag `v*.*.*` | Deploy to `prod` (manual approval gate) |

**Cloud Build config files:**
- `cloudbuild-infra.yaml` — `terraform fmt/validate/plan/apply`
- `cloudbuild-frontend.yaml` — Build Next.js, deploy to Cloud Run
- `cloudbuild-backend.yaml` — Build FastAPI services, deploy to Cloud Run
- `cloudbuild-inference.yaml` — Build vLLM/Triton images, deploy to GKE via Helm

## 0.5 Observability Foundation

**Steps:**
1. Enable Cloud Logging and Cloud Monitoring (default in new projects)
2. Create log sinks: errors → BigQuery dataset `ops_analytics` for analysis
3. Set up alerting policies:
   - Cloud Run 5xx rate > 1% → Slack #alerts
   - GKE GPU pod restart loop → PagerDuty
   - Cloud SQL connection failures → email
   - Billing on `Billing-Account-Agentic` > budget threshold → email + Slack
4. Deploy **Langfuse** (open-source) to GKE on a small CPU pod for agent tracing
   - Internal endpoint: `langfuse.internal.quantum-23.com` (private DNS)
5. Store Langfuse keys + OpenWeatherMap API key in Secret Manager (no plaintext anywhere):
   - `openweathermap-api-key`
   - `langfuse-public-key`
   - `langfuse-secret-key`

## 0.6 Phase 0 Exit Criteria

- [ ] `inference-expt` linked to `Billing-Account-Agentic`
- [ ] `quantum-23.com` registered in Cloud Domains, managed zone live in `inference-expt`, NS records propagated
- [ ] Terraform applies cleanly to `shared`, `dev`, `staging`, `prod` stacks with no drift
- [ ] All resources carry mandatory labels (`env`, `app=stylist-agent`); CI check enforces this
- [ ] Cloud Build can build and push a "hello world" container to Artifact Registry
- [ ] Cloud Build can deploy that container to Cloud Run in dev (`dev.quantum-23.com` resolves)
- [ ] Logs and metrics flowing to Cloud Monitoring with env-scoped dashboards
- [ ] Langfuse reachable via internal endpoint
- [ ] OpenWeatherMap API key validated against the API and stored in Secret Manager
- [ ] All secrets stored in Secret Manager (no secrets in code/Terraform/env files)
- [ ] Per-env budget alerts active (label-filtered)
- [ ] DLP API enabled and a sample person-detection rule tested against a clothing photo
- [ ] IAM Conditions verified: `agent-orch-dev-sa` cannot read prod resources

**Estimated cost so far:** ~$30/mo (idle infra)

---

# Phase 1 — Agent MVP (Weeks 2–5)

**Goal:** A user can log in, manage their inventory, ask the Stylist Agent for an outfit, and receive a reasoned recommendation. Single-agent implementation, basic tools, no street feed yet.

## 1.1 Data Layer Provisioning (Week 2)

**Terraform modules to apply:**
- `data/cloud-sql` → PostgreSQL 15, `db-f1-micro` for dev, `db-custom-2-7680` for prod
- `data/firestore` → Native mode, multi-region for prod
- `data/memorystore` → Redis 6, basic tier 1GB
- `data/bigquery` → Datasets: `analytics`, `training_data`, `ops_analytics`
- `storage/buckets`:
  - `stylist-{env}-clothing-photos`
  - `stylist-{env}-model-weights`
  - `stylist-{env}-agent-sessions` (filesystem backend)
  - `stylist-{env}-street-feed-frames`
  
  Where `{env}` is one of `dev`, `staging`, `prod` — all within the `inference-expt` project.

**Database schemas applied via Cloud Build migration job:**
```
users               (id, email, created_at, preferences_jsonb)
clothing_items      (id, user_id, name, category, attributes_jsonb,
                     photo_url, qdrant_point_id, created_at)
recommendations     (id, user_id, request_jsonb, response_jsonb,
                     rating, trace_id, created_at)
agent_sessions      (id, user_id, status, gcs_path, trace_id, created_at)
feedback_events     (id, recommendation_id, event_type, payload_jsonb, created_at)
```

## 1.2 GKE Inference Cluster (Week 2)

**Steps:**
1. Apply `gke-inference` Terraform module:
   - GKE Autopilot cluster (private, authorized networks for Cloud Run egress)
   - GPU node pool: 1× `nvidia-l4` (24GB), spot=true for dev, on-demand for prod
   - Workload Identity enabled for pod → GCS auth
2. Install via Helm:
   - **vLLM** — Mistral-7B-Instruct AWQ 4-bit (the agent brain)
   - **vLLM** — LLaVA-NeXT-13B AWQ 4-bit (vision tasks, called as tool)
   - **Triton** — YOLOv8 + SAM-2 + CLIP + FashionCLIP (TensorRT optimized)
   - **Qdrant** — vector DB, 50GB persistent volume
3. Download model weights to GCS bucket `stylist-{env}-model-weights`
4. Pods pull weights from GCS at startup via init container (no embedded weights in images)
5. Verify:
   - `curl` vLLM endpoint with chat completion → response in <1s
   - Triton model status = READY for all 4 vision models
   - Qdrant `/healthz` returns 200

## 1.3 Backend Services (Week 3)

### Service: Inventory Tool API
- FastAPI on Cloud Run
- Endpoints:
  - `POST /items` — upload photo + metadata; auto-tags via CLIP/FashionCLIP
  - `GET /items` — search with filters (category, color, warmth, formality)
  - `GET /items/{id}`
  - `PUT /items/{id}`
  - `DELETE /items/{id}`
- Calls Triton for embeddings, stores in Qdrant + Cloud SQL

### Service: Weather Tool API
- FastAPI on Cloud Run
- Endpoints:
  - `GET /weather?zone=midtown&start=...&end=...`
- Backend: OpenWeatherMap (key `openweathermap-api-key` in Secret Manager) + Open-Meteo fallback for resilience
- Applies microclimate adjustments per zone (waterfront / midtown / downtown / uptown)
- Cached in Redis (15 min TTL for current, 1 hr for forecast)

### Service: Agent Orchestrator (the brain)
- FastAPI on Cloud Run
- Uses LangChain `deepagents` package
- Connects to vLLM via OpenAI-compatible client
- Tools wired:
  - `get_weather` → calls Weather Tool API
  - `search_inventory` → calls Inventory Tool API
  - `compute_similarity` → direct Qdrant query
  - `get_user_history` → Firestore read
  - `save_recommendation` → Firestore write + Cloud SQL insert
  - `ask_user` → returns interrupt to frontend (human-in-the-loop)
- **Filesystem backend:** GCS (`stylist-{env}-agent-sessions`)
- **Memory store:** Firestore via LangGraph store adapter
- **Tracing:** Langfuse SDK initialized at boot
- Streams responses to frontend via Server-Sent Events (SSE)

## 1.4 Frontend (Weeks 3–4)

**Next.js 14 on Cloud Run:**
- Pages:
  - `/login` — Firebase Auth (Google sign-in)
  - `/inventory` — CRUD UI; photo upload to GCS via signed URLs
  - `/chat` — main interface; streams agent responses
  - `/history` — past recommendations + ratings
- Components: shadcn/ui, TailwindCSS, Lucide icons
- Calls Agent Orchestrator via `/api` route handlers (server-side, includes auth token)

## 1.5 Auth (Week 4)

**Firebase Authentication** (separate Firebase project per env to keep auth tenants isolated even within the single GCP project):
- Google sign-in (extensible to email/password later)
- Identity token forwarded to Cloud Run services via `Authorization` header
- Cloud Endpoints validates JWT before reaching backend
- User ID extracted from token claim, used for row-level scoping in all queries
- **Email is the only PII collected** — stored once in `users` table, never logged

## 1.6 End-to-End Flow Test (Week 4)

Manually validate in dev:
1. User signs in
2. Uploads 5 clothing items → confirms auto-tags appear
3. Asks: *"What should I wear tomorrow at 3pm in Midtown for a casual lunch?"*
4. Agent: calls weather → gets forecast → searches inventory → reasons → returns recommendation with rationale
5. User rates the recommendation
6. Trace visible in Langfuse showing all tool calls and reasoning steps

## 1.7 Promote to Staging & Prod (Week 5)

**Steps:**
1. Tag release `v0.1.0`
2. Cloud Build deploys to staging (`staging.quantum-23.com`)
3. Run smoke tests + Playwright E2E suite
4. Manual approval → deploy to prod
5. Bind Google-managed SSL certs to `app.quantum-23.com` and `api.quantum-23.com`
6. Enable Cloud Armor on prod load balancer
7. Configure Cloud CDN for static frontend assets

## 1.8 Phase 1 Exit Criteria

- [ ] User can sign in, manage inventory, and get an outfit recommendation
- [ ] Agent reasoning visible end-to-end in Langfuse traces
- [ ] All services running on Cloud Run / GKE in prod
- [ ] P95 latency < 8 seconds end-to-end
- [ ] Zero secrets in source code; all in Secret Manager
- [ ] Uptime > 99% over a 7-day soak test

**Estimated prod cost:** ~$350–450/mo (1× L4 GPU on prod, scale-to-zero on dev)

---

# Phase 2 — Multi-Agent + Street Intelligence (Weeks 6–10)

**Goal:** Add subagents (Weather Analyst, Street Scout, Wardrobe Manager), deploy the street feed pipeline, integrate trends into recommendations, and begin LoRA fine-tuning on user feedback.

## 2.1 Subagent Implementation (Week 6)

**Refactor Agent Orchestrator:**
- Promote single Stylist agent into root + subagents:
  - `weather_agent` — uses `get_weather` tool
  - `street_scout` — uses `get_street_trends` tool
  - `wardrobe_agent` — uses `search_inventory` + `rate_outfit_coherence`
- Use Deep Agents `task` tool for subagent spawning
- Each subagent writes findings to `/session/{id}/*.json` on the GCS filesystem
- Root agent reads all findings before final synthesis
- All subagents share the same vLLM endpoint (different system prompts)

## 2.2 Street Feed Pipeline (Weeks 6–8)

### 2.2.1 Camera Frame Ingestion
- **Cloud Function** (HTTP trigger from Cloud Scheduler every 15 min)
- For each NYC zone (waterfront, midtown, downtown, uptown):
  - Pull MJPEG frame from configured NYC DOT cameras
  - Save to `gs://stylist-{env}-street-feed-frames/{zone}/{timestamp}.jpg`
  - Publish Pub/Sub message: `{ zone, timestamp, frame_uri }`

### 2.2.2 Frame Processing Worker
- **GKE deployment** (CPU pod, scales 0–3 via KEDA on Pub/Sub backlog)
- Subscribes to Pub/Sub topic `street-frames`
- For each frame:
  1. Call Triton **YOLOv8** → list of person bounding boxes
  2. Call Triton **SAM-2** → segmented person crops (alpha-masked)
  3. For each crop, call vLLM **LLaVA-NeXT**: *"Describe the outfit this person is wearing"*
  4. Call Triton **FashionCLIP** → embedding per outfit description
- Aggregate: average embeddings → trend vector for `(zone, timestamp)`
- Store in Qdrant collection `street_trends` with metadata

### 2.2.3 Street Trends Tool API
- New FastAPI service on Cloud Run
- `GET /trends?zone=...&time=now`
- Queries Qdrant for the most recent trend vector for that zone
- Returns aggregated description + embedding + sample outfit descriptions

### 2.2.4 Wire into Agent
- Root agent's planner now considers spawning `street_scout` subagent
- Decision rule in system prompt: *"Spawn `street_scout` if occasion is social and weather is ambiguous (50–70°F)"*

## 2.3 LoRA Fine-Tuning Pipeline (Week 9)

**Components:**
1. **BigQuery view** `training_data.outfit_feedback`
   - Joins `recommendations` + `feedback_events` into prompt/completion pairs
2. **Cloud Scheduler** (weekly trigger)
   - Triggers Cloud Build job
   - Job spins up GKE Spot GPU pod (A100 if available, fallback L4)
   - Runs **QLoRA** training via Axolotl on last 7 days of feedback
   - Outputs adapter to `gs://stylist-prod-model-weights/lora/v{timestamp}/`
   - Triggers vLLM rolling restart with new adapter mounted
3. **Validation gate**
   - Hold-out test set evaluation before promoting new adapter
   - If win rate < baseline + 2%, skip promotion (auto-rollback)

## 2.4 Shopping Suggestion Tool (Week 9)

- New tool service on Cloud Run
- `POST /suggest_purchase { gap_description, budget_range }`
- Uses FashionCLIP to embed gap description
- Searches a product catalog (initially a curated dataset in BigQuery)
- Returns top 5 matches ranked by `style_distance + price_fit`

## 2.5 Observability Hardening (Week 10)

**Add:**
- Per-tool latency dashboards in Cloud Monitoring
- Agent loop count alarm (>15 tool calls = potential runaway)
- Daily cost report by service (BigQuery export of billing data)
- Langfuse cost-per-conversation tracking
- User-feedback-correlated trace search (find traces of bad recommendations)

## 2.6 Phase 2 Exit Criteria

- [ ] Multi-agent orchestration working in prod
- [ ] Street feed pipeline ingesting + processing every 15 min
- [ ] Trend data influencing recommendations (validated via A/B test)
- [ ] First LoRA adapter trained on real user data and deployed
- [ ] Shopping suggestions returning relevant items
- [ ] P95 latency still < 12 seconds despite added subagents

**Estimated prod cost:** ~$600–800/mo (added street feed GPU usage + scheduled training)

---

# Phase 3 — Personalization & Scale (Weeks 11–16)

**Goal:** Production-grade personalization, conversational refinement, multi-stop day planning, and public launch readiness.

## 3.1 Advanced Memory (Week 11)

- Pattern detection job (BigQuery + scheduled Cloud Function)
- Identifies user-specific patterns:
  - *"User picks dark colors after 6pm"*
  - *"User avoids high-formality items on weekends"*
  - *"User runs cold (selects warmer than weather suggests)"*
- Stored as structured memory entries in Firestore
- Surfaced to root agent via expanded `get_user_history` tool

## 3.2 Skills System (Week 12)

**Create `skills/` directory in agent codebase:**
- `nyc_microclimate.md`
- `outfit_combination.md`
- `color_harmony.md`
- `formality_matching.md`
- `multi_stop_planning.md` (NEW)
- `weather_transition.md` (NEW)

Skills loaded at agent boot via Deep Agents skills feature.

## 3.3 Conversational Refinement (Week 13)

- Frontend: maintain `session_id` across turns
- Agent: GCS filesystem persists session state across requests
- User can say *"actually make it more casual"* or *"what about with the brown shoes?"*
- Agent loads previous turn's candidates from GCS and adjusts

## 3.4 Multi-Stop Day Planning (Week 14)

- New request schema: list of `(location, time, occasion)` stops
- Agent plans cross-stop optimization:
  - Find core items that work everywhere
  - Identify swap items if needed (shoes, jacket)
  - Build a packing/wearing strategy with transition timing

## 3.5 Load Testing & Auto-Scaling (Week 15)

**Tooling:** Locust or k6
**Targets:**
- 100 concurrent users sustained
- 500 RPS burst capacity

**Tune:**
- vLLM batch size and concurrent request limit
- Cloud Run min instances (warm pool of 2 for prod)
- GKE HPA targets (GPU utilization 70%)

**Document SLOs:**
- 99% requests < 15s end-to-end
- 99.5% uptime over 30 days

## 3.6 Security Hardening (Week 15)

- Penetration test (third party or internal red team)
- VPC Service Controls perimeter scoped to prod resources (using resource labels) within `inference-expt`
- Cloud Armor WAF rules (OWASP Top 10)
- Audit logging enabled across all services
- **DLP scan on every uploaded clothing photo** — reject upload if a person is detected (enforces no-PII scope)
- **Street feed face-blurring + 24h frame retention** verified in production
- Per-user rate limiting via Cloud Endpoints quota
- Schema audit: confirm no PII columns exist in Cloud SQL or Firestore (automated scan)

## 3.7 Public Launch Prep (Week 16)

- DNS + SSL via Google-managed certificates (already provisioned in Phase 1.7)
- Custom domain: `app.quantum-23.com` → Cloud Run frontend
- API: `api.quantum-23.com` → Cloud Endpoints
- Status page: `status.quantum-23.com` (self-hosted on GKE or statuspage.io)
- Privacy policy + ToS hosted at `quantum-23.com/privacy` and `/terms`
- GDPR/CCPA data export + deletion endpoints
- Analytics: privacy-respecting (Plausible, self-hosted at `analytics.quantum-23.com`)

## 3.8 Phase 3 Exit Criteria

- [ ] System handles 100+ concurrent users with P95 < 15s
- [ ] Conversational refinement working across multi-turn sessions
- [ ] Multi-stop day planning validated by 5+ test users
- [ ] Penetration test passed with no critical findings
- [ ] Public launch checklist complete
- [ ] On-call runbook documented and rehearsed

**Estimated prod cost (steady state):** ~$1,200–1,800/mo (depending on traffic)

---

# Cross-Phase Concerns

## Rollback Strategy

| Failure | Rollback |
|---------|----------|
| Bad Cloud Run deploy | `gcloud run services update-traffic` to previous revision (instant) |
| Bad GKE deploy | `helm rollback` to previous release |
| Bad LoRA adapter | Symlink in GCS bucket points to previous version; vLLM hot-reload |
| Bad DB migration | Migrations are forward-only; tested down migration ready before applying up |
| Bad Terraform apply | `terraform state pull` from previous version of state in GCS |

## Disaster Recovery

| Asset | Backup | RTO | RPO |
|-------|--------|-----|-----|
| Cloud SQL | Automated backups, 7-day retention, PITR | 1 hour | 5 min |
| Firestore | Daily export to GCS | 4 hours | 24 hours |
| Qdrant | Snapshot to GCS daily | 2 hours | 24 hours |
| GCS buckets | Versioning + lifecycle rules | Immediate | 0 |
| Model weights | Multi-region GCS bucket | Immediate | 0 |
| Terraform state | GCS versioning | Immediate | 0 |

## Cost Controls

- Budget alerts at 50%, 80%, 100% of monthly budget per project
- Cloud Run: max instances cap per service
- GKE: node pool max-size cap, GPU pod resource limits
- BigQuery: per-query cost ceiling, slot reservations capped
- Cloud SQL: HA disabled in dev/staging
- Spot/preemptible for all batch workloads (training, street feed processing)

## On-Call & Runbooks

**Critical alerts paging on-call:**
- Agent error rate > 5% over 5 min
- vLLM pod down > 2 min
- Cloud SQL primary unreachable
- Auth service 5xx
- Billing > 150% of budget

**Runbooks** (Confluence/Notion):
- *"Agent stuck in loop"* → kill session, review trace, file bug
- *"vLLM OOM"* → scale up GPU node, reduce batch size
- *"Cloud SQL high latency"* → check slow query log, scale tier
- *"Street feed not updating"* → check Cloud Scheduler, Pub/Sub backlog

---

# Timeline Summary

| Week | Phase / Milestone |
|------|-------------------|
| 1 | Phase 0 — Foundation |
| 2 | Phase 1.1–1.2 — Data layer + GKE inference |
| 3 | Phase 1.3–1.4 — Backend services + Frontend |
| 4 | Phase 1.5–1.6 — Auth + E2E test in dev |
| 5 | Phase 1.7–1.8 — Promote to prod, soak test |
| 6 | Phase 2.1 — Subagents |
| 7–8 | Phase 2.2 — Street feed pipeline |
| 9 | Phase 2.3–2.4 — LoRA training + Shopping |
| 10 | Phase 2.5–2.6 — Observability + close phase |
| 11 | Phase 3.1 — Advanced memory |
| 12 | Phase 3.2 — Skills system |
| 13 | Phase 3.3 — Conversational refinement |
| 14 | Phase 3.4 — Multi-stop planning |
| 15 | Phase 3.5–3.6 — Load test + security |
| 16 | Phase 3.7–3.8 — Public launch |

**Total: ~16 weeks from kickoff to public launch.**

---

# Critical Path Dependencies

```
Phase 0 ──▶ Phase 1.1 (Data) ──▶ Phase 1.3 (Backend)
        └─▶ Phase 1.2 (GKE)  ──▶ Phase 1.3 (Backend)
                                          │
                                          ▼
                              Phase 1.4 (Frontend) ──▶ Phase 1.6 (E2E)
                                                              │
                                                              ▼
                                                      Phase 1.7 (Prod)
                                                              │
                            ┌─────────────────────────────────┤
                            ▼                                 ▼
                    Phase 2.1 (Subagents)         Phase 2.2 (Street Feed)
                            │                                 │
                            └────────────┬────────────────────┘
                                         ▼
                                 Phase 2.3 (LoRA)  ← needs feedback data
                                         │
                                         ▼
                                  Phase 3 (Polish)
```

Phase 2.2 (street feed) is the longest single workstream — start it as soon as
Phase 1 hits prod, in parallel with Phase 2.1 subagent work.

---

# Pre-Phase 0 Decisions

## ✅ Resolved

| Item | Decision |
|------|----------|
| **GCP billing account** | `Billing-Account-Agentic` (existing) |
| **GCP project** | `inference-expt` (existing, **no pre-existing allocations**) — hosts dev, staging, and prod within a single project |
| **Environment isolation** | Resource naming (`stylist-{env}-*`), GKE namespaces, separate VPC subnets, IAM Conditions on `env` label; separate Firebase project per env for auth tenant isolation |
| **Domain name** | `quantum-23.com` (registered via Cloud Domains in `inference-expt`) |
| **OpenWeatherMap account** | Provisioned with **One Call API 3.0** subscription (covers current + minute/hourly/daily forecasts + historical). API key stored as Secret Manager entry `openweathermap-api-key`. |
| **Data scope** | **Clothing only.** No PII beyond user email. No photos of people. Street feeds are face-blurred at ingestion, raw frames deleted within 24h, only aggregate trend vectors persisted. DLP enforces this on every upload. |
| **Privacy review** | Resolved by the locked data scope above; documented in the "Data Scope & Privacy Boundary" section |
| **Team structure** | **Single owner** model — one person owns frontend, agent runtime, infra & ML across all phases. CI automation compensates for lack of team specialization. |
| **Approval gate for prod deploys** | **Single owner** is the sole approver via Cloud Build manual approval step on tagged releases. Cloud Build sends Slack/email notification; owner approves or rejects in the GCP console. **Future Phase 4 (post-prod):** replace human approval with an **agentic release gate** — an LLM agent reviews the diff, test results, Langfuse eval scores, and canary metrics, then auto-approves or escalates. |

## ⏳ Still Open

1. **NYC DOT camera access** — confirm public access works from GCP egress IPs; document rate limits. *(See "How to Confirm NYC DOT Camera Access" section below.)*

---

# How to Confirm NYC DOT Camera Access

**Goal:** Verify that we can pull live camera frames from NYC DOT public traffic cameras at the cadence we need (every 15 min × 4 zones = 96 calls/day minimum) from GCP egress IPs, before committing to the street feed pipeline in Phase 2.2.

## Background

NYC DOT operates ~900+ public traffic cameras with still-image (JPEG) endpoints exposed via:
- **Public viewer:** `https://webcams.nyctmc.org/` (web UI, links to per-camera image URLs)
- **Direct image URL pattern:** `https://webcams.nyctmc.org/api/cameras/{camera_id}/image`
- **Metadata API:** `https://webcams.nyctmc.org/api/cameras` (returns list of cameras with `id`, `name`, `latitude`, `longitude`, `area`, `isOnline`)

There is also the legacy `dotsignals.org` endpoint pattern still serving JPEG frames for many cameras.

**Important:** These endpoints are not formally documented as a public API. They are scraped/consumed at the public's risk. NYC DOT may rate-limit, block, or change them without notice. Plan for graceful degradation.

## Verification Checklist (run before Phase 2.2 kickoff)

### Step 1 — Inventory the cameras we need
- [ ] Pull `GET https://webcams.nyctmc.org/api/cameras` from a local machine
- [ ] Filter to our four zones using `latitude`/`longitude` bounding boxes:
  - **Waterfront:** Battery Park, FDR around South St, Brooklyn Bridge approaches
  - **Midtown:** 34th–59th St, 3rd–8th Ave
  - **Downtown:** South of 14th St
  - **Uptown:** North of 96th St
- [ ] Pick 2–3 cameras per zone (redundancy for offline cameras), record their `id` values
- [ ] Confirm each picked camera returns `isOnline: true`

### Step 2 — Validate frame retrieval from a local machine
- [ ] For each chosen `camera_id`:
  ```bash
  curl -I https://webcams.nyctmc.org/api/cameras/{id}/image
  # Expect: HTTP/2 200, Content-Type: image/jpeg
  ```
- [ ] Download the frame and confirm it's a valid JPEG (not an HTML error page)
- [ ] Note the average frame size (typically 30–80 KB)

### Step 3 — Validate from GCP egress
This is the most important check — the public viewer may work from a browser but block server-side IPs.

- [ ] Provision a small Cloud Run service in `inference-expt` (dev env) that just curls each camera URL
- [ ] Deploy and invoke it; confirm 200 + valid JPEG returned
- [ ] If blocked (403/429/connection reset), test via:
  - **Cloud NAT static IP** — some public APIs allow-list specific IPs; we have no relationship with NYC DOT to request this
  - **Direct VPC egress** without NAT — different source IP behavior
  - **Cloud Functions vs Cloud Run** — different egress characteristics
- [ ] Document which approach works

### Step 4 — Rate-limit probe
- [ ] From the GCP egress, hit the same camera at increasing rates:
  - 1 req every 60s for 30 min → expect all 200s
  - 1 req every 15s for 30 min → expect all 200s
  - 1 req every 5s for 10 min → watch for 429 / blocks
- [ ] At our planned rate (1 req every 15 min per camera, ~12 cameras = 0.013 req/s), this should be well under any sane rate limit
- [ ] Record the threshold at which throttling appears

### Step 5 — Stability test (24 hr)
- [ ] Cloud Scheduler triggers a Cloud Function every 15 min for 24 hours, hitting all chosen cameras
- [ ] Log: success rate, error types, frame validity rate, average latency
- [ ] Acceptance: ≥ 95% success rate per camera over 24 hr; remaining failures should be transient (camera offline, retry next cycle)

### Step 6 — Terms of Service & Legal review
- [ ] Read NYC DOT camera viewer ToS (https://webcams.nyctmc.org/)
- [ ] Confirm allowed uses include public consumption of still images for derivative analytics
- [ ] Document our use case: aggregate fashion trend extraction, no individual identification, no rebroadcast of frames
- [ ] If ToS is unclear, send a usage-disclosure email to NYC DOT (`[email protected]` or via 311) and document the response (or non-response after 30 days)

### Step 7 — Backup data sources (in case verification fails)
If NYC DOT access proves unreliable, fall back to:
- **511NY API** — covers some NYC cameras; requires free API key
- **MTA Bus Time / Subway camera feeds** — different domain coverage
- **Webcam aggregators** (e.g., EarthCam) — commercial, ToS varies
- **Synthetic fallback:** disable street feed entirely; agent skips `street_scout` subagent and falls back to weather + inventory only (system degrades gracefully by design)

## Verification Owner & Timing

- **Owner:** Single project owner (per Resolved decisions)
- **When:** Run Steps 1–4 in Week 1 alongside Phase 0 (no GCP infra needed beyond a Cloud Run scratch service)
- **Stability test (Step 5):** Run during Week 5 while Phase 1 soak test is running; results inform Phase 2.2 go/no-go

## Exit Criteria for This Open Item

- [ ] At least 2 cameras per zone confirmed reachable from GCP egress with ≥ 95% 24-hr success rate
- [ ] Rate-limit threshold documented and our planned rate confirmed safe
- [ ] ToS reviewed; usage deemed compliant or formally disclosed
- [ ] Fallback plan documented in case of future NYC DOT access changes
