# Phase 1 — Agent MVP Runbook

> Prerequisite: Phase 0 complete (`PHASE-0-RUNBOOK.md`). All commands run in
> Cloud Shell. Active project must be `inference-expt`.

This runbook is split by sub-phase. Each section is independently re-runnable
and idempotent. Tick the boxes as you go.

| Sub-phase | Status | Section |
|-----------|--------|---------|
| 1.1 Data Layer | ⬜ | [§1.1 below](#11-data-layer-week-2) |
| 1.2 GKE Inference Cluster | ⬜ | [§1.2 below](#12-gke-inference-cluster-week-3) |
| 1.3 Backend Services | ⬜ | [§1.3 below](#13-backend-services-week-3) |
| 1.4 Frontend | ⬜ | _(next chunk)_ |
| 1.5 Auth | ⬜ | _(next chunk)_ |
| 1.6 E2E Flow Test | ⬜ | _(next chunk)_ |
| 1.7 Promote to Staging & Prod | ⬜ | _(next chunk)_ |

---

## 1.1 Data Layer (Week 2)

> **Pause & resume:** to drop the bill to ~$0.10/day between sessions, run
> `/teardown-dev` (or follow the [Pause & Resume appendix](#appendix--pausing-dev-between-implementation-phases)).
> Coming back, run **R0** in the appendix — you're back to the state at the
> end of this section.

**Why this matters for the recommender**

The NYC weather-based clothing recommender is only as good as the wardrobe
it can reason about. This sub-phase stands up the *system of record* for
every user's closet (`clothing_items` in Cloud SQL) and the supporting
stores the agent will lean on:

- **Cloud SQL** — the source of truth for users + items. The agent's
  `search_wardrobe` tool reads from here; if it isn't online, the agent
  hallucinates clothes the user doesn't own.
- **Firestore** — multi-turn agent session state (“what did we tell this
  user yesterday about their black blazer?”). Used later by the deep-agent
  loop in §1.3 / §1.5.
- **GCS buckets** — `clothing-photos` holds the user's uploaded item images
  (Phase 2 turns these into FashionCLIP embeddings); `agent-sessions`
  durably persists the agent's filesystem so a long planning trace doesn't
  vanish on a Cloud Run cold start.
- **BigQuery** — `recommendations` table receives every “what should I
  wear?” response so we can later score outfit quality, train re-rankers,
  and answer “which rationale styles produce the highest 👍 rate?”

Without §1.1, the agent has nothing real to recommend, no memory between
turns, no place to put photos, and no analytics loop to improve over time.

**What this sub-phase delivers**

- Private Services Access (VPC peering) so Cloud SQL / Memorystore can use private IPs
- A Serverless VPC Access connector so Cloud Run reaches private IPs
- Cloud SQL (Postgres 15) — one instance per env, IAM auth enabled
- Firestore — one named database per env (`stylist-dev`, `stylist-staging`, `stylist-prod`)
- Memorystore Redis — private, AUTH enabled
- BigQuery datasets — `stylist_<env>_analytics`, `stylist_<env>_training_data`
- New GCS buckets — `stylist-<env>-model-weights`, `stylist-<env>-street-feed-frames`
- A `stylist-<env>-db-migrate` Cloud Run Job that applies `db/migrations/*.sql` idempotently
- Resource-conditioned IAM so `agent-orch-<env>-sa` can only see its own env's data

**Pre-flight**

```bash
cd ~/Inference-expt
git pull
export PROJECT_ID=inference-expt
export REGION=us-east4
gcloud config set project $PROJECT_ID
```

Enable APIs introduced in this sub-phase:

```bash
gcloud services enable \
  servicenetworking.googleapis.com \
  vpcaccess.googleapis.com \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  firestore.googleapis.com \
  bigquery.googleapis.com \
  --project=$PROJECT_ID
```

### Step 1 — Re-apply the shared stack (PSA + VPC connector)

```bash
cd ~/Inference-expt/infra/envs/shared
terraform init -upgrade
terraform plan -out=plan.out
terraform apply plan.out
```

You should see ~5 new resources:
- `module.network.google_compute_global_address.psa_range`
- `module.network.google_service_networking_connection.psa`
- `module.network.google_compute_firewall.allow_internal_to_psa`
- `module.network.google_vpc_access_connector.serverless`
- `module.iam_shared.google_project_iam_member.cloudbuild_roles["roles/cloudsql.client"]`
- `module.iam_shared.google_project_iam_member.cloudbuild_roles["roles/cloudsql.instanceUser"]`

Verify:

```bash
gcloud compute networks peerings list --network=stylist-vpc \
  --project=$PROJECT_ID --format='table(name,peerNetwork,state)'
# Expect: servicenetworking-googleapis-com  ...  ACTIVE

gcloud compute networks vpc-access connectors list --region=$REGION --project=$PROJECT_ID
# Expect: stylist-vpc-conn  READY
```

### Step 2 — Apply the dev env stack (data layer)

```bash
cd ~/Inference-expt/infra/envs/dev
terraform init -upgrade
terraform plan -out=plan.out
terraform apply plan.out
```

This adds (~30 resources):

- `module.cloud_sql.*` — Cloud SQL instance, db, root user, root password secret
- `module.firestore.*` — `stylist-dev` Firestore database + 2 composite indexes
- `module.memorystore.*` — Redis instance + AUTH-string secret
- `module.bigquery.*` — analytics + training_data datasets
- New buckets: `model_weights`, `street_feed_frames` (+ IAM bindings)
- Resource-conditioned IAM bindings for `agent-orch-dev-sa`
- `db-migrate-dev-sa` SA + Cloud Run Job `stylist-dev-db-migrate` (placeholder image)

> **Cloud SQL takes 8–15 min to come up.** Don't worry if `terraform apply` sits at the Cloud SQL resource for a while; that's normal first-create latency.

Inspect outputs:

```bash
terraform output -json cloud_sql        | jq
terraform output -json redis            | jq
terraform output -raw firestore_database
terraform output -json bigquery_datasets
```

### Step 3 — Build & run the migration job (dev)

```bash
cd ~/Inference-expt
SHA=$(git rev-parse --short HEAD)
gcloud builds submit --config=ci/cloudbuild-migrate.yaml \
  --substitutions=_ENV=dev,_SHA=$SHA .
```

This pipeline:

1. Builds `services/db-migrate/Dockerfile` (psql + Cloud SQL Auth Proxy + migrations)
2. Pushes to Artifact Registry
3. Updates the `stylist-dev-db-migrate` Cloud Run Job to the new image
4. Executes the job once and waits for completion

Watch live: <https://console.cloud.google.com/cloud-build/builds?project=inference-expt>

### Step 4 — Verify the schema

The Cloud SQL instance is **private-IP only** (no public IP), so `cloud-sql-proxy`
from Cloud Shell cannot reach it directly — Cloud Shell isn't on the VPC. Use
one of the methods below.

#### 4a (recommended) — Read the migration job logs

The job already prints the table list and `schema_migrations` contents on every
run, so the Cloud Run Job execution logs are an authoritative record:

```bash
PROJECT=inference-expt
REGION=us-east4

EXEC=$(gcloud run jobs executions list \
  --job=stylist-dev-db-migrate --region=$REGION --project=$PROJECT \
  --limit=1 --format='value(name)')

gcloud logging read \
  "resource.type=cloud_run_job
   AND resource.labels.job_name=stylist-dev-db-migrate
   AND labels.\"run.googleapis.com/execution_name\"=$EXEC" \
  --project=$PROJECT --limit=300 --order=asc \
  --format='value(textPayload)'
```

Look for the `===== Final state of schema_migrations =====` block. Expected:

```
===== Connecting as stylist-root to stylist =====
(schema_migrations not yet created — first migration will create it)
===== Applying migrations in lexical order =====
----- /app/migrations/0001_init.sql -----
CREATE TABLE
…
===== Final state of schema_migrations =====
 0001_init | 2026-…
```

If you see that block with no errors above it, the schema is in place. Move on
to Step 5.

#### 4b (optional, dev only) — Interactive psql

The instance is private-IP only, so neither `cloud-sql-proxy` nor
`gcloud sql connect` can route to it from Cloud Shell out of the box. To open
an ad-hoc psql session you must briefly attach a public IP **and** allow-list
your egress IP:

```bash
PROJECT=inference-expt
MY_IP=$(curl -s ifconfig.me)

# 1. Attach a public IP + allow-list only your Cloud Shell egress.
gcloud sql instances patch stylist-dev-pg \
  --assign-ip \
  --authorized-networks=$MY_IP/32 \
  --project=$PROJECT

# 2. Show the bootstrap password (paste when prompted).
gcloud secrets versions access latest \
  --secret=stylist-dev-pg-root-password --project=$PROJECT

# 3. Connect.
gcloud sql connect stylist-dev-pg \
  --user=stylist-root --database=stylist --project=$PROJECT
```

At the prompt:

```sql
\dt
SELECT version, applied_at FROM schema_migrations ORDER BY version;
\q
```

**Always run the cleanup** the moment you exit psql:

```bash
gcloud sql instances patch stylist-dev-pg \
  --no-assign-ip \
  --clear-authorized-networks \
  --project=$PROJECT

# Verify only PRIVATE remains:
gcloud sql instances describe stylist-dev-pg --project=$PROJECT \
  --format='value(ipAddresses[].type)'
```

> **Never use 4b in staging or prod.** Even briefly attaching a public IP to a
> production database is a security finding. From those environments, rely on
> 4a or run psql from a workload inside the VPC (a debug pod on the GKE cluster
> or a one-shot Cloud Run Job that uses `cloud-sql-proxy --private-ip`).

### Step 5 — Switch the migration job to IAM auth (optional, recommended)

After the first migration, the `db-migrate-dev-sa` IAM user exists in Postgres
and can be granted the schema. Open a psql session via Step 4b (`gcloud sql
connect`) and run:

```sql
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "db-migrate-dev-sa@inference-expt.iam";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "db-migrate-dev-sa@inference-expt.iam";
GRANT USAGE ON SCHEMA public TO "db-migrate-dev-sa@inference-expt.iam";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "db-migrate-dev-sa@inference-expt.iam";
\q
```

Then remove the temporary public IP again:

```bash
gcloud sql instances patch stylist-dev-pg --no-assign-ip --project=inference-expt
```

Then flip the job env var:

```bash
gcloud run jobs update stylist-dev-db-migrate \
  --region=$REGION --project=$PROJECT \
  --update-env-vars=USE_IAM_AUTH=true
```

Subsequent migrations no longer need the Secret Manager password — the job
authenticates with its own service-account identity.

### Step 6 — Quick data-layer health check

Don't try to hand-roll a redis-cli round-trip from Cloud Shell — Memorystore is
private-only and the agent and weather services in §1.3 will exercise it for
real. For §1.1 it's enough to confirm every resource is in a healthy state:

```bash
PROJECT=inference-expt
REGION=us-east4
ENV=dev

gcloud sql instances describe stylist-$ENV-pg --project=$PROJECT \
  --format='value(state)'                                  # → RUNNABLE
gcloud firestore databases describe \
  --database=stylist-$ENV --project=$PROJECT \
  --format='value(type,locationId)'                        # → FIRESTORE_NATIVE, nam5 (or your region)
gcloud redis instances describe stylist-$ENV-redis \
  --region=$REGION --project=$PROJECT \
  --format='value(state)'                                  # → READY
```

If all three print the values shown, the data plane is healthy. Real
connectivity is proven later when the agent/inventory/weather services come
up in §1.3 — there's no value in writing throwaway proxy/redis-cli scripts
here.

### Step 7 — Repeat for staging and prod

> **Recommended: defer this until §1.7.** Standing up `stylist-staging-pg` +
> `stylist-prod-pg` (HA), Firestore, and HA Memorystore burns ~$300+/mo each
> while you iterate on §1.2–1.6 against dev. Schema, IAM, and service shapes
> *will* change between now and §1.7, so applying staging+prod now means you
> reapply them later anyway. Skip ahead to §1.2 and do all three envs as one
> batch when you reach the promotion-gating phase.
>
> If you have a business reason to bring all three envs up immediately
> (compliance review, parallel team work, etc.), proceed with the loop below.

Same flow, environment by environment:

```bash
for E in staging prod; do
  cd ~/Inference-expt/infra/envs/$E
  terraform init -upgrade
  terraform apply

  cd ~/Inference-expt
  SHA=$(git rev-parse --short HEAD)
  gcloud builds submit --config=ci/cloudbuild-migrate.yaml \
    --substitutions=_ENV=$E,_SHA=$SHA .
done
```

Then re-run **Step 6** with `ENV=staging` and `ENV=prod`. That's the entire
validation surface for §1.1.

> **Prod is sized larger** (HA Postgres `db-custom-2-7680` + 4GB Redis HA +
> multi-region Firestore). Plan ~20 min for the first apply.

### Step 8 — Exit checklist for §1.1

- [ ] Step 6 health check passes for **dev** (re-run for staging/prod when you bring those up in §1.7)
- [ ] Migration job logs (Step 4a) show `0001_init` applied in dev
- [ ] `bq ls --project_id=$PROJECT_ID` shows `stylist_dev_analytics` + `stylist_dev_training_data`

> Cross-project IAM scoping was already validated in Phase 0 §10. No need
> to re-run those checks unless you've added new bindings here.

---

## 1.3 Backend Services (Week 3)

> **Pause & resume:** `/teardown-dev` between sessions. To resume here, run
> **R0**, then re-deploy weather, inventory, agent via
> `cloudbuild-service.yaml` (Step 3) and re-apply the §1.3 Step 4 GRANTs.

**Why this matters for the recommender**

This is the sub-phase where the recommender stops being a plan and starts
answering “what should I wear?”. Three services come online:

- **Inventory** — the agent's `search_wardrobe(category, attributes)` tool.
  This is what lets the recommendation be grounded in *the actual clothes*
  the user owns rather than generic advice.
- **Weather** — the agent's `get_weather(zone, time)` tool. NYC microclimate
  matters: a 70°F evening in Midtown is a different outfit from 70°F on the
  Brooklyn waterfront with 15 mph wind. The zone-aware API surfaces that.
- **Agent orchestrator** — the planner that turns a free-text query (“rooftop
  dinner, 8pm, Williamsburg”) into a tool plan, calls those tools, and
  produces a reasoned outfit + rationale streamed via SSE.

Starting in `LLM_MODE=stub` lets us prove the *plumbing* works (chat → tools
→ DB → streaming UI) before §1.2 plugs in a real reasoning model. Every
later enhancement — personalization, photo embeddings, street-feed signal —
is just another tool dropped into this orchestrator.

> **Order note:** We do §1.3 before §1.2 so we have working endpoints to test
> end-to-end. The agent starts in `LLM_MODE=stub` (deterministic, no LLM). Once
> §1.2 brings vLLM online we flip a single env var and the same agent becomes
> LLM-driven.

**What this sub-phase delivers**

- 3 Cloud Run services per env:
  - `stylist-<env>-weather` — NYC microclimate-aware weather tool (internal only)
  - `stylist-<env>-inventory` — CRUD on users + clothing items, signed-URL minting (internal only)
  - `stylist-<env>-agent` — public SSE chat endpoint at `api-<env>.quantum-23.com` (prod: `api.quantum-23.com`)
- Dedicated runtime SAs per service (`weather-<env>-sa`, `inventory-<env>-sa`); least privilege
- Agent SA can invoke the two private services via `roles/run.invoker` (per-resource binding)
- Inventory talks to Cloud SQL via the unix-socket integration (no proxy), authenticating with IAM
- Weather caches in Memorystore via the VPC connector
- Generic `ci/cloudbuild-service.yaml` builds and deploys any service

### Step 1 — Prerequisites

1. Confirm §1.1 exit checklist is green for the env you're about to deploy.
2. Get an OpenWeatherMap API key from <https://openweathermap.org/api> (free tier is fine for dev).
3. Store it in Secret Manager (one secret shared across envs; access is granted per-env to each weather SA):

   ```bash
   echo -n "<your-owm-key>" | gcloud secrets create openweathermap-api-key \
     --data-file=- --project=$PROJECT_ID
   # If already exists:
   echo -n "<your-owm-key>" | gcloud secrets versions add openweathermap-api-key \
     --data-file=- --project=$PROJECT_ID
   ```

   The Terraform stacks reference `secret_id = "openweathermap-api-key"` directly — do not change the name.

### Step 2 — Terraform apply (dev)

```bash
cd ~/Inference-expt/infra/envs/dev
terraform plan -out=plan.out
terraform apply plan.out
```

You should see ~25 new resources, the most important being:

- `google_service_account.weather`, `google_service_account.inventory`
- `module.weather.google_cloud_run_v2_service.service`
- `module.inventory.google_cloud_run_v2_service.service`
- `module.agent.google_cloud_run_v2_service.service`
- `google_cloud_run_v2_service_iam_member.agent_invokes_{weather,inventory}`
- `google_sql_user.inventory_iam` (creates `inventory-dev-sa@...iam` as a Postgres user)

Inspect outputs:

```bash
terraform output -raw agent_service_uri
terraform output -raw weather_service_uri
terraform output -raw inventory_service_uri
terraform output -json service_accounts | jq
```

> The three Cloud Run services boot with the placeholder `hello` image at this
> point. `/healthz` returns 404 until Step 3 deploys the real images.

### Step 3 — Build & deploy each service

Three runs of the same parameterized pipeline:

```bash
cd ~/Inference-expt
SHA=$(git rev-parse --short HEAD)

for pair in "weather-api weather" "inventory-api inventory" "agent-orchestrator agent"; do
  set -- $pair
  gcloud builds submit --config=ci/cloudbuild-service.yaml \
    --substitutions=_SERVICE=$1,_SHORT_NAME=$2,_ENV=dev,_SHA=$SHA . || break
done
```

Each build:
1. Builds `services/<_SERVICE>/Dockerfile`
2. Pushes two tags (`dev-$SHA`, `dev-latest`) to Artifact Registry
3. `gcloud run services update` swaps the image
4. Probes `/healthz` with an OIDC token minted for the Cloud Build SA

Watch live: <https://console.cloud.google.com/cloud-build/builds?project=inference-expt>

### Step 4 — Bootstrap the inventory Postgres role

The migration job already created the `stylist` schema as `stylist-root`.
`inventory-dev-sa` exists as a Postgres IAM user but has no privileges yet.
Grant them once (Cloud Shell, via Cloud SQL Auth Proxy):

```bash
PROJECT=inference-expt
ENV=dev
INSTANCE="$PROJECT:us-east4:stylist-$ENV-pg"

PGPASSWORD=$(gcloud secrets versions access latest \
  --secret="stylist-$ENV-pg-root-password" --project=$PROJECT)

cloud-sql-proxy --port=15432 "$INSTANCE" &
PROXY_PID=$!
sleep 3

PGPASSWORD=$PGPASSWORD psql -h 127.0.0.1 -p 15432 -U stylist-root -d stylist <<SQL
GRANT USAGE ON SCHEMA public TO "inventory-$ENV-sa@$PROJECT.iam";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "inventory-$ENV-sa@$PROJECT.iam";
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO "inventory-$ENV-sa@$PROJECT.iam";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "inventory-$ENV-sa@$PROJECT.iam";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO "inventory-$ENV-sa@$PROJECT.iam";
SQL

kill $PROXY_PID
```

> One-time per env. Run again only if you add new tables in a future migration
> and want the IAM user to access them automatically (the `ALTER DEFAULT
> PRIVILEGES` clause handles future tables).

### Step 5 — Smoke test the agent end-to-end

The agent is public; weather + inventory are private. The agent's runtime SA
mints OIDC tokens to call them internally. To seed test data we use a
developer ID token (the human running this runbook needs `roles/run.invoker`
on the inventory service, which they get via `roles/run.admin` on the project).

```bash
ENV=dev
INVENTORY_URL=$(gcloud run services describe stylist-$ENV-inventory \
  --project=inference-expt --region=us-east4 --format='value(status.url)')
AGENT_URL=$(gcloud run services describe stylist-$ENV-agent \
  --project=inference-expt --region=us-east4 --format='value(status.url)')

# Inventory is private. Use Cloud Build / human-developer ID token to seed
# data; in normal operation only the agent SA can reach it.
TOKEN=$(gcloud auth print-identity-token --audiences=$INVENTORY_URL)

# 1) Get-or-create user
USER_JSON=$(curl -sS -X POST $INVENTORY_URL/users \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"email":"dev@quantum-23.com","preferences":{"style":"smart-casual"}}')
USER_ID=$(echo $USER_JSON | jq -r .id)
echo "user_id=$USER_ID"

# 2) Add three sample items
for body in \
  '{"name":"Navy crewneck","category":"top","attributes":{"warmth":4,"color":"navy"}}' \
  '{"name":"Black chinos","category":"bottom","attributes":{"warmth":4,"color":"black"}}' \
  '{"name":"White sneakers","category":"footwear","attributes":{"warmth":2,"color":"white"}}'
do
  curl -sS -X POST "$INVENTORY_URL/items?user_id=$USER_ID" \
    -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
    -d "$body" | jq -c '{id,name,category}'
done

# 3) Ask the agent (public; SSE)
curl -N -sS -X POST $AGENT_URL/chat \
  -H 'content-type: application/json' \
  -d "{\"user_id\":\"$USER_ID\",\"query\":\"what should I wear for a walk?\",\"zone\":\"midtown\"}"
```

You should see SSE events:

```
event: thought
data: {"event":"thought","text":"Stub agent: planning ..."}

event: tool_result
data: {"event":"tool_result","name":"get_weather","result":{...}}

event: tool_result
data: {"event":"tool_result","name":"search_inventory","result":{"items":[...]}}

event: final
data: {"event":"final","recommendation":{"items":[...],"rationale":"...","weather":{...}}}

event: saved
data: {"recommendation_id":"<firestore-doc-id>"}
```

### Step 6 — Promote to staging and prod

> **Defer until §1.7** unless you have a specific reason to run all envs in
> parallel — see the callout in §1.1 Step 7.

```bash
cd ~/Inference-expt
SHA=$(git rev-parse --short HEAD)

# Terraform first (each env is independent state)
for E in staging prod; do
  cd ~/Inference-expt/infra/envs/$E && terraform apply
done

# Then re-run the build pipeline pointed at each env
for E in staging prod; do
  for pair in "weather-api weather" "inventory-api inventory" "agent-orchestrator agent"; do
    set -- $pair
    gcloud builds submit --config=ci/cloudbuild-service.yaml \
      --substitutions=_SERVICE=$1,_SHORT_NAME=$2,_ENV=$E,_SHA=$SHA .
  done
  # Re-run Step 4's GRANT block, substituting ENV=$E
done
```

### Step 7 — Exit checklist for §1.3

- [ ] `/healthz` returns 200 for all three dev services (staging/prod deferred to §1.7)
- [ ] `POST /chat` (Step 5) emits a `final` SSE event citing the seeded items
- [ ] Inventory called **without** an ID token returns 403 (one-shot `curl` is enough — proves the service is private)

> Cross-env isolation, CORS hardening, and Firestore `trace_id` capture get
> exercised by the §1.6 e2e suite and Phase 0 security tests; no need to
> hand-verify them here.

---

## 1.2 GKE Inference Cluster (Week 3)

> **Pause & resume:** GKE is the most expensive idle resource (~$2.40/day for
> the regional cluster fee alone). Always `/teardown-dev` between sessions.
> To resume here, run **R0**, then re-run §1.2 Steps 3 → 6 (`get-credentials`,
> secrets, FashionCLIP repo upload, k8s manifests, tfvars round-trip).

**Why this matters for the recommender**

The recommender's whole pitch is “it *reasons* about your outfit like a
stylist.” That reasoning lives in an open-weight LLM (Mistral-7B-Instruct)
behind a vLLM server on a GPU node. This sub-phase brings that brain online
and flips the agent from `LLM_MODE=stub` to `LLM_MODE=openai`-compatible.

Concretely, this is what changes for the user once §1.2 lands:

- The agent can write a real **plan** (“it's 45°F and windy by the water at
  night → I should layer; let me search the user's outerwear”) instead of a
  hard-coded sequence.
- The agent produces a **natural-language rationale** alongside its picks,
  citing weather and the user's specific items.
- The agent can **handle ambiguity** (“going out tonight” → ask clarifier or
  pick safest interpretation) instead of failing.

GKE-Autopilot + a single GPU node is the cheapest way to host this on GCP
while keeping the door open to scale (vLLM is happy on multi-GPU, and
swapping models is a one-line change in the deployment).

> **Order note:** §1.3 deployed the agent in `LLM_MODE=stub` so we already
> have a working end-to-end flow. This section brings up the GPU inference
> stack (vLLM + Triton + Qdrant) and flips the agent to `LLM_MODE=openai`.

**What this sub-phase delivers**

- One regional, private, VPC-native GKE cluster per env: `stylist-<env>-gke`
- Two node pools:
  - `cpu-pool` — `e2-standard-4`, autoscaling 1–3 (dev), runs Qdrant + system pods
  - `gpu-l4-pool` — `g2-standard-8` + 1× NVIDIA L4, autoscaling 0–N (dev: 0–1, staging: 1–2, prod: 2–4). Taint `nvidia.com/gpu=present:NoSchedule`
- Three workloads in the `inference` namespace:
  - `vllm` — Mistral-7B-Instruct-v0.3, OpenAI-compatible, exposed via an ILB
  - `triton` — FashionCLIP (ONNX) loaded from a per-env GCS bucket via the gcsfuse CSI driver
  - `qdrant` — single-replica StatefulSet on a 20Gi PD-balanced volume
- Workload Identity enabled cluster-wide
- Firewall rules so Cloud Run (via the serverless VPC connector) can reach the three ILBs on TCP 6333, 8000, 8001, 8002
- Agent picks up the new `LLM_BASE_URL` Terraform variable and switches from stub to OpenAI/vLLM transparently

### Step 1 — Prereqs

1. §1.1 and §1.3 exit checklists green.
2. Hugging Face account with access to `mistralai/Mistral-7B-Instruct-v0.3` (request access at <https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3> — gated model, instant approval).
3. Quota check (us-east4):

   ```bash
   gcloud compute regions describe us-east4 --project=$PROJECT_ID \
     --format='value(quotas)' | tr ',' '\n' | grep -i gpu
   # need NVIDIA_L4_GPUS >= 4 to cover dev(1)+staging(2)+prod(4); request more if 0
   ```

   If the quota is 0, request an increase at:
   <https://console.cloud.google.com/iam-admin/quotas?project=inference-expt&service=compute.googleapis.com&metric=NVIDIA_L4_GPUS>
   Approval usually takes 1–2 business days.

### Step 2 — Terraform apply (dev)

```bash
cd ~/Inference-expt/infra/envs/dev
terraform plan -out=plan.out
terraform apply plan.out
```

Adds ~12 resources, most importantly:

- `module.gke.google_container_cluster.this` (10–15 min to provision)
- `module.gke.google_container_node_pool.cpu`
- `module.gke.google_container_node_pool.gpu`
- 3 new firewall rules: `stylist-allow-connector-to-gke`, `stylist-allow-gke-health-checks`, `stylist-allow-gke-intra`

Cluster IAM (workload identity pool, node SA) is created in the same apply.

### Step 3 — kubectl auth + secrets

```bash
ENV=dev
PROJECT=inference-expt
REGION=us-east4

gcloud container clusters get-credentials stylist-$ENV-gke \
  --region=$REGION --project=$PROJECT

kubectl get nodes # cpu-pool nodes should be Ready; gpu pool 0 in dev
```

Create the Hugging Face token Secret (vLLM needs it to download Mistral):

```bash
read -s -p "HF token: " HF_TOKEN; echo
kubectl create ns inference --dry-run=client -o yaml | kubectl apply -f -
kubectl -n inference create secret generic huggingface \
  --from-literal=token="$HF_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
```

Optional Qdrant API key (recommended for prod, optional for dev):

```bash
QDRANT_KEY=$(openssl rand -hex 24)
kubectl -n inference create secret generic qdrant-auth \
  --from-literal=api-key="$QDRANT_KEY" --dry-run=client -o yaml | kubectl apply -f -
echo "qdrant-api-key=$QDRANT_KEY" # save it; inventory + agent need it
```

### Step 4 — Prepare the Triton model repo (FashionCLIP)

```bash
cd ~/Inference-expt
./scripts/prepare-fashionclip-repo.sh dev
```

This:
1. Creates `gs://stylist-dev-fashionclip-models` (regional, uniform IAM)
2. Grants `roles/storage.objectViewer` on it to the GKE node SA (`gke-dev-node-sa@…`)
3. Downloads FashionCLIP from Hugging Face, exports vision tower to ONNX
4. Uploads `fashionclip/{config.pbtxt,1/model.onnx}` to the bucket

> ~5 min on a Cloud Shell VM. Re-runnable; second run only re-uploads if files change.

### Step 5 — Apply Kubernetes manifests

```bash
cd ~/Inference-expt/infra/k8s/inference

kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-vllm.yaml
kubectl apply -f 30-qdrant.yaml

# Render Triton with the env-specific bucket name
export MODEL_REPO_BUCKET=stylist-$ENV-fashionclip-models
envsubst < 20-triton.yaml | kubectl apply -f -
```

Watch the GPU node provision + vLLM pod start (model download is the slow part — ~10 min the first time):

```bash
kubectl -n inference get pods -w
kubectl -n inference logs -f deploy/vllm | head -200
```

`vllm` is Ready when `/health` returns 200. ILBs allocate addresses within ~1 min after the pods are Ready.

### Step 6 — Collect ILB IPs and wire them back into Terraform

```bash
VLLM_IP=$(kubectl -n inference get svc vllm -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
TRITON_IP=$(kubectl -n inference get svc triton -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
QDRANT_IP=$(kubectl -n inference get svc qdrant -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "vllm    -> http://$VLLM_IP/v1"
echo "triton  -> http://$TRITON_IP:8002"
echo "qdrant  -> http://$QDRANT_IP:6333"
```

Write them to a per-env tfvars file (this file is gitignored — DO NOT commit ILB IPs):

```bash
cat > ~/Inference-expt/infra/envs/$ENV/inference.auto.tfvars <<EOF
llm_base_url    = "http://$VLLM_IP/v1"
triton_base_url = "http://$TRITON_IP:8002"
qdrant_base_url = "http://$QDRANT_IP:6333"
EOF

cd ~/Inference-expt/infra/envs/$ENV && terraform apply
```

The agent's `LLM_MODE` flips from `stub` to `openai` automatically (`LLM_MODE = var.llm_base_url == "" ? "stub" : "openai"`) and a new Cloud Run revision rolls out with the new env vars.

> **gitignore reminder:** add `infra/envs/*/inference.auto.tfvars` to `.gitignore` if not already present. The IPs are private (RFC 1918) but they're env-specific and should not be in git.

### Step 7 — Smoke test the LLM-driven agent

Re-run the §1.3 chat curl. The single difference that confirms GKE is wired
in: the SSE stream now includes `tool_call` events (stub mode emitted none)
and the `final` text is LLM-generated, not boilerplate.

```bash
ENV=dev
AGENT_URL=$(gcloud run services describe stylist-$ENV-agent \
  --project=inference-expt --region=us-east4 --format='value(status.url)')
USER_ID="<uuid from §1.3 Step 5>"

curl -N -sS -X POST $AGENT_URL/chat -H 'content-type: application/json' \
  -d "{\"user_id\":\"$USER_ID\",\"query\":\"drizzling in midtown — casual brunch outfit?\",\"zone\":\"midtown\"}"
```

### Step 8 — Promote to staging and prod

> **Defer until §1.7** — same reasoning as §1.1 Step 7. GKE GPU pools
> in particular are expensive to keep idle.

```bash
for E in staging prod; do
  cd ~/Inference-expt/infra/envs/$E && terraform apply           # builds the cluster
  gcloud container clusters get-credentials stylist-$E-gke \
    --region=us-east4 --project=inference-expt
  kubectl create ns inference --dry-run=client -o yaml | kubectl apply -f -
  # Same Step 3 secrets, Step 4 model repo prep, Step 5 manifests, Step 6 tfvars round-trip
done
```

Prod-specific:
- `gpu_min_nodes=2` keeps two warm GPU nodes for HA
- Set `replicas: 2` on the vLLM Deployment (one per node)
- Enable a Qdrant API key

### Step 9 — Cost guardrail: scale to zero on dev when idle

```bash
# At end of dev day:
kubectl --context=stylist-dev-gke -n inference scale deploy/vllm --replicas=0
# Node autoscaler drains the GPU node within ~10 min, charges stop.
# Restart next morning:
kubectl --context=stylist-dev-gke -n inference scale deploy/vllm --replicas=1
```

Optional cron via Cloud Scheduler — left for Phase 2.

### Step 10 — Exit checklist for §1.2

- [ ] `kubectl -n inference get pods` — `vllm`, `triton`, `qdrant-0` all Running/Ready
- [ ] `kubectl -n inference get svc` — all three have a LoadBalancer Ingress IP
- [ ] `POST /chat` (Step 7) emits `tool_call` events and a Mistral-generated `final`

---

## 1.4 Frontend (Week 4)

> **Pause & resume:** `/teardown-dev` between sessions. To resume here, run
> **R0**, restore §1.2 and §1.3 (see their callouts), then re-deploy the
> frontend via `cloudbuild-frontend.yaml` (Step 4).

**Why this matters for the recommender**

The recommender becomes a *product* in this sub-phase. Two surfaces ship:

- **Wardrobe** — the user uploads photos and metadata for the clothes they
  actually own. Without this, every recommendation is generic; with it,
  the agent's `search_wardrobe` tool returns real items that get cited in
  the rationale (“wear your navy oxford with the charcoal chinos”).
- **Chat** — the conversational entry point: “going to a Yankees game at
  7pm, what do I wear?”. Streaming SSE rendering exposes the agent's
  *thinking* (plan → weather lookup → wardrobe search → final outfit) so
  the user trusts and can correct the recommendation.

Photo upload via signed URLs is a deliberate design choice: the photo never
touches the inventory pod, which keeps that service stateless, lightweight,
and cheap to scale. The same photos are what the FashionCLIP embedding
pipeline will consume in Phase 2.

**What this sub-phase delivers**

- One public Next.js 14 (App Router) service per env: `stylist-<env>-frontend`
  on Cloud Run, mapped to `app-<env>.quantum-23.com` (prod: `app.quantum-23.com`).
- Three core pages:
  - `/onboarding` — 3-step wizard. Calls `POST /api/users` and stores the
    returned id in `localStorage` (Phase 1.5 swaps this out for Firebase Auth).
  - `/wardrobe` — list + create + delete clothing items, with direct-to-GCS
    photo uploads via signed PUT URLs minted by the BFF.
  - `/chat` — live SSE chat. Renders `thought`, `tool_call`, `tool_result`,
    `final`, `saved`, and `error` events as the agent streams them.
- **BFF proxy** on `stylist-<env>-agent` exposing `/api/users`,
  `/api/items*`, `/api/items/upload-url`. The frontend never talks to
  inventory or weather directly.
- CORS locked down to the env's frontend origin only.

> **Design note:** the public attack surface stays at *one* service
> (`stylist-<env>-agent`). The frontend itself only serves static assets +
> SSR shell and never holds secrets.

### Step 1 — Prereqs

- §1.3 exit checklist green (agent at `api-<env>.quantum-23.com` answers
  `POST /chat` in stub mode).
- Local Node.js 20 toolchain if you want to dev against the deployed agent
  before pushing.

### Step 2 — Terraform apply

```bash
cd ~/Inference-expt/infra/envs/dev && terraform apply
```

Creates:
- `google_service_account.frontend`
- `module.frontend` (Cloud Run + DNS A/AAAA + ssl cert)
- Adds `CORS_ALLOW_ORIGINS=https://app-dev.quantum-23.com` to the agent (rolls
  a new revision automatically)

Verify outputs:

```bash
terraform output frontend_service_uri
# https://stylist-dev-frontend-XXXX-uk.a.run.app  (still serving hello-world)
```

### Step 3 — Local dev (optional)

```bash
cd ~/Inference-expt/services/frontend
npm install
NEXT_PUBLIC_AGENT_URL=https://api-dev.quantum-23.com npm run dev
# open http://localhost:3000
```

The agent's CORS config already allows `https://app-dev.quantum-23.com`. For
local dev, temporarily widen it:

```bash
gcloud run services update stylist-dev-agent --region=us-east4 \
  --update-env-vars=CORS_ALLOW_ORIGINS="https://app-dev.quantum-23.com,http://localhost:3000"
# Revert after dev session, or just re-run terraform apply.
```

### Step 4 — Deploy via Cloud Build

```bash
ENV=dev
SHA=$(git rev-parse --short HEAD)
gcloud builds submit \
  --config=ci/cloudbuild-frontend.yaml \
  --substitutions=_ENV=$ENV,_SHA=$SHA .
```

This:
1. Computes `NEXT_PUBLIC_AGENT_URL` per env (`api-<env>.quantum-23.com` for
   dev/staging, `api.quantum-23.com` for prod).
2. Builds the Next.js image with that value baked in.
3. Pushes to `us-east4-docker.pkg.dev/$PROJECT/stylist-<env>/frontend:<sha>`.
4. Updates the Cloud Run service.
5. Probes `/` for HTTP 200.

> The `NEXT_PUBLIC_*` baking is intentional. If you `gcloud run services update`
> with a new image built for *dev* against a *staging* Cloud Run service, the
> browser JS will still call the dev agent. Always re-run the pipeline per env.

### Step 5 — Smoke test the end-to-end flow

```bash
# 1. Browser to https://app-dev.quantum-23.com
#    (or curl the Cloud Run URL directly if DNS hasn't propagated)
open https://app-dev.quantum-23.com

# 2. Click "Start" -> enter test email -> pick style -> pick zone -> Finish.
#    Network tab should show: POST https://api-dev.quantum-23.com/api/users -> 200
#    localStorage has stylist.user.v1.

# 3. /wardrobe -> "Add item" -> upload a JPEG. You should see:
#    POST /api/items/upload-url       -> 200 {upload_url, object_uri}
#    PUT  https://storage.googleapis.com/... (CORS preflight OK)
#    POST /api/items?user_id=...      -> 201

# 4. /chat -> type "What should I wear to a 7pm rooftop dinner downtown?"
#    EventStream tab shows the SSE frames live; final event renders an
#    outfit grid with the items you uploaded.
```

### Step 6 — Promote to staging and prod

> **Defer until §1.7** unless staging/prod are already up — see §1.1 Step 7.

```bash
for E in staging prod; do
  (cd ~/Inference-expt/infra/envs/$E && terraform apply)
  gcloud builds submit \
    --config=ci/cloudbuild-frontend.yaml \
    --substitutions=_ENV=$E,_SHA=$(git rev-parse --short HEAD) .
done
```

Prod-specific:
- `min_instances=1` (no cold starts on first paint).
- DNS subdomain is bare `app.quantum-23.com`.

### Step 7 — Exit checklist for §1.4

- [ ] `https://app-<env>.quantum-23.com/` returns the landing page
- [ ] Onboarding → wardrobe photo upload → `/chat` end-to-end works in a real browser (Step 5)
- [ ] `/chat` SSE renders a `final` outfit citing items from the wardrobe

> CORS edge cases and cross-origin rejection are covered by the §1.6 e2e
> suite (`auth.spec.ts`); skip the manual preflight curls here.

---

## 1.5 Auth (Week 5)

> **Pause & resume:** `/teardown-dev` between sessions. Firebase project +
> web app config persist across destroys (they live in the Firebase console,
> not Terraform), so resume = **R0** + §1.2 / §1.3 / §1.4 redeploys + the §1.5
> Step 4 builds with `_FB_*` substitutions.

**Why this matters for the recommender**

A wardrobe is intensely personal — the recommender is multi-tenant from day
one, and §1.5 is what makes that real. Without this sub-phase any visitor
could read or modify any other visitor's closet.

What real-user behaviour this unlocks:

- **Per-user closets.** “What should I wear to brunch?” resolves against
  *your* clothes, not a global pool.
- **Persistent preferences.** Style (`smart-casual`) and default zone
  (`waterfront`) ride along with the bearer token, so the agent personalises
  every recommendation without asking again.
- **Trustworthy analytics.** `recommendations` rows in BigQuery are now
  attributable to a stable user id, which is what makes “thumbs-up rate by
  style preset” a meaningful metric instead of noise.
- **A clean contract for future providers.** Email-as-stable-key + a
  `firebase_uid → inventory_user_id` adapter means we can swap in
  Apple/Google/SAML later without touching agent code.

**What this sub-phase delivers**

- **Firebase Auth** wired into the frontend: email magic link + Google sign-in.
- Server-side **Firebase ID-token verification** on the agent for `/api/*` and
  `/chat`. The token's `email` is mapped to (or lazily creates) an inventory
  user row, and the resolved `inventory_user_id` is what tools see — meaning
  if we ever swap auth providers, only the email→uuid mapping moves.
- All client `user_id` parameters disappear. Wardrobe/chat use the bearer token
  alone.
- A new `/login` page; protected routes redirect to `/login?next=<path>`.
- Onboarding becomes "set preferences" (style + zone) rather than a sign-up.

> **Design note:** we kept Firebase UID separate from the inventory primary key
> on purpose. Inventory rows are joined to `users.email`; the
> `firebase_uid -> inventory_user_id` map lives in agent memory only (and can
> be reconstructed from email at any time).

### Step 1 — Enable Firebase Auth on each GCP project

For each `dev`, `staging`, `prod` project:

```bash
PROJECT=stylist-dev   # repeat for staging, prod

# 1. Enable Identity Toolkit (the API behind Firebase Auth)
gcloud services enable identitytoolkit.googleapis.com --project=$PROJECT

# 2. Add the GCP project to Firebase (one-time per project)
firebase projects:addfirebase $PROJECT
```

Then in the **Firebase console** ([console.firebase.google.com](https://console.firebase.google.com)):
- Select the project.
- **Build → Authentication → Get started**.
- Enable **Email/Password** (toggle on **Email link (passwordless)**).
- Enable **Google** (auto-creates an OAuth client).
- **Settings → Authorized domains**: add
  - `app-dev.quantum-23.com` (and `app-staging.`, `app.`)
  - `localhost` (for local dev)

### Step 2 — Get the Firebase web config

Firebase console → ⚙️ **Project settings** → **Your apps** → **Add web app**
(call it `stylist-web`). Copy the four public values:

```js
apiKey:        "AIza..."
authDomain:    "stylist-dev.firebaseapp.com"
projectId:     "stylist-dev"
appId:         "1:123:web:abc"
```

These are **public** (they ship in the browser bundle) but they ARE per-env.
Store them as Cloud Build trigger substitutions, NOT as secrets:

```bash
gcloud builds triggers create-from-template ...   # or edit existing trigger
# Add substitutions:
#   _FB_API_KEY      = AIza...
#   _FB_AUTH_DOMAIN  = stylist-dev.firebaseapp.com
#   _FB_PROJECT_ID   = stylist-dev
#   _FB_APP_ID       = 1:123:web:abc
```

For one-off CLI builds:

```bash
gcloud builds submit \
  --config=ci/cloudbuild-frontend.yaml \
  --substitutions=_ENV=dev,_SHA=$(git rev-parse --short HEAD),\
_FB_API_KEY=AIza...,_FB_AUTH_DOMAIN=stylist-dev.firebaseapp.com,\
_FB_PROJECT_ID=stylist-dev,_FB_APP_ID=1:123:web:abc .
```

### Step 3 — Terraform apply

```bash
cd ~/Inference-expt/infra/envs/dev && terraform apply
```

What this does:
- Adds `FIREBASE_PROJECT_ID=stylist-dev` to the agent's env. The agent uses
  this as the audience when verifying ID tokens.
- Rolls a new agent revision automatically.

No additional IAM is needed — `firebase-admin` verifies tokens against
Google's public JWKs (no Firebase Admin SDK calls that require GCP perms).

### Step 4 — Deploy the new agent + frontend

```bash
ENV=dev
SHA=$(git rev-parse --short HEAD)

# Agent (new firebase-admin dep + verify dependency on /api + /chat)
gcloud builds submit --config=ci/cloudbuild.yaml \
  --substitutions=_ENV=$ENV,_SHA=$SHA \
  services/agent-orchestrator

# Frontend (new login page + Firebase init)
gcloud builds submit --config=ci/cloudbuild-frontend.yaml \
  --substitutions=_ENV=$ENV,_SHA=$SHA,\
_FB_API_KEY=...,_FB_AUTH_DOMAIN=...,_FB_PROJECT_ID=...,_FB_APP_ID=... .
```

### Step 5 — Smoke test

```bash
open https://app-dev.quantum-23.com
# 1. Click "Sign in" -> email me a magic link or use Google.
# 2. After redirect, you should land on /wardrobe.
#    Check Network: GET /api/users/me 200, GET /api/items 200.
# 3. /chat works without any user_id in the request body.

# 4. Token check: hit a protected endpoint without a Bearer token:
curl -sS -i https://api-dev.quantum-23.com/api/users/me
# -> HTTP/1.1 401 Unauthorized, body: {"detail":"missing bearer token"}

# 5. Verify the agent rejects forged tokens:
curl -sS -i https://api-dev.quantum-23.com/api/users/me \
  -H "Authorization: Bearer not-a-jwt"
# -> 401 invalid token: ...
```

### Step 6 — Promote

> **Defer until §1.7** unless staging/prod are already up — see §1.1 Step 7.
> Each env has its own Firebase project and its own `_FB_*` substitutions,
> so this step won't be a no-op when you do come back to it.

Same gcloud invocations against `_ENV=staging` and `_ENV=prod`.

### Step 7 — Exit checklist for §1.5

- [ ] Magic-link **or** Google sign-in works on `app-<env>.quantum-23.com`
- [ ] `GET /api/users/me` returns 401 without a token and 200 with a valid one (Step 5)
- [ ] After sign-in, wardrobe + chat work without any `user_id` in client requests

> First-login user-row creation, sign-out redirect, and token auto-refresh
> are all asserted by the §1.6 e2e suite — don't re-test by hand.

---

## 1.6 E2E tests (Week 6)

> **Pause & resume:** `/teardown-dev` between sessions. The e2e test user in
> Firebase Auth and the `e2e-test-*` secrets all persist. Resume = the chain
> through §1.5, then `gcloud builds submit --config=ci/cloudbuild-e2e.yaml ...`
> to re-validate.

**Why this matters for the recommender**

The recommender's value is the *full* chain working: weather → wardrobe →
LLM plan → streamed outfit with rationale, behind a per-user auth wall.
Unit tests can't catch a broken signed-URL header, a Firebase audience
mismatch, or a CORS preflight regression — but a real browser hitting a
real deployment will. This sub-phase locks that contract in:

- Every deploy proves a NYC user can sign in, register a clothing item,
  ask the agent for an outfit, and see the streamed final card.
- Promotion to staging/prod is gated on the same suite — so we never ship
  a regression that silently breaks the recommender's core flow.
- The HTML report archived in GCS becomes the post-mortem artifact when
  something does break: it includes screenshots, network logs, and the
  exact SSE frames the agent emitted.

Think of §1.6 as the safety harness for everything Phase 2 will add
(personalisation, FashionCLIP retrieval, street-feed signal): each new tool
we drop into the agent must keep this suite green.

**What this sub-phase delivers**

- A Playwright suite (`tests/e2e/`) that drives a real deployed environment
  through sign-in, wardrobe CRUD, and chat — using the same bearer-token flow
  a real browser produces.
- A reusable Cloud Build pipeline (`ci/cloudbuild-e2e.yaml`) that runs the
  suite on every deploy and uploads the HTML report to GCS.
- A one-time helper (`scripts/provision-e2e-user.py`) that creates per-env
  test users in Firebase Auth.
- Wiring so the promotion pipeline blocks on a green e2e run (1.7 takes this
  further with manual approvals).

> **Why we don't drive Google popups.** A Google sign-in popup needs a real
> user gesture inside an OAuth domain we don't control. Magic-link emails
> need an inbox we'd have to poll. Both add flakiness without testing
> behaviour we own. The suite signs in via the Firebase REST API
> (`accounts:signInWithPassword`) and seeds the SDK's localStorage record,
> producing a session that's indistinguishable to the agent from a
> real-browser session — and that's where coverage matters.

### Step 1 — Enable Email/Password sign-in (one-time per env)

If you haven't already during §1.5 setup:
- Firebase console → Authentication → Sign-in method → **Email/Password** =
  enabled. Email-link is fine to leave on too.

### Step 2 — Provision the test user (one-time per env)

```bash
PROJECT=stylist-dev
TEST_EMAIL=e2e@stylist-dev.com
TEST_PASSWORD=$(openssl rand -base64 24)

# Stash the creds in Secret Manager so Cloud Build can read them.
gcloud secrets create e2e-test-email \
  --project=$PROJECT --data-file=- <<<"$TEST_EMAIL"
gcloud secrets create e2e-test-password \
  --project=$PROJECT --data-file=- <<<"$TEST_PASSWORD"

# Mint the user.
PROJECT_ID=$PROJECT TEST_EMAIL=$TEST_EMAIL TEST_PASSWORD=$TEST_PASSWORD \
  python scripts/provision-e2e-user.py
```

Grant the Cloud Build SA read on those secrets:

```bash
PROJECT=stylist-dev
SA=$(gcloud projects describe $PROJECT --format='value(projectNumber)')@cloudbuild.gserviceaccount.com

for s in e2e-test-email e2e-test-password; do
  gcloud secrets add-iam-policy-binding $s --project=$PROJECT \
    --member="serviceAccount:$SA" \
    --role="roles/secretmanager.secretAccessor"
done
```

### Step 3 — Run locally to validate

```bash
cd tests/e2e
npm install
npx playwright install --with-deps chromium

export E2E_BASE_URL=https://app-dev.quantum-23.com
export E2E_AGENT_URL=https://api-dev.quantum-23.com
export E2E_FIREBASE_API_KEY=<same as _FB_API_KEY in your frontend Cloud Build trigger>
export E2E_TEST_EMAIL=e2e@stylist-dev.com
export E2E_TEST_PASSWORD=<the password you generated above>

npm test           # full suite
npm run report     # open the HTML report
```

Expected: 4 specs across 3 projects (`setup`, `auth`, `wardrobe`, `chat`),
all green, ~30s total against a warm agent (longer on cold start).

### Step 4 — Run via Cloud Build against dev

```bash
gcloud builds submit \
  --config=ci/cloudbuild-e2e.yaml \
  --substitutions=_ENV=dev,\
_BASE_URL=https://app-dev.quantum-23.com,\
_AGENT_URL=https://api-dev.quantum-23.com,\
_FB_API_KEY=AIza... .
```

Report lands at `gs://<project>_cloudbuild/e2e/<build_id>/playwright-report.zip`.

### Step 5 — Wire it into the deploy pipeline

The promotion pipeline (defined fully in §1.7) calls
`cloudbuild-e2e.yaml` as a required predecessor before flipping traffic to
the next environment. For now you can:

- Create a Cloud Build **trigger** that fires on every successful
  `cloudbuild-frontend.yaml` build for `_ENV=dev`, runs the e2e config, and
  fails the trigger group if Playwright fails.
- Block staging deploys via the trigger's "include / exclude" filters until
  the latest e2e build is green.

### Step 6 — Exit checklist for §1.6

- [ ] `npm test` in `tests/e2e/` is green locally against `dev`
- [ ] `cloudbuild-e2e.yaml` is green when triggered manually against `dev`
- [ ] HTML report uploaded to `gs://<project>_cloudbuild/e2e/<build_id>/playwright-report.zip`

> A "forced-failure" sanity run (break `useRequireAuth`, redeploy, watch
> `auth.spec.ts` fail) is worth doing **once** when you first wire the gate —
> not on every promotion.

---

## Troubleshooting (1.6)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Missing required env var: E2E_BASE_URL` | Forgot to export the env vars before `npm test` | Re-read `tests/e2e/README.md`; all five vars are required |
| `Firebase signIn failed: 400 EMAIL_NOT_FOUND` | Test user not provisioned in this env's Firebase project | Re-run `scripts/provision-e2e-user.py` with the right `PROJECT_ID` |
| `setup` project passes but `wardrobe` redirects to `/login` | localStorage record format drifted in a Firebase minor version | Bump Firebase pin in `services/frontend/package.json` and re-check the seeded user shape in `global.setup.ts` (`stsTokenManager` keys especially) |
| `chat` spec times out | LLM in `stub` mode is fine; with real OpenRouter, a cold inference pod can blow 60s | Either raise `expect.timeout` in `playwright.config.ts` or pre-warm the inference pod before triggering the e2e build |
| HTML report missing in GCS after a red run | `upload-report` step needs `set -euo pipefail` but the previous step's failure short-circuits the build | The config already runs the upload step with its own `bash`; if it still fails check the Cloud Build SA has GCS write on `gs://<project>_cloudbuild/` |
| Playwright complains it can't find Chromium | Using the wrong base image — must be `mcr.microsoft.com/playwright:vX.Y.Z-jammy` (browsers preinstalled), NOT `node:20-alpine` | Match versions: `package.json` `@playwright/test` vs. image tag |
| Specs are flaky on parallel runs | `fullyParallel` was flipped on — the suite shares a single test account | Keep `fullyParallel: false` and `workers: 1` |

---

## Troubleshooting (1.5)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `auth/unauthorized-domain` on Google sign-in popup | Frontend origin not in Firebase **Authorized domains** | Firebase console → Authentication → Settings → Authorized domains; add `app-<env>.quantum-23.com` and reload |
| `auth/invalid-api-key` in browser console | `_FB_API_KEY` substitution wrong/empty in Cloud Build | Re-run frontend build with correct substitutions; remember the bake is per-env |
| Backend rejects with `Firebase ID token has incorrect "aud"` | `FIREBASE_PROJECT_ID` on the agent doesn't match the token's project | Confirm `gcloud run services describe stylist-<env>-agent --format='value(spec.template.spec.containers[0].env)'` shows the right id; redo terraform apply |
| `inventory /users failed: 401` after sign-in | Agent runtime SA lost `roles/run.invoker` on inventory | `infra/envs/<env>/main.tf` should bind it; `terraform apply` |
| Magic link email never arrives | Firebase quota for free tier (~200/day) or sender-domain rejection | Use Google sign-in OR set up a custom email template + verified sender in Firebase console |
| `auth/email-link-sign-in-disabled` | Email-link toggle never flipped on | Firebase console → Authentication → Sign-in method → Email/Password → Email link (passwordless) |
| Sign-in works but `/wardrobe` flashes empty then redirects to `/login` | `useRequireAuth` guard fires before Firebase rehydrates the session | Make sure `firebase.ts` uses `browserLocalPersistence` (it does); check that the build wasn't done with empty `_FB_*` (frontend silently behaves as "logged out") |
| `firebase-admin` startup error `Failed to determine project ID` | `FIREBASE_PROJECT_ID` env var not set on agent | Re-apply Terraform, or `gcloud run services update stylist-<env>-agent --update-env-vars=FIREBASE_PROJECT_ID=<project>` |
| User table grows duplicates | Email casing differs between providers (Google: `Foo@x.com`, magic link: `foo@x.com`) | Normalize on the inventory side: lowercase email before SELECT/INSERT (already done in Phase 1.1 schema) — verify with `select email from users` |

---

## Troubleshooting (1.4)

| Symptom | Cause | Fix |
|---------|-------|-----|
| Browser console: `CORS policy: No 'Access-Control-Allow-Origin'` | Agent's `CORS_ALLOW_ORIGINS` doesn't include the frontend origin | `terraform apply` in the env, OR `gcloud run services update stylist-<env>-agent --update-env-vars=CORS_ALLOW_ORIGINS=https://app-<env>.quantum-23.com` |
| `POST /api/items/upload-url` returns 500 `CLOTHING_BUCKET env var not configured` | Inventory pod didn't pick up the new env var | Check `gcloud run services describe stylist-<env>-inventory --format='value(spec.template.spec.containers[0].env)'`; re-apply Terraform |
| Signed PUT URL `403 SignatureDoesNotMatch` | Browser is sending an extra header that wasn't signed | Make sure the only `Content-Type` header sent matches the one passed to `/api/items/upload-url` (default `image/jpeg`) |
| Photos load 403 in `/wardrobe` | GCS object is private (default) | Either make the bucket public-read **for the photos prefix only** (`gsutil iam ch allUsers:objectViewer gs://stylist-<env>-clothing-photos`) OR mint per-GET signed URLs in `/api/items` response (Phase 2 task) |
| `next: command not found` in Cloud Build | `npm install` skipped or pinned to wrong Node | The Dockerfile uses `node:20-alpine`. If you re-pin, also update `engines` in `package.json`. |
| Browser sees old `NEXT_PUBLIC_AGENT_URL` after switching envs | Image baked with wrong arg, or CDN/Cloud Run cache | Re-run `cloudbuild-frontend.yaml` with the correct `_ENV`; force a new revision: `gcloud run services update stylist-<env>-frontend --update-env-vars=FORCE_ROLL=$(date +%s)` |
| Chat `EventSource` closes after first event | Cloud Run buffering on slow responses, or `Content-Type` missing | Confirm agent emits `content-type: text/event-stream` and uses `sse-starlette` (`EventSourceResponse`) — already wired in `services/agent-orchestrator/app/main.py` |
| Onboarding works once, then `409` on retry | `get-or-create-user` is idempotent on `email` but you changed `preferences` — that's expected | Treat as "updated"; or clear localStorage and re-onboard with a different email |

---

## Troubleshooting (1.2)

| Symptom | Cause | Fix |
|---------|-------|-----|
| Cluster create fails with `secondaryRangeName "pods" not found` | Network module wasn't re-applied after Phase 1.2 vars added | `cd infra/envs/shared && terraform apply` (re-creates subnets with the new secondary ranges, then re-run env apply) |
| `vllm` Pod stuck `Pending` with `0/1 nodes are available: 1 node(s) had untolerated taint` | GPU node pool didn't scale up | Check `gpu_max_nodes >= 1` in the env's `module "gke"`; check the L4 quota in us-east4; `kubectl describe nodes` for taints |
| `vllm` CrashLoopBackOff with `Cannot access gated repo` | Hugging Face token missing or wrong scope | Re-create the `huggingface` Secret with a token that has access to mistralai/Mistral-7B-Instruct-v0.3 |
| `triton` Pod can't mount gcsfuse volume | gcsfuse driver disabled, or node SA lacks objectViewer | `gcloud container clusters describe stylist-$ENV-gke --format='value(addonsConfig.gcsFuseCsiDriverConfig.enabled)'` should be true (default on GKE 1.26+); re-run `prepare-fashionclip-repo.sh` to ensure the IAM bind |
| Agent gets `Connection refused` to vLLM | Firewall rule missing or IP wrong | `gcloud compute firewall-rules describe stylist-allow-connector-to-gke` should list 8000 in ports; verify `VLLM_IP` matches `kubectl get svc vllm` output and tfvars file |
| Agent stays in stub mode after wiring URLs | Cloud Run revision didn't roll | `gcloud run services describe stylist-$ENV-agent --format='value(spec.template.spec.containers[0].env)' \| grep LLM_BASE_URL` — if empty, force a revision: `gcloud run services update stylist-$ENV-agent --update-env-vars=FORCE_ROLL=$(date +%s)` |
| Qdrant Pod Pending: `no nodes match nodeSelector` | CPU pool empty or label mismatch | Verify `cloud.google.com/gke-nodepool: cpu-pool` label on a cpu-pool node; otherwise scale cpu pool: `gcloud container clusters resize stylist-$ENV-gke --node-pool=cpu-pool --num-nodes=2` |
| `nvidia-l4` not found error during node pool create | Region/zone doesn't have L4 yet | us-east4 has L4 across all three zones as of 2024; check `gcloud compute accelerator-types list --filter='zone~us-east4 AND name=nvidia-l4'`. If empty, switch to `us-central1` and re-create. |

---

## Troubleshooting (1.3)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `403 Forbidden` from agent → inventory | Missing `run.invoker` on the target service | `terraform apply` again — the binding is `google_cloud_run_v2_service_iam_member.agent_invokes_inventory` |
| `cloudbuild-service.yaml` smoke-test fails for weather/inventory with `404` and `gcloud auth print-identity-token: No identity token can be obtained` | Cloud Build's default worker pool is outside your VPC, so it cannot reach `INGRESS_TRAFFIC_INTERNAL_ONLY` services (returns 404 from GFE before auth). | Already handled in `cloudbuild-service.yaml`: smoke-test verifies revision `Ready` for internal services and only HTTP-probes public ones. End-to-end probing happens from Cloud Shell in §1.3 Step 5. |
| Inventory pod 500s with `permission denied for table users` | Postgres GRANTs not run for the IAM user | Run Step 4 — `GRANT ... ON ALL TABLES TO "inventory-$ENV-sa@..."` |
| Inventory startup probe fails with `ImportError: email-validator is not installed` | pydantic's `EmailStr` needs an optional dep | Confirm `pydantic[email]==2.9.2` (not bare `pydantic`) in `services/inventory-api/requirements.txt`; rebuild |
| Weather pod returns 502 for every request | OWM key secret not accessible | `gcloud secrets get-iam-policy openweathermap-api-key` should list `weather-<env>-sa`; re-apply Terraform |
| `api-dev.quantum-23.com` returns NXDOMAIN | DNS propagation in progress | Wait 1–5 min; verify `gcloud dns record-sets list --zone=quantum-23-com \| grep api-` |
| Agent stream returns `error` event with `LLM_BASE_URL must be set` | `LLM_MODE=openai` set before §1.2 deployed vLLM | Switch back to `LLM_MODE=stub` until vLLM is ready |
| Firestore writes 404 | Wrong DB name in `FIRESTORE_DATABASE` env var | Should be `stylist-<env>`; check `terraform output -raw firestore_database` |

---

## Troubleshooting (1.1)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Error 400: Invalid request: Cannot create instance because network ... is not authorized` | PSA peering not active before Cloud SQL apply | Wait 60s then `terraform apply` again — the peering takes a moment |
| `gcloud builds submit` migrate fails on `permission denied` connecting to Cloud SQL | Cloud Build SA missing `roles/cloudsql.client` | Re-apply shared stack — the role is in `cloudbuild_roles` |
| Migration job exits with `connection refused` to 127.0.0.1:5432 | VPC connector not attached, or PSA not peered yet | `gcloud run jobs describe stylist-${ENV}-db-migrate --format='value(template.template.vpcAccess)'` should show the connector |
| `psql: FATAL: PAM authentication failed for user "...iam"` from the migration job | First-run: IAM user has no schema privileges | Step 5 — keep `USE_IAM_AUTH=false` for first run, then GRANT and flip |
| `terraform destroy` complains Cloud SQL has `deletion_protection_enabled` | Prod safety guard | Set the guard off via `gcloud sql instances patch ... --no-deletion-protection` first |

---

## Appendix — Pausing dev between implementation phases

Once you have anything beyond §1.1 applied, dev burns roughly:

| Resource | Idle $/day |
|---|---|
| Cloud SQL `stylist-dev-pg` | ~$0.40 |
| Memorystore `stylist-dev-redis` (1 GB BASIC) | ~$1.15 |
| Serverless VPC connector (in `shared`) | ~$1.80 |
| GKE regional cluster mgmt + 1 cpu node | ~$2.40 |
| Cloud Run services (if any have `min_instances ≥ 1`) | up to $2.50 |
| Monitoring + networking + DNS + logging | ~$0.45 |
| **Total at §1.2+** | **~$7–9/day** |

None of these can be meaningfully paused (Memorystore has no stop, GKE charges
the mgmt fee even at 0 nodes, the VPC connector charges per min instance).
The only path to ~$0/day is **`terraform destroy`** on the env stack(s).

### Tear down

```bash
PROJECT=inference-expt
REGION=us-east4

# 1. (If §1.2 is up) Scale GKE workloads down so destroy doesn't wait on
#    pod-disruption / PV detach timeouts.
gcloud container clusters get-credentials stylist-dev-gke \
  --region=$REGION --project=$PROJECT 2>/dev/null && \
  kubectl -n inference scale deploy --all --replicas=0 || true

# 2. Destroy the dev env stack (kills GKE, Cloud Run, Cloud SQL, Redis).
cd ~/Inference-expt/infra/envs/dev
terraform destroy -auto-approve

# 3. (Optional, recommended for >2-day pauses) Destroy `shared` too — kills
#    the ~$1.80/day VPC connector and ~$0.20/day NAT idle costs.
cd ~/Inference-expt/infra/envs/shared
terraform destroy -auto-approve
```

What this deletes (all recreatable from git + state):
- Cloud SQL `stylist-dev-pg` **including data** — migrations live in
  `services/db-migrate/migrations/`, so the schema comes back on resume
- Memorystore `stylist-dev-redis` — cache, no persistent state
- All Cloud Run services + jobs in dev
- GKE cluster + node pools (if §1.2 was applied)
- ILB forwarding rules

What's preserved (cents/month total):
- Terraform state in `gs://inference-expt-tf-state/`
- Container images in Artifact Registry
- GCS bucket contents (`stylist-dev-clothing-photos`, etc.)
- DNS zone, PSA peering, VPC connector, Artifact Registry — these live in the
  `shared` stack which you **do not** destroy (slow + expensive to recreate)

Verify the bill went quiet (next-day check):

```bash
gcloud billing accounts list
# Then in the console: Billing → Reports → filter project=inference-expt
# Should drop to <$0.10/day within 24h of destroy.
```

### Resume

Always start with the foundation, then add only the layers you actually need
again. Each block below is **idempotent** — safe to re-run if it half-fails.

#### R0 — Foundation (always run first)

```bash
cd ~/Inference-expt
git pull --ff-only origin main

# If you destroyed `shared` in tear-down step 3, bring it back first (~15 min).
cd infra/envs/shared
terraform init -upgrade
terraform apply -auto-approve

# Dev data + IAM + Cloud Run skeletons (~15 min; Cloud SQL is the long pole).
cd ~/Inference-expt/infra/envs/dev
terraform init -upgrade
terraform apply -auto-approve

# Re-apply schema migrations (Cloud SQL is fresh — has no tables yet).
cd ~/Inference-expt
SHA=$(git rev-parse --short HEAD)
gcloud builds submit --config=ci/cloudbuild-migrate.yaml \
  --substitutions=_ENV=dev,_SHA=$SHA .
```

After R0 you have: VPC, PSA, VPC connector, DNS, Artifact Registry, Cloud SQL
(empty + migrated), Firestore, Memorystore, BigQuery datasets, GCS buckets,
all dev service accounts, and any `hello-world` Cloud Run stubs.

#### Per-phase resume matrix

Run the row matching the **furthest phase you had completed** before tearing
down. Each row includes the previous rows' work via R0 + Terraform state, so
you don't need to chain them.

| Last completed phase | What to run after R0 |
|---|---|
| **§1.1** Data layer | Nothing — R0 already restored everything in §1.1 |
| **§1.2** GKE | Re-run §1.2 Steps 3 → 6 (`get-credentials`, secrets, FashionCLIP repo, manifests, ILB tfvars round-trip) |
| **§1.3** Backend services | After §1.2 work above (if applicable): `gcloud builds submit --config=ci/cloudbuild-service.yaml --substitutions=_SERVICE=…,_ENV=dev,_SHA=$SHA .` for each of weather, inventory, agent. Then re-run §1.3 Step 4 GRANTs. |
| **§1.4** Frontend | All of §1.3 above, then `gcloud builds submit --config=ci/cloudbuild-frontend.yaml --substitutions=_ENV=dev,_SHA=$SHA .` |
| **§1.5** Auth | All of §1.4 above. Firebase project + web app config are **not** in Terraform — they persist across destroys, no rebuild needed. |
| **§1.6** E2E tests | All of §1.5 above. The e2e test user in Firebase Auth also persists. Just run `gcloud builds submit --config=ci/cloudbuild-e2e.yaml ...` to re-validate. |

Each row adds roughly 10–15 minutes on top of R0. Worst case (§1.6 from a full
teardown including `shared`): ~75 minutes wall-clock, almost all unattended.

#### One-shot resume helper

For convenience, the `/resume-dev` workflow (`.windsurf/workflows/resume-dev.md`)
runs R0 + you pick the phase from a prompt.
