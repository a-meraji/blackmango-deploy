#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/big_black_mango}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-blackmango_db}"
DB_USER="${DB_USER:-blackmango_user}"
DB_PASS="${DB_PASS:-}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

if [[ -z "${DB_PASS}" ]]; then
  echo "Set DB_PASS environment variable before running."
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

TS="$(date +%F_%H%M%S)"
FILE="${BACKUP_DIR}/${DB_NAME}_${TS}.sql.gz"

export PGPASSWORD="${DB_PASS}"
pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" | gzip > "${FILE}"
unset PGPASSWORD

find "${BACKUP_DIR}" -type f -name "${DB_NAME}_*.sql.gz" -mtime +"${RETENTION_DAYS}" -delete

echo "Backup created: ${FILE}"

