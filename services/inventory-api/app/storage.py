"""Signed-URL minting for direct browser uploads to GCS.

Cloud Run service accounts cannot sign URLs directly with private keys, so
we use IAM-credentials based signing via `iam.signBlob`. The runtime SA
must hold `roles/iam.serviceAccountTokenCreator` on itself for this to work.
"""

from __future__ import annotations

import datetime as dt
import logging
import uuid
from typing import Tuple

import google.auth
import google.auth.transport.requests
from google.auth import iam
from google.cloud import storage
from google.oauth2 import service_account

logger = logging.getLogger(__name__)


def _signing_credentials():
    creds, project = google.auth.default()
    creds.refresh(google.auth.transport.requests.Request())
    if hasattr(creds, "service_account_email") and creds.service_account_email and creds.service_account_email != "default":
        return creds, creds.service_account_email
    # Cloud Run / GCE metadata-token credentials lack a private key. Wrap in
    # IAMCredentials-based signer.
    target = creds.service_account_email if hasattr(creds, "service_account_email") else None
    if not target or target == "default":
        from google.auth import compute_engine
        from googleapiclient import discovery
        # Resolve the runtime SA email from metadata.
        import urllib.request
        req = urllib.request.Request(
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email",
            headers={"Metadata-Flavor": "Google"},
        )
        target = urllib.request.urlopen(req, timeout=2).read().decode()
    signer = iam.Signer(google.auth.transport.requests.Request(), creds, target)
    signing_creds = service_account.Credentials(
        signer=signer,
        service_account_email=target,
        token_uri="https://oauth2.googleapis.com/token",
    )
    return signing_creds, target


def mint_upload_url(bucket: str, content_type: str, ttl_seconds: int) -> Tuple[str, str]:
    """Returns (signed_put_url, gs://uri) for a fresh object in the bucket."""
    object_name = f"uploads/{uuid.uuid4()}.bin"
    client = storage.Client()
    blob = client.bucket(bucket).blob(object_name)

    creds, sa_email = _signing_credentials()
    url = blob.generate_signed_url(
        version="v4",
        expiration=dt.timedelta(seconds=ttl_seconds),
        method="PUT",
        content_type=content_type,
        credentials=creds,
        service_account_email=sa_email,
    )
    return url, f"gs://{bucket}/{object_name}"
