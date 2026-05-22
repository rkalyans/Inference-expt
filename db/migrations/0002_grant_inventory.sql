-- Phase 1.3 — Grant the inventory runtime SA Postgres-side privileges.
-- Applied by the db-migrate Cloud Run Job (which runs as stylist-root, the
-- schema owner). The IAM Postgres user itself is created by Terraform
-- (google_sql_user.inventory_iam) and has no privileges by default.
--
-- Idempotent: GRANT and ALTER DEFAULT PRIVILEGES are no-ops if already applied.
-- Multi-env safe: the username is interpolated from the current_database()
-- value via a DO block so the same file works in dev/staging/prod.

DO $$
DECLARE
  inv_user text;
BEGIN
  -- The Cloud Run Job sets PROJECT_ID + ENV. We don't have those in psql,
  -- but the migrate.sh sets a `current_database()` that always starts with
  -- "stylist". We instead read the env from a session GUC the migrate
  -- script can set, or fall back to reading from a settings table.
  --
  -- Simplest: list the candidate IAM users and grant to whichever exists.
  -- This avoids hard-coding the env name into the SQL file.
  FOR inv_user IN
    SELECT rolname FROM pg_roles
    WHERE rolname LIKE 'inventory-%-sa@%.iam'
  LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', inv_user);
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I',
      inv_user
    );
    EXECUTE format(
      'GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO %I',
      inv_user
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I',
      inv_user
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO %I',
      inv_user
    );
    RAISE NOTICE 'Granted CRUD privileges to %', inv_user;
  END LOOP;
END
$$;
