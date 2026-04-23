-- Data model for remote Neuron management control plane

CREATE TABLE IF NOT EXISTS gateway_registry (
  gateway_id           VARCHAR(128) PRIMARY KEY,
  site_code            VARCHAR(64) NOT NULL,
  display_name         VARCHAR(255) NOT NULL,
  cert_fingerprint     VARCHAR(128) NOT NULL,
  cert_not_after       TIMESTAMPTZ NOT NULL,
  policy_version       VARCHAR(64) NOT NULL,
  agent_version        VARCHAR(64),
  status               VARCHAR(32) NOT NULL DEFAULT 'offline',
  last_seen_at         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS remote_jobs (
  job_id               UUID PRIMARY KEY,
  command_id           VARCHAR(128) NOT NULL UNIQUE,
  idempotency_key      VARCHAR(256) NOT NULL,
  gateway_id           VARCHAR(128) NOT NULL REFERENCES gateway_registry(gateway_id),
  operation            VARCHAR(64) NOT NULL,
  request_payload      JSONB NOT NULL,
  status               VARCHAR(32) NOT NULL,
  attempt_count        INTEGER NOT NULL DEFAULT 0,
  max_attempts         INTEGER NOT NULL DEFAULT 3,
  timeout_ms           INTEGER NOT NULL,
  scheduled_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at           TIMESTAMPTZ,
  completed_at         TIMESTAMPTZ,
  created_by           VARCHAR(256) NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (gateway_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_remote_jobs_gateway_status
  ON remote_jobs(gateway_id, status, scheduled_at);

CREATE TABLE IF NOT EXISTS job_events (
  event_id             BIGSERIAL PRIMARY KEY,
  job_id               UUID NOT NULL REFERENCES remote_jobs(job_id) ON DELETE CASCADE,
  command_id           VARCHAR(128) NOT NULL,
  gateway_id           VARCHAR(128) NOT NULL,
  event_type           VARCHAR(64) NOT NULL,
  event_payload        JSONB,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_job_events_job_created
  ON job_events(job_id, created_at);

CREATE TABLE IF NOT EXISTS config_snapshot (
  snapshot_id          BIGSERIAL PRIMARY KEY,
  gateway_id           VARCHAR(128) NOT NULL REFERENCES gateway_registry(gateway_id),
  collected_at         TIMESTAMPTZ NOT NULL,
  source               VARCHAR(32) NOT NULL DEFAULT 'remote_read',
  neuron_version       VARCHAR(64),
  nodes                JSONB NOT NULL,
  groups               JSONB NOT NULL,
  tags                 JSONB NOT NULL,
  subscribes           JSONB NOT NULL,
  checksum_sha256      VARCHAR(64) NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_config_snapshot_gateway_collected
  ON config_snapshot(gateway_id, collected_at DESC);

-- Optional materialized view for latest snapshot per gateway
CREATE MATERIALIZED VIEW IF NOT EXISTS latest_config_snapshot AS
SELECT DISTINCT ON (gateway_id)
  gateway_id,
  snapshot_id,
  collected_at,
  neuron_version,
  checksum_sha256
FROM config_snapshot
ORDER BY gateway_id, collected_at DESC;
