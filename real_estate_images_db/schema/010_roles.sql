-- Application roles
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_role') THEN
    CREATE ROLE app_role;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_readonly') THEN
    CREATE ROLE app_readonly;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_admin') THEN
    CREATE ROLE app_admin WITH SUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN;
  END IF;
END $$;

-- Create login role for application (bound to env APP_DB_USER)
-- The init script will ensure creation and password separately; this guards idempotence.
```
