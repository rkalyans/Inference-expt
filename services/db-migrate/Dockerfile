FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

# psql + cloud-sql-proxy
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      postgresql-client wget curl jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /usr/local/bin/cloud-sql-proxy \
      https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.11.0/cloud-sql-proxy.linux.amd64 \
 && chmod +x /usr/local/bin/cloud-sql-proxy

WORKDIR /app

# Build context is the repo root (see ci/cloudbuild-migrate.yaml).
COPY services/db-migrate/migrate.sh /app/migrate.sh
RUN chmod +x /app/migrate.sh

# Migrations are baked into the image at build time.
COPY db/migrations /app/migrations

ENTRYPOINT ["/app/migrate.sh"]
