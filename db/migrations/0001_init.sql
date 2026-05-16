-- Phase 1.1 initial schema for the stylist-agent Postgres database.
-- Applied by the db-migrate Cloud Build job (ci/cloudbuild-migrate.yaml).
--
-- Conventions:
--   - All ids are UUID v4 (server-generated)
--   - All timestamps are TIMESTAMPTZ in UTC
--   - JSONB used for evolving payloads (preferences, attributes, traces)
--   - Row-level scoping is enforced by the application via user_id

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- for gen_random_uuid()

-- ----- users -----
CREATE TABLE IF NOT EXISTS users (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email             TEXT         UNIQUE NOT NULL,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    preferences_jsonb JSONB        NOT NULL DEFAULT '{}'::jsonb
);

-- ----- clothing_items -----
CREATE TABLE IF NOT EXISTS clothing_items (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name             TEXT         NOT NULL,
    category         TEXT         NOT NULL,                  -- e.g. top|bottom|footwear|outerwear|accessory
    attributes_jsonb JSONB        NOT NULL DEFAULT '{}'::jsonb, -- color, warmth, formality, fabric, etc.
    photo_url        TEXT,                                   -- gs:// URI in clothing-photos bucket
    qdrant_point_id  TEXT,                                   -- vector id in Qdrant for similarity search
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_clothing_items_user      ON clothing_items(user_id);
CREATE INDEX IF NOT EXISTS idx_clothing_items_category  ON clothing_items(user_id, category);
CREATE INDEX IF NOT EXISTS idx_clothing_items_attributes_gin ON clothing_items USING GIN (attributes_jsonb);

-- ----- recommendations -----
CREATE TABLE IF NOT EXISTS recommendations (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    request_jsonb  JSONB        NOT NULL,
    response_jsonb JSONB        NOT NULL,
    rating         SMALLINT,                              -- 1..5, nullable until rated
    trace_id       TEXT,                                  -- Langfuse trace id
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recommendations_user_created ON recommendations(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recommendations_trace        ON recommendations(trace_id);

-- ----- agent_sessions -----
CREATE TABLE IF NOT EXISTS agent_sessions (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status     TEXT         NOT NULL,        -- pending|running|completed|failed
    gcs_path   TEXT         NOT NULL,        -- gs://...agent-sessions/<id>/
    trace_id   TEXT,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_sessions_user_status ON agent_sessions(user_id, status);

-- ----- feedback_events -----
CREATE TABLE IF NOT EXISTS feedback_events (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    recommendation_id UUID         NOT NULL REFERENCES recommendations(id) ON DELETE CASCADE,
    event_type        TEXT         NOT NULL,        -- rating|comment|item_swap|reuse
    payload_jsonb     JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feedback_events_rec ON feedback_events(recommendation_id);

-- ----- updated_at trigger for agent_sessions -----
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_agent_sessions_updated ON agent_sessions;
CREATE TRIGGER trg_agent_sessions_updated
    BEFORE UPDATE ON agent_sessions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Migration tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT         PRIMARY KEY,
    applied_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
INSERT INTO schema_migrations (version) VALUES ('0001_init') ON CONFLICT DO NOTHING;

COMMIT;
