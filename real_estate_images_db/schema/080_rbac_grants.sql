-- Revoke broad defaults
REVOKE ALL ON DATABASE CURRENT_DATABASE() FROM PUBLIC;

-- Usage on schemas
GRANT USAGE ON SCHEMAS core, billing, config TO app_role, app_readonly;
GRANT USAGE ON SCHEMA audit TO app_admin;
GRANT USAGE ON SCHEMA crypto TO app_role, app_admin;

-- Table privileges
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core TO app_role;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO app_readonly;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA billing TO app_role;
GRANT SELECT ON ALL TABLES IN SCHEMA billing TO app_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA config TO app_role, app_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA audit TO app_admin;
REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM app_role, app_readonly;

-- Sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA core, billing TO app_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA core, billing TO app_readonly;

-- Future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT ON TABLES TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA billing GRANT SELECT ON TABLES TO app_readonly;

-- Note: EXECUTE on crypto.decrypt_text is only for app_admin (granted in 030_crypto.sql)
```
