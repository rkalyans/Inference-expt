---
description: Resume the dev GCP env after a /teardown-dev pause, up to the phase the user picks
---

# Resume dev environment

This workflow re-applies the dev infrastructure and redeploys application
layers up to whichever phase the user had completed before pausing.

## Steps

1. Ask the user which phase they had completed before the teardown. Options:
   - `1.1` Data layer
   - `1.2` GKE inference cluster
   - `1.3` Backend services (weather, inventory, agent)
   - `1.4` Frontend
   - `1.5` Auth
   - `1.6` E2E tests

2. **R0 — Foundation** (always run; takes ~15–30 min total).

   ```bash
   cd ~/Inference-expt
   git pull --ff-only origin main
   ```

   // turbo
   ```bash
   if [ -d infra/envs/shared/.terraform ] || gcloud compute networks describe stylist-vpc --project=inference-expt 2>/dev/null | grep -q name; then
     echo "shared stack appears to exist — skipping shared apply"
   else
     cd ~/Inference-expt/infra/envs/shared
     terraform init -upgrade
     terraform apply -auto-approve
   fi
   ```

   ```bash
   cd ~/Inference-expt/infra/envs/dev
   terraform init -upgrade
   terraform apply -auto-approve
   ```

   ```bash
   cd ~/Inference-expt
   SHA=$(git rev-parse --short HEAD)
   gcloud builds submit --config=ci/cloudbuild-migrate.yaml \
     --substitutions=_ENV=dev,_SHA=$SHA .
   ```

3. Run the per-phase rebuild — **only** the steps for phases up to and
   including the one the user picked. Each block is independent.

   **If user picked 1.2 or beyond:** redeploy the GKE inference stack.
   ```bash
   gcloud container clusters get-credentials stylist-dev-gke \
     --region=us-east4 --project=inference-expt

   # Recreate inference namespace + huggingface secret (one-time; HF token in user's hands)
   kubectl create ns inference --dry-run=client -o yaml | kubectl apply -f -
   read -s -p "HF token: " HF_TOKEN; echo
   kubectl -n inference create secret generic huggingface \
     --from-literal=token="$HF_TOKEN" --dry-run=client -o yaml | kubectl apply -f -

   # Re-upload FashionCLIP repo (idempotent; skips if already in GCS)
   cd ~/Inference-expt
   ./scripts/prepare-fashionclip-repo.sh dev

   # Reapply k8s manifests
   cd ~/Inference-expt/infra/k8s/inference
   export MODEL_REPO_BUCKET=stylist-dev-fashionclip-models
   kubectl apply -f 00-namespace.yaml
   kubectl apply -f 10-vllm.yaml
   kubectl apply -f 30-qdrant.yaml
   envsubst < 20-triton.yaml | kubectl apply -f -

   # Wait for LBs, then write IPs back into tfvars + re-apply dev
   sleep 60
   VLLM_IP=$(kubectl -n inference get svc vllm -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   TRITON_IP=$(kubectl -n inference get svc triton -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   QDRANT_IP=$(kubectl -n inference get svc qdrant -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   cat > ~/Inference-expt/infra/envs/dev/inference.auto.tfvars <<EOF
   llm_base_url    = "http://$VLLM_IP/v1"
   triton_base_url = "http://$TRITON_IP:8002"
   qdrant_base_url = "http://$QDRANT_IP:6333"
   EOF
   cd ~/Inference-expt/infra/envs/dev && terraform apply -auto-approve
   ```

   **If user picked 1.3 or beyond:** redeploy backend services.
   ```bash
   cd ~/Inference-expt
   SHA=$(git rev-parse --short HEAD)
   for pair in "weather-api weather" "inventory-api inventory" "agent-orchestrator agent"; do
     set -- $pair
     gcloud builds submit --config=ci/cloudbuild-service.yaml \
       --substitutions=_SERVICE=$1,_SHORT_NAME=$2,_ENV=dev,_SHA=$SHA .
   done
   ```
   Then re-run §1.3 Step 4 GRANTs against Cloud SQL (use `gcloud sql connect`
   per §1.1 Step 4b, briefly attaching a public IP).

   **If user picked 1.4 or beyond:** redeploy frontend.
   ```bash
   cd ~/Inference-expt
   SHA=$(git rev-parse --short HEAD)
   gcloud builds submit --config=ci/cloudbuild-frontend.yaml \
     --substitutions=_ENV=dev,_SHA=$SHA \
     --substitutions=_FB_API_KEY=...,_FB_AUTH_DOMAIN=...,_FB_PROJECT_ID=...,_FB_APP_ID=... .
   ```
   Firebase substitutions are unchanged from §1.5 Step 4; pull from the
   Firebase console if you don't have them stashed.

   **If user picked 1.5 or beyond:** auth is already wired into agent + frontend
   by the §1.3 and §1.4 redeploys above. No extra step required.

   **If user picked 1.6:** re-run the e2e Cloud Build to validate the chain.
   ```bash
   gcloud builds submit --config=ci/cloudbuild-e2e.yaml \
     --substitutions=_ENV=dev,\
   _BASE_URL=https://app-dev.quantum-23.com,\
   _AGENT_URL=https://api-dev.quantum-23.com,\
   _FB_API_KEY=AIza... .
   ```

4. Health check — run the §1.1 Step 6 three-liner to confirm the data plane is
   back:
   ```bash
   PROJECT=inference-expt
   REGION=us-east4
   gcloud sql instances describe stylist-dev-pg --project=$PROJECT --format='value(state)'
   gcloud firestore databases describe --database=stylist-dev --project=$PROJECT --format='value(type,locationId)'
   gcloud redis instances describe stylist-dev-redis --region=$REGION --project=$PROJECT --format='value(state)'
   ```

5. Confirm with the user that the resume is complete and ready for the next
   phase of implementation.
