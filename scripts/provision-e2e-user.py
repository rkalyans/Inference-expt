#!/usr/bin/env python3
"""Provision (or reset the password of) the e2e test user for a given env.

Usage:
    GOOGLE_APPLICATION_CREDENTIALS=... \\
    PROJECT_ID=inference-expt \\
    TEST_EMAIL=e2e@stylist.test \\
    TEST_PASSWORD='secret' \\
    python scripts/provision-e2e-user.py

(One Firebase project per GCP project; for dev that is `inference-expt`.)

Idempotent. If the user already exists, just updates the password. Designed
to be run once per environment, not from CI.
"""
from __future__ import annotations

import os
import sys

import firebase_admin
from firebase_admin import auth, credentials


def main() -> int:
    project_id = os.environ["PROJECT_ID"]
    email = os.environ["TEST_EMAIL"]
    password = os.environ["TEST_PASSWORD"]

    firebase_admin.initialize_app(
        credentials.ApplicationDefault(),
        {"projectId": project_id},
    )

    try:
        user = auth.get_user_by_email(email)
        auth.update_user(user.uid, password=password, email_verified=True)
        print(f"updated existing user: {user.uid} ({email})")
    except auth.UserNotFoundError:
        user = auth.create_user(email=email, password=password, email_verified=True)
        print(f"created user: {user.uid} ({email})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
