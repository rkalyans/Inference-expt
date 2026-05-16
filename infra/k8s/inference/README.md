# inference/ — GKE workloads

Three pods make up the Stylist inference stack:

| Pod | Image | Pool | Purpose |
|---|---|---|---|
| `vllm` | `vllm/vllm-openai:v0.6.3` | gpu-l4-pool | OpenAI-compatible LLM (Mistral-7B-Instruct-v0.3). Agent calls `/v1/chat/completions`. |
| `triton` | `nvcr.io/nvidia/tritonserver:24.08-py3` | gpu-l4-pool | FashionCLIP via ONNX. Inventory calls for clothing-item embeddings. |
| `qdrant` | `qdrant/qdrant:v1.12.4` | cpu-pool | Vector DB for FashionCLIP embeddings + similarity search. |

All three are exposed via **Internal Load Balancers** so only callers inside
the VPC (Cloud Run via the serverless VPC connector) can reach them. There
is no public ingress.

## Files

- `00-namespace.yaml` — `inference` namespace + service accounts (one per workload)
- `10-vllm.yaml` — vLLM Deployment + Service + HPA
- `20-triton.yaml` — Triton Deployment + Service. Loads model repo from a GCS bucket via the `gcsfuse-csi-driver`
- `30-qdrant.yaml` — Qdrant StatefulSet + headless + ILB Services. Persists to a 20Gi PD-balanced volume

## Apply

The runbook (`PHASE-1-RUNBOOK.md` §1.2) has the full step-by-step. Quick path:

```bash
ENV=dev
PROJECT=inference-expt
REGION=us-east4

# Auth kubectl
gcloud container clusters get-credentials stylist-$ENV-gke \
  --region=$REGION --project=$PROJECT

# Create the Hugging Face token Secret (Mistral is gated)
kubectl create ns inference --dry-run=client -o yaml | kubectl apply -f -
kubectl -n inference create secret generic huggingface \
  --from-literal=token="$HF_TOKEN" --dry-run=client -o yaml | kubectl apply -f -

# Render Triton manifest with the model-repo bucket name
export MODEL_REPO_BUCKET=stylist-$ENV-fashionclip-models
envsubst < 20-triton.yaml > 20-triton.rendered.yaml

kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-vllm.yaml
kubectl apply -f 20-triton.rendered.yaml
kubectl apply -f 30-qdrant.yaml

# Wait for ILBs to allocate IPs
kubectl -n inference get svc -w
```

## Sizing knobs

| Variable | vLLM | Triton | Qdrant |
|---|---|---|---|
| Replicas | 1–3 (HPA) | 1 | 1 |
| GPU | 1× L4 | 1× L4 | none |
| Memory request | 16Gi | 8Gi | 1Gi |
| Storage | 60Gi ephemeral (model cache) | gcsfuse RO | 20Gi PD |
| Scale-to-zero | with `gpu_min_nodes=0` | with `gpu_min_nodes=0` | no |

> **GPU floor in dev:** Terraform sets `gpu_min_nodes=0`. The vLLM Deployment
> stays at `replicas: 1` even when the node pool is at 0 — the pod sits
> Pending until autoscaler provisions a GPU node. To force scale-down, run
> `kubectl -n inference scale deploy/vllm --replicas=0`. Reverse with `--replicas=1`.

## Monitoring

GKE Cloud Logging + Cloud Monitoring are enabled on the cluster. vLLM and
Triton both expose Prometheus metrics; Phase 2 wires Managed Prometheus to
scrape them.
