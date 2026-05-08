# Cloud Build Pipelines

| File | Purpose |
|------|---------|
| `cloudbuild-infra.yaml` | Validate/plan/apply a Terraform env stack |
| `cloudbuild-hello.yaml` | Build, push, deploy, and smoke-test the Phase 0 hello service |

## Trigger model (set up in Phase 0.4)

| Event | Pipeline | Substitutions |
|-------|----------|---------------|
| PR to `main` | `cloudbuild-infra.yaml` | `_ACTION=plan`, `_STACK=<changed>` |
| PR to `main` | `cloudbuild-hello.yaml` | `_ENV=dev` (deploy preview) |
| Merge to `main` | `cloudbuild-infra.yaml` | `_ACTION=apply` for affected stacks |
| Merge to `main` | `cloudbuild-hello.yaml` | `_ENV=staging` |
| Tag `v*.*.*` | `cloudbuild-hello.yaml` | `_ENV=prod` (with manual approval) |

## Manual approval gate (prod)

Configure a Cloud Build trigger on the `prod` workflow with `requireApproval: true`. Cloud Build will pause and notify the single owner via the email channel until approval is granted in the GCP Console.

## Manual invocation (Phase 0)

Run from **Cloud Shell** at <https://shell.cloud.google.com>. Cloud Build executes the build itself on Google-managed workers; Cloud Shell only submits the job.

```bash
cd ~/stylist-agent

# Apply shared stack
gcloud builds submit --config=ci/cloudbuild-infra.yaml \
  --substitutions=_STACK=shared,_ACTION=apply .

# Deploy hello to dev
gcloud builds submit --config=ci/cloudbuild-hello.yaml \
  --substitutions=_ENV=dev .
```

Watch builds live in the Console: <https://console.cloud.google.com/cloud-build/builds?project=inference-expt>
