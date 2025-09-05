SET search_path = audit, public;

-- Chain-of-custody audit log with hash chaining
CREATE TABLE IF NOT EXISTS audit_log (
  audit_id BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_user_id UUID,             -- actor (nullable for system events)
  actor_role TEXT,
  action TEXT NOT NULL,           -- e.g., INSERT, UPDATE, DELETE, LOGIN, ACCESS
  table_name TEXT,
  record_id TEXT,                 -- primary key value(s) serialized
  changes JSONB,                  -- column-level diffs or payload
  ip_address INET,
  user_agent TEXT,
  prev_hash TEXT,
  curr_hash TEXT
);

CREATE INDEX IF NOT EXISTS idx_audit_occurred_at ON audit_log(occurred_at);

-- Data access logs (reads)
CREATE TABLE IF NOT EXISTS data_access_log (
  access_id BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_user_id UUID,
  actor_role TEXT,
  table_name TEXT NOT NULL,
  record_id TEXT,
  purpose TEXT,  -- legitimate interest / legal basis text for GDPR
  ip_address INET,
  user_agent TEXT
);

-- Helper function to compute hash for tamper-evident chain
CREATE OR REPLACE FUNCTION audit.compute_hash(payload TEXT)
RETURNS TEXT
LANGUAGE SQL
AS $$
  SELECT encode(digest(payload, 'sha256'), 'hex') FROM pgcrypto.digest(payload, 'sha256');
$$;

-- Insert function that maintains hash chain
CREATE OR REPLACE FUNCTION audit.append_log(
  p_actor_user_id UUID,
  p_actor_role TEXT,
  p_action TEXT,
  p_table_name TEXT,
  p_record_id TEXT,
  p_changes JSONB,
  p_ip INET,
  p_ua TEXT
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  last_hash TEXT;
  payload TEXT;
  new_hash TEXT;
BEGIN
  SELECT curr_hash INTO last_hash FROM audit.audit_log ORDER BY audit_id DESC LIMIT 1;
  payload := coalesce(last_hash,'') || '|' ||
             coalesce(p_actor_user_id::TEXT,'') || '|' ||
             coalesce(p_actor_role,'') || '|' ||
             coalesce(p_action,'') || '|' ||
             coalesce(p_table_name,'') || '|' ||
             coalesce(p_record_id,'') || '|' ||
             coalesce(p_changes::TEXT,'') || '|' ||
             now()::TEXT;
  SELECT encode(digest(payload, 'sha256'), 'hex') INTO new_hash FROM pgcrypto.digest(payload, 'sha256');

  INSERT INTO audit.audit_log (actor_user_id, actor_role, action, table_name, record_id, changes, ip_address, user_agent, prev_hash, curr_hash)
  VALUES (p_actor_user_id, p_actor_role, p_action, p_table_name, p_record_id, p_changes, p_ip, p_ua, last_hash, new_hash);
END
$$;

REVOKE ALL ON FUNCTION audit.append_log(UUID, TEXT, TEXT, TEXT, TEXT, JSONB, INET, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.append_log(UUID, TEXT, TEXT, TEXT, TEXT, JSONB, INET, TEXT) TO app_admin;
```
