SET search_path = config, public;

CREATE TABLE IF NOT EXISTS feature_flags (
  key TEXT PRIMARY KEY,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS kv_store (
  k TEXT PRIMARY KEY,
  v JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed default flags
INSERT INTO feature_flags (key, enabled, description)
VALUES
  ('enable_free_trial', TRUE, 'Enable 10 free images for new users'),
  ('enable_audit_reads', TRUE, 'Enable read access logging')
ON CONFLICT (key) DO NOTHING;
```
