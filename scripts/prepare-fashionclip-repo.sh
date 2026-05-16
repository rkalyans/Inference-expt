#!/usr/bin/env bash
# prepare-fashionclip-repo.sh
#
# One-time per environment: download FashionCLIP from Hugging Face, export the
# vision encoder to ONNX, and upload to the Triton model repository bucket
# `stylist-<env>-fashionclip-models`.
#
# Run from a machine with GPU is preferred (faster export) but CPU works too.
# Requires: python3.10+, pip, gcloud, gsutil.
#
# Usage:
#   ./prepare-fashionclip-repo.sh dev

set -euo pipefail

ENV="${1:-dev}"
PROJECT="${PROJECT_ID:-inference-expt}"
BUCKET="stylist-${ENV}-fashionclip-models"
WORK="$(mktemp -d)"
echo ">> work dir: $WORK"

# Create bucket if missing (uniform IAM, region matches GKE).
if ! gsutil ls -b "gs://${BUCKET}" >/dev/null 2>&1; then
  gsutil mb -p "$PROJECT" -l us-east4 -b on "gs://${BUCKET}"
fi

# Grant the GKE node SA read access (Triton pod uses it via gcsfuse-csi-driver).
NODE_SA="gke-${ENV}-node-sa@${PROJECT}.iam.gserviceaccount.com"
gsutil iam ch "serviceAccount:${NODE_SA}:roles/storage.objectViewer" "gs://${BUCKET}"

# Install deps in an isolated venv.
python3 -m venv "$WORK/venv"
# shellcheck disable=SC1091
source "$WORK/venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet \
  "transformers==4.45.2" \
  "torch==2.4.1" \
  "onnx==1.17.0" \
  "Pillow==10.4.0" \
  "huggingface-hub==0.25.2"

# Export the vision encoder. We only need image embeddings server-side; the
# text tower runs on the client when needed (or never, if we use prompts in
# the LLM directly).
python3 - <<'PY'
import os, torch
from transformers import CLIPModel, CLIPProcessor

MODEL = "patrickjohncyh/fashion-clip"
out = os.environ["WORK"] + "/fashionclip"
os.makedirs(out, exist_ok=True)

model = CLIPModel.from_pretrained(MODEL).eval()
proc  = CLIPProcessor.from_pretrained(MODEL)

# Save processor (preprocessing config) so the inference client can read it.
proc.save_pretrained(out + "/processor")

# Export the vision encoder.
class VisionWrap(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, pixel_values):
        return self.m.get_image_features(pixel_values=pixel_values)

dummy = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    VisionWrap(model), dummy, out + "/model.onnx",
    input_names=["pixel_values"],
    output_names=["image_embeds"],
    dynamic_axes={"pixel_values": {0: "batch"}, "image_embeds": {0: "batch"}},
    opset_version=17,
)
print("ok:", out + "/model.onnx")
PY

# Triton expects: <repo>/<model>/<version>/<file>
REPO="$WORK/repo/fashionclip"
mkdir -p "$REPO/1"
cp "$WORK/fashionclip/model.onnx" "$REPO/1/model.onnx"
cat > "$REPO/config.pbtxt" <<'CFG'
name: "fashionclip"
platform: "onnxruntime_onnx"
max_batch_size: 32
input [
  { name: "pixel_values" data_type: TYPE_FP32 dims: [3, 224, 224] }
]
output [
  { name: "image_embeds" data_type: TYPE_FP32 dims: [512] }
]
instance_group [{ count: 1 kind: KIND_GPU }]
dynamic_batching { preferred_batch_size: [4, 8, 16] max_queue_delay_microseconds: 5000 }
CFG

# Sync to GCS.
gsutil -m rsync -r -d "$WORK/repo/" "gs://${BUCKET}/"

echo ">> ready: gs://${BUCKET}/fashionclip/"
echo ">> Triton will pick this up automatically on its next poll (60s)."
