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
git clone https://github.com/rkalyans/Inference-expt.git ~/Inference-expt
cd ~/Inference-expt

# 3. Create the Terraform state bucket (full commands in PHASE-0-RUNBOOK.md §2)
gcloud storage buckets create gs://inference-expt-tf-state \
  --location=us-east4 --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://inference-expt-tf-state --versioning

# 4. Enable APIs (full list in PHASE-0-RUNBOOK.md §3)
gcloud services enable run.googleapis.com container.googleapis.com \
  storage.googleapis.com bigquery.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com dns.googleapis.com \
  compute.googleapis.com logging.googleapis.com monitoring.googleapis.com \
  cloudresourcemanager.googleapis.com iam.googleapis.com cloudbilling.googleapis.com \
  billingbudgets.googleapis.com dlp.googleapis.com

# 5. Apply infra
cd infra/envs/shared
cp terraform.tfvars.example terraform.tfvars
cloudshell edit terraform.tfvars      # fill billing_account_id + owner_email
terraform init && terraform apply
cd ../dev     && terraform init && terraform apply
cd ../staging && terraform init && terraform apply
cd ../prod    && terraform init && terraform apply

# 6. Deploy hello-world via Cloud Build
cd ~/Inference-expt
gcloud builds submit --config=ci/cloudbuild-hello.yaml \
  --substitutions=_ENV=dev .

# 7. Validate
curl https://dev.quantum-23.com/api/health
```

See [`PHASE-0-RUNBOOK.md`](PHASE-0-RUNBOOK.md) for **full** instructions including label/IAM verification, OpenWeatherMap + Langfuse Cloud secret seeding, and DLP enablement. Every step has both a Cloud Shell command form and a Console UI walkthrough.

## Confirmed Inputs

| Resource | Value |
|----------|-------|
| GCP Project | `inference-expt` |
| Billing Account | `Billing-Account-Agentic` |
| Domain | `quantum-23.com` |
| Weather API | OpenWeatherMap One Call API 3.0 |

## Owner

Single owner; manual approval gate for prod (to be replaced by an agentic release gate in Phase 4).
