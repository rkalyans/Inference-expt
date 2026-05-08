# NYC Stylist Agent

An agentic clothing recommender for NYC, built on open-weight models in GCP.

## Documents

- [`docs/ARCHITECTURE-AGENTIC.md`](docs/ARCHITECTURE-AGENTIC.md) — golden architecture (Deep Agents + open-weight models on GCP)
- [`docs/DEPLOYMENT-PLAN.md`](docs/DEPLOYMENT-PLAN.md) — phased deployment plan
- [`PHASE-0-RUNBOOK.md`](PHASE-0-RUNBOOK.md) — step-by-step Phase 0 execution

## Repository Layout

```
.
├── docs/                       # Architecture & planning
├── infra/                      # Terraform (modules + env stacks)
│   ├── modules/
│   └── envs/
│       ├── shared/             # Project-wide: VPC, DNS, Artifact Registry, observability
│       ├── dev/                # env=dev resources within inference-expt
│       ├── staging/            # env=staging resources
│       └── prod/                # env=prod resources
├── ci/                         # Cloud Build pipelines
├── scripts/                    # Bootstrap & validation scripts
├── services/
│   └── hello-world/            # Phase 0 smoke-test container
└── PHASE-0-RUNBOOK.md
```

## Phase 0 Quick Start

> **All execution happens in [Google Cloud Shell](https://shell.cloud.google.com).** Nothing runs on your local machine. Cloud Shell ships with `gcloud`, `terraform`, `docker`, `jq`, and is pre-authenticated.

```bash
# In Cloud Shell:

# 1. Set the project
gcloud config set project inference-expt

# 2. Bring this repo into Cloud Shell
git clone https://github.com/<your-org>/stylist-agent.git ~/stylist-agent
cd ~/stylist-agent
chmod +x scripts/*.sh

# 3. One-time bootstrap (state bucket + APIs)
./scripts/01-bootstrap-state.sh
./scripts/02-enable-apis.sh

# 4. Apply infra
cd infra/envs/shared
cp terraform.tfvars.example terraform.tfvars
cloudshell edit terraform.tfvars      # fill billing_account_id + alert_email
terraform init && terraform apply
cd ../dev     && terraform init && terraform apply
cd ../staging && terraform init && terraform apply
cd ../prod    && terraform init && terraform apply

# 5. Deploy hello-world via Cloud Build
cd ~/stylist-agent
gcloud builds submit --config=ci/cloudbuild-hello.yaml \
  --substitutions=_ENV=dev .

# 6. Validate
./scripts/03-validate-labels.sh
./scripts/04-iam-condition-test.sh
curl https://dev.quantum-23.com/healthz
```

See [`PHASE-0-RUNBOOK.md`](PHASE-0-RUNBOOK.md) for full instructions including OpenWeatherMap secret seeding, DLP enablement, and Langfuse deployment.

## Confirmed Inputs

| Resource | Value |
|----------|-------|
| GCP Project | `inference-expt` |
| Billing Account | `Billing-Account-Agentic` |
| Domain | `quantum-23.com` |
| Weather API | OpenWeatherMap One Call API 3.0 |

## Owner

Single owner; manual approval gate for prod (to be replaced by an agentic release gate in Phase 4).
