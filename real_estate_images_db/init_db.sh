#!/usr/bin/env bash
set -euo pipefail

# Loads environment variables from .env if present
if [ -f ".env" ]; then
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
fi

DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5000}
DB_NAME=${DB_NAME:-myapp}
DB_SUPERUSER=${DB_SUPERUSER:-postgres}
DB_SUPERUSER_PASSWORD=${DB_SUPERUSER_PASSWORD:-}
APP_DB_USER=${APP_DB_USER:-appuser}
APP_DB_PASSWORD=${APP_DB_PASSWORD:-dbuser123}

echo "Initializing database at ${DB_HOST}:${DB_PORT}/${DB_NAME} ..."

PGPASSFILE_CREATED=0
if [ -n "${DB_SUPERUSER_PASSWORD}" ]; then
  export PGPASSWORD="${DB_SUPERUSER_PASSWORD}"
fi

PSQL_BASE=(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_SUPERUSER}" -v ON_ERROR_STOP=1)

# 1) Create DB if not exists
echo "Ensuring database exists..."
"${PSQL_BASE[@]}" -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  "${PSQL_BASE[@]}" -d postgres -c "CREATE DATABASE ${DB_NAME};"

# 2) Create app login role if not exists and base roles
echo "Ensuring roles..."
"${PSQL_BASE[@]}" -d "${DB_NAME}" <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_role') THEN
    CREATE ROLE app_role;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_readonly') THEN
    CREATE ROLE app_readonly;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_DB_USER}') THEN
    CREATE ROLE ${APP_DB_USER} WITH LOGIN PASSWORD '${APP_DB_PASSWORD}';
  ELSE
    ALTER ROLE ${APP_DB_USER} WITH LOGIN PASSWORD '${APP_DB_PASSWORD}';
  END IF;
END
\$\$;

GRANT app_role TO ${APP_DB_USER};
SQL

# 3) Run schema files in order
run_sql() {
  local file="$1"
  echo "Applying ${file} ..."
  "${PSQL_BASE[@]}" -d "${DB_NAME}" -f "${file}"
}

SCHEMA_DIR="schema"
FILES=(
  "001_extensions.sql"
  "010_roles.sql"
  "020_schemas.sql"
  "030_crypto.sql"
  "040_core.sql"
  "050_billing.sql"
  "060_audit.sql"
  "070_config.sql"
  "080_rbac_grants.sql"
  "090_triggers.sql"
  "100_indexes.sql"
)

for f in "${FILES[@]}"; do
  run_sql "${SCHEMA_DIR}/${f}"
done

# 4) Grant DB access
echo "Granting database-level privileges..."
"${PSQL_BASE[@]}" -d "${DB_NAME}" <<SQL
GRANT CONNECT ON DATABASE ${DB_NAME} TO app_role, app_readonly;
GRANT TEMP ON DATABASE ${DB_NAME} TO app_role;
SQL

# 5) Output connection hint
CONN_STR="postgresql://${APP_DB_USER}:${APP_DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "${CONN_STR}" > db_connection.txt
echo "Connection string saved to db_connection.txt"
echo "Initialization completed successfully."
```
