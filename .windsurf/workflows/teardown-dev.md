---
description: Tear down the dev GCP env to ~$0.10/day between implementation phases
---

# Teardown dev environment

This workflow destroys all billable dev resources (Cloud SQL, Memorystore, GKE,
Cloud Run, ILBs) and optionally the `shared` stack (VPC connector, NAT) so the
project bill drops from ~$7/day to under $0.10/day.

What's preserved (cents/month):
- Terraform state in `gs://inference-expt-tf-state/`
- Container images in Artifact Registry
- GCS bucket contents (`stylist-dev-clothing-photos`, etc.)
- Firebase project + web app config (not in Terraform)
- DNS zone (~$0.50/mo)

## Steps

1. Confirm with the user which scope to tear down:
   - **dev only** (~$2/day after teardown — keeps `shared` so resume is faster)
   - **dev + shared** (~$0.10/day — destroys VPC connector + NAT; resume takes ~15 min longer)

2. (If GKE is up) Scale workloads to zero so destroy doesn't time out on PV/PDB.
   // turbo
   ```bash
   gcloud container clusters get-credentials stylist-dev-gke \
     --region=us-east4 --project=inference-expt 2>/dev/null && \
     kubectl -n inference scale deploy --all --replicas=0 || true
   ```

3. Destroy the dev env stack.
   ```bash
   cd ~/Inference-expt/infra/envs/dev
   terraform destroy -auto-approve
   ```

4. (Only if user chose "dev + shared") Destroy the shared stack.
   ```bash
   cd ~/Inference-expt/infra/envs/shared
   terraform destroy -auto-approve
   ```

5. Print a one-liner the user can run tomorrow to verify the bill dropped:
   ```bash
   echo "Check tomorrow: https://console.cloud.google.com/billing → project=inference-expt → daily total should be < \$0.10"
   ```

6. Remind the user that resuming is `/resume-dev` and the per-phase resume
   matrix lives in `PHASE-1-RUNBOOK.md` → "Appendix — Pausing dev".
