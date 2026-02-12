#!/bin/bash
set -euo pipefail

# Applies versioned SQL migrations (idempotent) and records them in schema_migrations.
# Expects db_connection.txt to contain a psql command like:
#   psql postgresql://user:pass@host:port/dbname

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS_DIR="${ROOT_DIR}/migrations"
MIGRATIONS_PATH="${MIGRATIONS_DIR}/sql"
SEEDS_PATH="${MIGRATIONS_DIR}/seeds"
CONN_FILE="${ROOT_DIR}/db_connection.txt"

if [ ! -f "${CONN_FILE}" ]; then
  echo "✗ Missing ${CONN_FILE}. Cannot apply migrations."
  exit 1
fi

PSQL_BASE_CMD="$(cat "${CONN_FILE}")"
if [[ "${PSQL_BASE_CMD}" != psql* ]]; then
  echo "✗ db_connection.txt does not start with 'psql ...' (got: ${PSQL_BASE_CMD})"
  exit 1
fi

# Use ON_ERROR_STOP so any SQL error fails fast.
PSQL_CMD="${PSQL_BASE_CMD} -v ON_ERROR_STOP=1"

echo "Running migrations using: ${PSQL_BASE_CMD}"

# Ensure migrations ledger exists
${PSQL_CMD} -c "CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());"

apply_sql_file_once () {
  local version="$1"
  local sql_file="$2"

  # Skip if already applied
  if ${PSQL_CMD} -tAc "SELECT 1 FROM schema_migrations WHERE version='${version}'" | grep -q 1; then
    echo "✓ Migration already applied: ${version}"
    return 0
  fi

  echo "Applying migration: ${version}"
  ${PSQL_CMD} -f "${sql_file}"
  ${PSQL_CMD} -c "INSERT INTO schema_migrations(version) VALUES ('${version}');"
  echo "✓ Applied migration: ${version}"
}

if [ -d "${MIGRATIONS_PATH}" ]; then
  shopt -s nullglob
  for f in "${MIGRATIONS_PATH}"/*.sql; do
    base="$(basename "$f")"
    version="${base%.sql}"
    apply_sql_file_once "${version}" "${f}"
  done
else
  echo "ℹ No migrations directory found at ${MIGRATIONS_PATH}; skipping migrations."
fi

# Seeds are intended to be idempotent SQL (INSERT ... ON CONFLICT ... / WHERE NOT EXISTS)
if [ -d "${SEEDS_PATH}" ]; then
  shopt -s nullglob
  for f in "${SEEDS_PATH}"/*.sql; do
    echo "Applying seed: $(basename "$f")"
    ${PSQL_CMD} -f "${f}"
    echo "✓ Applied seed: $(basename "$f")"
  done
else
  echo "ℹ No seeds directory found at ${SEEDS_PATH}; skipping seeds."
fi

echo "Migrations + seeds complete."
