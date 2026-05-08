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
   git clone https://github.com/<your-org>/stylist-agent.git ~/stylist-agent
   cd ~/stylist-agent
   ```

   **Option B — Upload via Cloud Shell's "Upload" menu** (three-dot menu → Upload), then:
   ```bash
   cd ~/Vibe-3
   ```

5. Set runbook environment variables for the session:

```bash
export PROJECT_ID=inference-expt
export REGION=us-east4
export DOMAIN=quantum-23.com
export ALERT_EMAIL=owner@quantum-23.com   # paste the single-owner email
```

6. Make the helper scripts executable:

```bash
chmod +x scripts/*.sh
```

7. Verify the Cloud Shell environment is healthy:

```bash
./scripts/00-prereqs.sh
```
Expected: `All prerequisites satisfied.` Skip the install checks — Cloud Shell guarantees them.

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

```bash
./scripts/01-bootstrap-state.sh
```
Creates `gs://inference-expt-tf-state` with versioning + lifecycle. Idempotent.

---

## 3. Enable Required APIs

```bash
./scripts/02-enable-apis.sh
```
Enables ~25 APIs. Takes 2–5 minutes. Idempotent.

---

## 4. Apply Shared Terraform Stack

This creates: VPC, DNS zone, Artifact Registry, IAM service accounts (`terraform-sa`, `cloudbuild-sa`, Langfuse SA), Secret Manager placeholders, BigQuery ops dataset, log sinks, baseline alerting, budgets.

In Cloud Shell:
```bash
cd ~/stylist-agent/infra/envs/shared
cp terraform.tfvars.example terraform.tfvars
```

Open the file in the Cloud Shell Editor (graphical editor):
```bash
cloudshell edit terraform.tfvars
```
Fill in `billing_account_id` and `alert_email`. Leave `deploy_langfuse = false` for this first apply. Save and close.

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
cd ~/stylist-agent/infra/envs/shared
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

OpenWeatherMap key + Langfuse bootstrap secrets. Run all of this in Cloud Shell so the values never touch your laptop.

```bash
cd ~/stylist-agent

# Paste the OpenWeatherMap key (One Call API 3.0 enabled subscription).
# Use Cloud Shell's secure paste (right-click → Paste) so it isn't echoed in scrollback.
read -s -p "OpenWeatherMap API key: " OPENWEATHERMAP_API_KEY; echo
export OPENWEATHERMAP_API_KEY

# Generate Langfuse internals (Cloud Shell has openssl)
export LANGFUSE_NEXTAUTH_SECRET="$(openssl rand -base64 32)"
export LANGFUSE_SALT="$(openssl rand -base64 32)"
# Database URL — placeholder for Phase 0; real Cloud SQL backing comes in Phase 1
export LANGFUSE_DATABASE_URL="postgresql://placeholder:placeholder@localhost/langfuse"

./scripts/05-seed-secrets.sh
```

The script also probes `https://api.openweathermap.org/data/3.0/onecall` to confirm One Call API 3.0 is reachable with your key.

Add the additional Langfuse secrets:
```bash
printf '%s' "$LANGFUSE_NEXTAUTH_SECRET" | \
  gcloud secrets versions add langfuse-nextauth-secret --data-file=-
printf '%s' "$LANGFUSE_SALT" | \
  gcloud secrets versions add langfuse-salt --data-file=-
printf '%s' "$LANGFUSE_DATABASE_URL" | \
  gcloud secrets versions add langfuse-database-url --data-file=-
```

---

## 7. (Optional) Re-Apply Shared Stack with Langfuse Enabled

In Cloud Shell:
```bash
cd ~/stylist-agent/infra/envs/shared
cloudshell edit terraform.tfvars   # set deploy_langfuse = true, save
terraform apply
```

Output `langfuse_url` will give you the Cloud Run URL. Internal-only for now (`INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`).

> **Note:** The doc plans Langfuse on GKE. To keep Phase 0 idle cost ~$30/mo we deploy on Cloud Run + a placeholder DB. Re-platform to GKE in Phase 1.2 when GKE is provisioned for inference.

---

## 8. Apply Per-Env Stacks

All three stacks share the same module structure. Apply them in order in Cloud Shell:

```bash
cd ~/stylist-agent/infra/envs/dev
terraform init && terraform apply

cd ~/stylist-agent/infra/envs/staging
terraform init && terraform apply

cd ~/stylist-agent/infra/envs/prod
terraform init && terraform apply
```

Each stack creates: per-env IAM SAs, env-scoped GCS buckets, resource-level IAM bindings, and the hello-world Cloud Run service mapped to its subdomain (`dev.quantum-23.com`, `staging.quantum-23.com`, `app.quantum-23.com`).

---

## 9. Build & Deploy Hello-World via Cloud Build

The entire build runs on Cloud Build servers — Cloud Shell only submits the job. No local Docker is invoked.

```bash
cd ~/stylist-agent

gcloud builds submit --config=ci/cloudbuild-hello.yaml \
  --substitutions=_ENV=dev,SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo manual) .
```

This will:
1. Build `services/hello-world/Dockerfile` on Cloud Build
2. Push two tags to Artifact Registry
3. Deploy to Cloud Run as `stylist-dev-hello`
4. Smoke-test `/healthz`

Watch the build live in Console: <https://console.cloud.google.com/cloud-build/builds?project=inference-expt>

Repeat for staging and prod:
```bash
gcloud builds submit --config=ci/cloudbuild-hello.yaml --substitutions=_ENV=staging .
gcloud builds submit --config=ci/cloudbuild-hello.yaml --substitutions=_ENV=prod .
```

---

## 10. Validate End-to-End

All validation commands run in Cloud Shell.

### 10.1 Hit the public URLs
```bash
curl https://dev.quantum-23.com/healthz
curl https://staging.quantum-23.com/healthz
curl https://app.quantum-23.com/healthz
```

Or in the Console: <https://console.cloud.google.com/run?project=inference-expt> → click each service → **URL**.

> **First request after deploy:** the Google-managed SSL cert may take 15–60 min to provision after the domain mapping is created. You'll get a TLS error until then. Plain `https://<service>-<hash>.run.app/healthz` works immediately.

### 10.2 Mandatory labels
```bash
./scripts/03-validate-labels.sh
```
Expected: `PASS: All stylist-* resources have the required labels.`

### 10.3 IAM scoping (the key safety property)
```bash
./scripts/04-iam-condition-test.sh
```
Expected: `PASS: dev SA correctly denied access to prod bucket.`

If this fails, prod is over-permissive — investigate immediately.

### 10.4 Logs and metrics

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

### 10.5 Budget alerts

Cloud Shell:
```bash
gcloud billing budgets list --billing-account=$BILLING_ACCOUNT_ID
# Should show stylist-dev-budget, stylist-staging-budget, stylist-prod-budget
```

Or Console: <https://console.cloud.google.com/billing/budgets>

---

## 11. DLP Smoke Test (Person Detection)

Verifies the data-scope guardrail works. Cloud Shell:

```bash
# Confirm DLP API is enabled and reachable from this project
gcloud services list --enabled --filter="NAME:dlp.googleapis.com"
gcloud dlp jobs list --location=$REGION --project=$PROJECT_ID --limit=1
```

Or Console: <https://console.cloud.google.com/security/sensitive-data-protection/landing?project=inference-expt>

The full DLP-on-upload Cloud Function is implemented in Phase 1.3 alongside the inventory service. For Phase 0 it is sufficient to confirm the DLP API is enabled and reachable.

---

## 12. Phase 0 Exit Checklist

All boxes can be ticked from Cloud Shell or the Console. Tick each item off `docs/DEPLOYMENT-PLAN.md` § 0.6:

- [ ] `inference-expt` linked to `Billing-Account-Agentic` (Step 1)
- [ ] `quantum-23.com` registered in Cloud Domains, NS records propagated (Step 5)
- [ ] Terraform applies cleanly to `shared`, `dev`, `staging`, `prod` (Steps 4 + 8)
- [ ] All resources carry mandatory labels (Step 10.2)
- [ ] Cloud Build can build/push/deploy hello-world (Step 9)
- [ ] `dev.quantum-23.com` resolves and serves 200 (Step 10.1)
- [ ] Logs and metrics flowing (Step 10.4)
- [ ] Langfuse reachable internally (Step 7)
- [ ] OpenWeatherMap key validated and stored (Step 6)
- [ ] All secrets in Secret Manager (Step 6)
- [ ] Per-env budget alerts active (Step 10.5)
- [ ] DLP API enabled and probed (Step 11)
- [ ] IAM scoping verified — dev SA cannot read prod (Step 10.3)

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
| `04-iam-condition-test.sh` PASSES but seems wrong | dev SA may genuinely not exist yet | Confirm dev stack applied: `cd infra/envs/dev && terraform output` |
| OpenWeatherMap key returns 401 | One Call API 3.0 not on subscription | Upgrade subscription tier on openweathermap.org |
| `cloud-domains.googleapis.com` not enabled | Domain wasn't bought via Cloud Domains | If registered elsewhere, manually update NS records at the external registrar |
| Cloud Shell disk full | Default 5GB home disk filled by Terraform plugins | `rm -rf infra/**/.terraform` and re-init only the stack you need |
| Cloud Shell session timed out mid-apply | Default 1hr inactivity timeout | Reopen Cloud Shell, run `terraform plan` to see what's left, then re-apply |

---

## Cleanup (if you need to start over)

All commands in Cloud Shell.

```bash
cd ~/stylist-agent

# Destroy in reverse order
cd infra/envs/prod    && terraform destroy && cd -
cd infra/envs/staging && terraform destroy && cd -
cd infra/envs/dev     && terraform destroy && cd -
cd infra/envs/shared  && terraform destroy && cd -

# Delete state bucket contents (preserves bucket for re-bootstrap)
gcloud storage rm -r gs://inference-expt-tf-state/**
```

Domain registration and APIs remain enabled — they're project-level, not Terraform-managed.
