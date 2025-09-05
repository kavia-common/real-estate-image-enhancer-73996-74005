-- Shared update timestamp function
CREATE OR REPLACE FUNCTION core.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END
$$;

-- Attach to tables with updated_at column
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT table_schema, table_name
    FROM information_schema.columns
    WHERE column_name = 'updated_at'
      AND table_schema IN ('core','billing')
  LOOP
    EXECUTE format('
      DO $b$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = %L
        ) THEN
          CREATE TRIGGER %I
          BEFORE UPDATE ON %I.%I
          FOR EACH ROW
          EXECUTE PROCEDURE core.set_updated_at();
        END IF;
      END
      $b$;
    ', 'trg_set_updated_at_'||r.table_name, 'trg_set_updated_at_'||r.table_name, r.table_schema, r.table_name);
  END LOOP;
END
$$;

-- Soft delete helper: set deleted_at instead of physical delete. Backend should use UPDATE to mark delete.
-- Optionally implement RLS and policies if multi-tenant isolation is needed at DB level.

-- Optional read access logging (when enabled by config.feature_flags.enable_audit_reads)
CREATE OR REPLACE FUNCTION audit.log_read(table_name TEXT, record_id TEXT, actor_user_id UUID, actor_role TEXT, ip INET, ua TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  enabled BOOLEAN;
BEGIN
  SELECT enabled INTO enabled FROM config.feature_flags WHERE key = 'enable_audit_reads';
  IF coalesce(enabled, false) THEN
    INSERT INTO audit.data_access_log (actor_user_id, actor_role, table_name, record_id, ip_address, user_agent)
    VALUES (actor_user_id, actor_role, table_name, record_id, ip, ua);
  END IF;
END
$$;

REVOKE ALL ON FUNCTION audit.log_read(TEXT, TEXT, UUID, TEXT, INET, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.log_read(TEXT, TEXT, UUID, TEXT, INET, TEXT) TO app_role, app_admin;
```
