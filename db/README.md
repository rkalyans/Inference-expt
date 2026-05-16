# Database migrations

Schema lives in `db/migrations/*.sql` and is applied by Cloud Build using
`@/Users/rkalyans/Desktop/Desktop/Code/Vibe-3/ci/cloudbuild-migrate.yaml`. Migrations run in lexical
order, idempotently. Each file ends by inserting its version into
`schema_migrations`; re-running is a no-op once applied.

## Apply (Cloud Shell)

```bash
gcloud builds submit --config=ci/cloudbuild-migrate.yaml \
  --substitutions=_ENV=dev .
```

The Cloud Build pipeline:
1. Reads the bootstrap password from `stylist-${_ENV}-pg-root-password` Secret Manager entry.
2. Connects to Cloud SQL via the in-process Cloud SQL Auth Proxy.
3. Runs `psql -f` against every `db/migrations/*.sql` in lexical order.
4. Verifies `schema_migrations` contains every applied version.

## Adding a migration

Create `db/migrations/000N_<name>.sql`. Wrap it in `BEGIN; … COMMIT;`. End with
`INSERT INTO schema_migrations (version) VALUES ('000N_<name>') ON CONFLICT DO NOTHING;`.
