# Phase 0 Runbook — Foundation

**Execution model:** Every command in this runbook runs inside **Google Cloud Shell** — the browser-based shell at <https://shell.cloud.google.com>. Nothing runs on your local machine.

Cloud Shell ships pre-installed with `gcloud`, `terraform`, `docker`, `jq`, `git`, and `python3`, and is pre-authenticated as your Google account. Application Default Credentials (ADC) for Terraform are also available automatically via the Cloud Shell metadata server.

End-to-end execution time: ~2–4 hours; most of it is waiting for DNS propagation and Google-managed SSL cert issuance.



## 0. Open Cloud Shell and Bring in the Repo

1. Sign into the GCP Console as the **single owner** account: <https://console.cloud.google.com>
2. Open Cloud Shell by clicking the terminal icon in the top-right of the Console (or go to <https://shell.cloud.google.com>).
3. Confirm you're targeting the right project:

```bash
gcloud config set project inference-expt
gcloud config get-value project   # should print: inference-expt
```

4. Bring this repo into Cloud Shell. Choose ONE:

   **Option A — Clone from your Git remote** (preferred):
   ```bash
   git clone https://github.com/rkalyans/Inference-expt.git ~/Inference-expt
   cd ~/Inference-expt
   ```

   **Option B — Upload via Cloud Shell's "Upload" menu** (three-dot menu → Upload), then:
   ```bash
   cd ~/Inference-expt
   ```

5. Set runbook environment variables for the session:

```bash
export PROJECT_ID=inference-expt
export REGION=us-east4
export DOMAIN=quantum-23.com
export OWNER_EMAIL=owner@quantum-23.com   # paste the single-owner email
```

6. Verify the Cloud Shell environment is healthy. Run each command and confirm the output:

```bash
# Cloud Shell tools
gcloud version           # → prints gcloud + components
terraform version        # → ≥ 1.6
docker --version         # → any version (Cloud Shell has one)
jq --version             # → any version

# You're in Cloud Shell
echo "$CLOUD_SHELL"      # → prints: true

# Authenticated
gcloud auth list                                  # → your owner email marked ACTIVE
gcloud auth application-default print-access-token >/dev/null && echo OK   # → OK

# Right project + billing on
gcloud projects describe inference-expt --format='value(projectId)'         # → inference-expt
gcloud billing projects describe inference-expt --format='value(billingEnabled)'   # → True
```

If any check fails, see **Troubleshooting** at the bottom of this runbook.

---

## 1. Confirm Billing Account

All commands run in Cloud Shell.

```bash
gcloud billing accounts list
```
Find the row for **Billing-Account-Agentic** and copy its **ACCOUNT_ID** (format `XXXXXX-XXXXXX-XXXXXX`).

```bash
export BILLING_ACCOUNT_ID="012345-67890A-BCDEF1"   # paste your value

# Verify project is linked
gcloud billing projects describe $PROJECT_ID
# billingEnabled: true should appear

# If not linked:
# gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT_ID
```

You can cross-check in the Console: <https://console.cloud.google.com/billing/linkedaccount?project=inference-expt>

---

## 2. Bootstrap Terraform State Bucket

Creates `gs://inference-expt-tf-state` with uniform access, versioning, and a 90-day non-current-version lifecycle rule. Idempotent (safe to re-run).

### Option A — Cloud Shell commands

```bash
BUCKET="gs://inference-expt-tf-state"

# Create the bucket (skip if it already exists)
gcloud storage buckets describe "$BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "$BUCKET" \
    --project=inference-expt \
    --location=us-east4 \
    --uniform-bucket-level-access \
    --public-access-prevention

# Enable versioning
gcloud storage buckets update "$BUCKET" --versioning

# Apply lifecycle: delete noncurrent versions older than 90 days
cat > /tmp/lifecycle.json <<'EOF'
{
  "lifecycle": {
    "rule": [
      { "action": {"type": "Delete"},
        "condition": {"daysSinceNoncurrentTime": 90} }
    ]
  }
}
EOF
gcloud storage buckets update "$BUCKET" --lifecycle-file=/tmp/lifecycle.json
rm /tmp/lifecycle.json

# Verify
gcloud storage buckets describe "$BUCKET" \
  --format='value(name, location, versioning.enabled, lifecycle.rule)'
```

### Option B — Console UI

1. Open <https://console.cloud.google.com/storage/browser?project=inference-expt>.
2. Click **Create**.
3. **Name:** `inference-expt-tf-state` → **Continue**.
4. **Location type:** Region → **us-east4** → **Continue**.
5. **Storage class:** Standard → **Continue**.
6. **Access control:** Uniform → check **Enforce public access prevention** → **Continue**.
7. **Protection tools:** check **Object versioning** (default 100 versions is fine) → **Create**.
8. After creation, open the bucket → **Lifecycle** tab → **Add a rule** → Action: *Delete object* → Condition: *Days since becoming noncurrent = 90* → **Create**.

---

## 3. Enable Required APIs

Enables every API used through Phase 1. Takes 2–5 minutes. Idempotent.

### Option A — Cloud Shell

```bash
gcloud services enable \
  run.googleapis.com \
  container.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudscheduler.googleapis.com \
  pubsub.googleapis.com \
  sqladmin.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com \
  bigquery.googleapis.com \
  redis.googleapis.com \
  compute.googleapis.com \
  dns.googleapis.com \
  servicenetworking.googleapis.com \
  vpcaccess.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  dlp.googleapis.com \
  cloudkms.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  cloudtrace.googleapis.com \
  cloudprofiler.googleapis.com \
  cloudbilling.googleapis.com \
  billingbudgets.googleapis.com \
  aiplatform.googleapis.com \
  --project=inference-expt

# Verify count
gcloud services list --enabled --project=inference-expt --format='value(NAME)' | wc -l
```

### Option B — Console UI

Open <https://console.cloud.google.com/apis/library?project=inference-expt> and enable each API by name (search box). The same list as above. Slower; use only if you can't paste into Cloud Shell.

---

## 4. Apply Shared Terraform Stack

This creates: VPC, DNS zone, Artifact Registry, IAM service accounts (`terraform-sa`, `cloudbuild-sa`), Secret Manager placeholders, BigQuery ops dataset, log sinks, baseline alerting, per-env budgets.

In Cloud Shell:
```bash
cd ~/Inference-expt/infra/envs/shared
cp terraform.tfvars.example terraform.tfvars
```

Open the file in the Cloud Shell Editor (graphical editor):
```bash
cloudshell edit terraform.tfvars
```
Fill in `billing_account_id` and `owner_email`. Save and close.

Then apply:
```bash
terraform init
terraform plan -out=plan.out
terraform apply plan.out
```

Watch for the `dns_name_servers` output — you'll need it next.

---

## 5. Configure Domain Registrar (Cloud Domains)

The domain `quantum-23.com` is registered via Cloud Domains. Point its name servers at the Cloud DNS zone we just created.

In Cloud Shell:
```bash
cd ~/Inference-expt/infra/envs/shared
terraform output dns_name_servers
```

Expected output: 4 nameservers like:
```
ns-cloud-c1.googledomains.com.
ns-cloud-c2.googledomains.com.
ns-cloud-c3.googledomains.com.
ns-cloud-c4.googledomains.com.
```

Point Cloud Domains at the new zone (Cloud Shell):
```bash
gcloud domains registrations configure dns quantum-23.com \
  --cloud-dns-zone=quantum-23-com \
  --project=$PROJECT_ID
```

Or via Console: <https://console.cloud.google.com/net-services/domains/registrations?project=inference-expt> → click `quantum-23.com` → **DNS** tab → **Use Cloud DNS** → select `quantum-23-com` zone.

Verify propagation (Cloud Shell, may take 5–60 min):
```bash
dig +short NS quantum-23.com
# Should return the same 4 ns-cloud-cN.googledomains.com servers
```

---

## 6. Seed Secrets

The `shared` Terraform stack (Step 4) already created four empty secret containers in Secret Manager:

- `openweathermap-api-key`
- `langfuse-public-key`
- `langfuse-secret-key`
- `langfuse-host`

Now we add their **values** as new versions. Langfuse runs as **SaaS** at <https://cloud.langfuse.com> (no self-hosted server).

### 6.1 Get the values

**OpenWeatherMap** (One Call API 3.0):
1. Sign in at <https://home.openweathermap.org/api_keys>.
2. Confirm your subscription includes **One Call API 3.0** (free tier requires the "One Call by Call" subscription, with a 1k-call/day cap and a billing card on file). If you only see "Current weather" or "5 day forecast", upgrade at <https://home.openweathermap.org/subscriptions>.
3. Copy the API key.

**Langfuse Cloud**:
1. Sign in at <https://cloud.langfuse.com>.
2. Open (or create) the project `stylist-agent`.
3. Left nav → **Settings** → **API Keys** → **Create new API keys**.
4. Copy:
   - **Public Key** — `pk-lf-…`
   - **Secret Key** — `sk-lf-…` (shown **once**, copy immediately).
5. Note your region's host:
   - US: `https://us.cloud.langfuse.com`
   - EU: `https://cloud.langfuse.com`

### 6.2 Option A — Cloud Shell

```bash
PROJECT=inference-expt

# --- OpenWeatherMap ---
read -s -p "OpenWeatherMap API key: " OWM_KEY; echo

# Validate One Call API 3.0 reachability
curl -s -o /dev/null -w 'OWM probe: HTTP %{http_code}\n' \
  "https://api.openweathermap.org/data/3.0/onecall?lat=40.7580&lon=-73.9855&exclude=minutely,alerts&appid=$OWM_KEY"
# Expect HTTP 200. 401 → wrong key or subscription missing One Call 3.0.

printf '%s' "$OWM_KEY" | \
  gcloud secrets versions add openweathermap-api-key --data-file=- --project=$PROJECT
unset OWM_KEY

# --- Langfuse Cloud ---
read -s -p "Langfuse Public Key (pk-lf-...): " LF_PUB; echo
read -s -p "Langfuse Secret Key (sk-lf-...): " LF_SEC; echo
read    -p "Langfuse Host [https://us.cloud.langfuse.com]: " LF_HOST
LF_HOST=${LF_HOST:-https://us.cloud.langfuse.com}

printf '%s' "$LF_PUB"  | gcloud secrets versions add langfuse-public-key --data-file=- --project=$PROJECT
printf '%s' "$LF_SEC"  | gcloud secrets versions add langfuse-secret-key --data-file=- --project=$PROJECT
printf '%s' "$LF_HOST" | gcloud secrets versions add langfuse-host       --data-file=- --project=$PROJECT
unset LF_PUB LF_SEC LF_HOST

# --- Verify each secret has ≥ 1 version ---
for s in openweathermap-api-key langfuse-public-key langfuse-secret-key langfuse-host; do
  count=$(gcloud secrets versions list "$s" --project=$PROJECT --format='value(name)' | wc -l | tr -d ' ')
  echo "$s: $count version(s)"
done
# Each should show ≥ 1.
```

### 6.3 Option B — Console UI

1. Open <https://console.cloud.google.com/security/secret-manager?project=inference-expt>.
2. For each of `openweathermap-api-key`, `langfuse-public-key`, `langfuse-secret-key`, `langfuse-host`:
   - Click the secret → **+ NEW VERSION**.
   - Paste the value into **Secret value** → **ADD NEW VERSION**.
3. Validate the OpenWeatherMap key from a Cloud Shell tab:
   ```bash
   curl -s -o /dev/null -w 'HTTP %{http_code}\n' \
     "https://api.openweathermap.org/data/3.0/onecall?lat=40.7580&lon=-73.9855&exclude=minutely,alerts&appid=<paste-key>"
   ```
   Expect `HTTP 200`.
4. Validate the Langfuse credentials from a Cloud Shell tab:
   ```bash
   curl -s -o /dev/null -w 'HTTP %{http_code}\n' \
     -u "<pk-lf-...>:<sk-lf-...>" \
     "https://us.cloud.langfuse.com/api/public/projects"
   ```
   Expect `HTTP 200` with a JSON list of projects.

---

## 7. Apply Per-Env Stacks

All three stacks share the same module structure. Apply them in order in Cloud Shell:

```bash
cd ~/Inference-expt/infra/envs/dev
terraform init && terraform apply

cd ~/Inference-expt/infra/envs/staging
terraform init && terraform apply

cd ~/Inference-expt/infra/envs/prod
terraform init && terraform apply
```

Each stack creates: per-env IAM SAs, env-scoped GCS buckets, resource-level IAM bindings, and the hello-world Cloud Run service mapped to its subdomain (`dev.quantum-23.com`, `staging.quantum-23.com`, `app.quantum-23.com`).

> **Placeholder image:** Terraform creates the Cloud Run service with Google's public hello image (`us-docker.pkg.dev/cloudrun/container/hello`). Cloud Build (Step 8) then deploys the real image as a new revision. The `cloud-run-service` module has `lifecycle.ignore_changes = [template[0].containers[0].image]` so re-running `terraform apply` after Step 8 will **not** revert the deployed image.

---

## 8. Build & Deploy Hello-World via Cloud Build

The entire build runs on Cloud Build servers — Cloud Shell only submits the job. No local Docker is invoked.

```bash
cd ~/Inference-expt

SHA=$(git rev-parse --short HEAD 2>/dev/null || echo manual)

gcloud builds submit --config=ci/cloudbuild-hello.yaml \
  --substitutions=_ENV=dev,_SHA=$SHA .
```

This will:
1. Build `services/hello-world/Dockerfile` on Cloud Build
2. Push two tags to Artifact Registry (`:dev-<sha>` and `:dev-latest`)
3. Deploy to Cloud Run as `stylist-dev-hello`
4. Smoke-test `GET /` and assert the response body contains `"version":"<sha>"`, proving the just-built image is serving traffic

> **Note:** We validate via `GET /` rather than `GET /healthz` because some Cloud Run frontends intercept arbitrary health paths at the GFE layer (returning Google's HTML 404) before the request reaches the container. The container's own `/healthz` liveness probe still runs internally and is enforced by Cloud Run's `Ready` condition.

Watch the build live in Console: <https://console.cloud.google.com/cloud-build/builds?project=inference-expt>

Repeat for staging and prod:
```bash
gcloud builds submit --config=ci/cloudbuild-hello.yaml --substitutions=_ENV=staging,_SHA=$SHA .
gcloud builds submit --config=ci/cloudbuild-hello.yaml --substitutions=_ENV=prod,_SHA=$SHA .
```

---

## 9. Validate End-to-End

All validation commands run in Cloud Shell.

### 9.1 Hit the public URLs
```bash
curl https://dev.quantum-23.com/healthz
curl https://staging.quantum-23.com/healthz
curl https://app.quantum-23.com/healthz
```

Or in the Console: <https://console.cloud.google.com/run?project=inference-expt> → click each service → **URL**.

> **First request after deploy:** the Google-managed SSL cert may take 15–60 min to provision after the domain mapping is created. You'll get a TLS error until then. Plain `https://<service>-<hash>.run.app/healthz` works immediately.

### 9.2 Mandatory labels

Every `stylist-*` resource must carry `app=stylist-agent` and `env=<dev|staging|prod|shared>`.

#### Cloud Shell

```bash
PROJECT=inference-expt

# Cloud Run services — must show app + env
gcloud run services list --project=$PROJECT --format='value(metadata.name)' | \
  grep '^stylist-' | while read svc; do
    echo "== $svc"
    gcloud run services describe "$svc" --project=$PROJECT --region=us-east4 \
      --format='value(metadata.labels.app, metadata.labels.env)'
  done
# Each service should print: stylist-agent\t<env>

# GCS buckets — must show app + env
gcloud storage buckets list --project=$PROJECT --format=json | \
  jq -r '.[] | select(.name | startswith("stylist-")) | "\(.name)\tapp=\(.labels.app // "MISSING")\tenv=\(.labels.env // "MISSING")"'
# No row should contain MISSING.
```

#### Console UI

- Cloud Run: <https://console.cloud.google.com/run?project=inference-expt> → click each `stylist-*` service → **Details** tab → confirm **Labels** include `app=stylist-agent` + the right `env`.
- GCS: <https://console.cloud.google.com/storage/browser?project=inference-expt> → click each `stylist-*` bucket → **Configuration** tab → confirm **Labels** show both.

### 9.3 IAM scoping (the key safety property)

The dev runtime service account **must not** be able to read prod resources. We test this by impersonating the dev SA and trying to list a prod bucket.

#### Cloud Shell

```bash
DEV_SA="agent-orch-dev-sa@inference-expt.iam.gserviceaccount.com"
PROD_BUCKET="gs://stylist-prod-clothing-photos"

gcloud storage ls "$PROD_BUCKET" --impersonate-service-account="$DEV_SA"
```

**Expected:** the command **fails** with `permission denied` / `403 Forbidden`. That's the desired outcome — prod is correctly walled off.

If the command succeeds, prod is over-permissive. Investigate:
```bash
# What roles does the dev SA have on the prod bucket?
gcloud storage buckets get-iam-policy gs://stylist-prod-clothing-photos \
  --format=json | jq '.bindings[] | select(.members[]? | contains("agent-orch-dev-sa"))'
# Should return empty. If anything appears, remove that binding immediately.
```

#### Console UI

1. Open <https://console.cloud.google.com/iam-admin/iam?project=inference-expt>.
2. Filter by **Principal:** `agent-orch-dev-sa`.
3. Confirm: **no** roles appear scoped to prod resources.
4. For each `stylist-prod-*` bucket at <https://console.cloud.google.com/storage/browser?project=inference-expt>: open the bucket → **Permissions** tab → confirm `agent-orch-dev-sa` is **not listed**.

### 9.4 Logs and metrics

Cloud Shell:
```bash
# Recent logs from any stylist service
gcloud logging read 'labels.app="stylist-agent"' --limit=10 --format=json | \
  jq -r '.[].textPayload // .[].jsonPayload.message'

# Confirm the BigQuery sink is receiving rows (errors only)
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) FROM `inference-expt.ops_analytics.stderr_*`'
```

Or Console:
- Logs: <https://console.cloud.google.com/logs/query;query=labels.app%3D%22stylist-agent%22?project=inference-expt>
- Metrics: <https://console.cloud.google.com/monitoring/dashboards?project=inference-expt>

### 9.5 Budget alerts

Cloud Shell:
```bash
gcloud billing budgets list --billing-account=$BILLING_ACCOUNT_ID
# Should show stylist-dev-budget, stylist-staging-budget, stylist-prod-budget
```

Or Console: <https://console.cloud.google.com/billing/budgets>

---

## 10. DLP Smoke Test (Person Detection)

Verifies the data-scope guardrail works. Cloud Shell:

```bash
# Confirm DLP API is enabled and reachable from this project
gcloud services list --enabled --filter="NAME:dlp.googleapis.com"
gcloud dlp jobs list --location=$REGION --project=$PROJECT_ID --limit=1
```

Or Console: <https://console.cloud.google.com/security/sensitive-data-protection/landing?project=inference-expt>

The full DLP-on-upload Cloud Function is implemented in Phase 1.3 alongside the inventory service. For Phase 0 it is sufficient to confirm the DLP API is enabled and reachable.

---

## 11. Phase 0 Exit Checklist

All boxes can be ticked from Cloud Shell or the Console. Tick each item off `docs/DEPLOYMENT-PLAN.md` § 0.6:

- [ ] `inference-expt` linked to `Billing-Account-Agentic` (Step 1)
- [ ] `quantum-23.com` registered in Cloud Domains, NS records propagated (Step 5)
- [ ] Terraform applies cleanly to `shared`, `dev`, `staging`, `prod` (Steps 4 + 7)
- [ ] All resources carry mandatory labels (Step 9.2)
- [ ] Cloud Build can build/push/deploy hello-world (Step 8)
- [ ] `dev.quantum-23.com` resolves and serves 200 (Step 9.1)
- [ ] Logs and metrics flowing (Step 9.4)
- [ ] Langfuse Cloud project + API keys created and stored in Secret Manager (Step 6)
- [ ] OpenWeatherMap key validated and stored (Step 6)
- [ ] All four secrets have a version (Step 6)
- [ ] Per-env budget alerts active (Step 9.5)
- [ ] DLP API enabled and probed (Step 10)
- [ ] IAM scoping verified — dev SA cannot read prod (Step 9.3)

When all are checked: **Phase 0 is complete. Proceed to Phase 1.**

---

## Troubleshooting

All fixes assume Cloud Shell.

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Permission denied` on `terraform apply` | Cloud Shell session expired | Reopen Cloud Shell tab; ADC refreshes automatically |
| Domain mapping stuck `PENDING` | DNS NS records not yet at registrar | Wait, re-run `dig +short NS quantum-23.com` |
| TLS error on `dev.quantum-23.com` | Managed cert still provisioning | Wait 15–60 min after first successful DNS resolution |
| Cloud Build `denied: Permission` to push | `cloudbuild-sa` missing AR Writer | Re-apply `shared` stack; check IAM bindings |
| `terraform apply` per-env fails with `Image '...stylist-hello:latest' not found` | You cloned an older copy that hard-coded the AR image as the Terraform default. The current default is `us-docker.pkg.dev/cloudrun/container/hello` (public placeholder); Cloud Build deploys the real one in Step 8. | `git pull`, then re-run `terraform apply` |
| IAM impersonation test (§9.3) succeeds when it should fail | dev SA may genuinely not exist yet | Confirm dev stack applied: `cd infra/envs/dev && terraform output` |
| OpenWeatherMap key returns 401 | One Call API 3.0 not on subscription | Upgrade subscription tier on openweathermap.org |
| Langfuse `/api/public/projects` returns 401 | Wrong public/secret key pair, or wrong host (US vs EU) | Re-copy the keys; confirm host matches the Langfuse Cloud region |
| `cloud-domains.googleapis.com` not enabled | Domain wasn't bought via Cloud Domains | If registered elsewhere, manually update NS records at the external registrar |
| Cloud Shell disk full | Default 5GB home disk filled by Terraform plugins | `rm -rf infra/**/.terraform` and re-init only the stack you need |
| Cloud Shell session timed out mid-apply | Default 1hr inactivity timeout | Reopen Cloud Shell, run `terraform plan` to see what's left, then re-apply |

---

## Cleanup (if you need to start over)

All commands in Cloud Shell.

```bash
cd ~/Inference-expt

# Destroy in reverse order
cd infra/envs/prod    && terraform destroy && cd -
cd infra/envs/staging && terraform destroy && cd -
cd infra/envs/dev     && terraform destroy && cd -
cd infra/envs/shared  && terraform destroy && cd -

# Delete state bucket contents (preserves bucket for re-bootstrap)
gcloud storage rm -r gs://inference-expt-tf-state/**
```

Domain registration and APIs remain enabled — they're project-level, not Terraform-managed.
