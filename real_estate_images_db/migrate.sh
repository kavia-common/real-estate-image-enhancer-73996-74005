#!/bin/bash
set -euo pipefail

DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Applying schema and seed to ${DB_NAME} on port ${DB_PORT} ..."

if [ -f "schema.sql" ]; then
  sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -f schema.sql
  echo "✓ Schema applied"
else
  echo "schema.sql not found"
fi

if [ -f "seed.sql" ]; then
  sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -f seed.sql
  echo "✓ Seed applied"
else
  echo "seed.sql not found"
fi

echo "Done."
