# Infrastructure (Terraform)

All envs live in a single GCP project (`inference-expt`). Isolation is enforced via labels, naming, subnets, GKE namespaces, and IAM Conditions.

## Stack order

```
shared  → dev → staging → prod
```

`shared` MUST be applied first — it creates the VPC, DNS zone, Artifact Registry, observability primitives, and project-wide service accounts. Each env stack consumes those via `terraform_remote_state`.

## State

- Bucket: `gs://inference-expt-tf-state`
- Prefix per stack: `shared/`, `dev/`, `staging/`, `prod/`

## Apply

> Run all `terraform` commands inside **Google Cloud Shell** (<https://shell.cloud.google.com>). Cloud Shell provides Terraform, ADC, and `gcloud` — no local installs needed.

```bash
cd ~/Inference-expt/infra/envs/shared
terraform init && terraform apply

cd ~/Inference-expt/infra/envs/dev
terraform init && terraform apply

cd ~/Inference-expt/infra/envs/staging
terraform init && terraform apply

cd ~/Inference-expt/infra/envs/prod
terraform init && terraform apply
```

## Modules

| Module | Purpose |
|--------|---------|
| `network` | VPC + per-env subnets + Cloud NAT |
| `dns` | Cloud DNS managed zone for `quantum-23.com` |
| `artifact-registry` | Docker repo for all containers |
| `iam` | Per-env service accounts with IAM Conditions on `env` label |
| `observability` | Log sinks, alerting policies, per-env budget alerts, BigQuery ops dataset (Langfuse runs as SaaS) |
| `secrets` | Secret Manager bootstrap (empty placeholders; values added manually — see PHASE-0-RUNBOOK.md §6) |
| `cloud-run-service` | Reusable Cloud Run service (used by hello-world and later phases) |

## Mandatory labels

Every resource MUST carry:
- `env` — `dev` | `staging` | `prod` | `shared`
- `app` — `stylist-agent`

Validation commands live in PHASE-0-RUNBOOK.md §9.2 (mandatory labels) and §9.3 (IAM scoping). Both have a Cloud Shell command form and a Console UI walkthrough.
