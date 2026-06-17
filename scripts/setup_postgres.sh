#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-blackmango_db}"
DB_USER="${DB_USER:-blackmango_user}"
DB_PASS="${DB_PASS:-}"

if [[ -z "${DB_PASS}" ]]; then
  echo "Set DB_PASS before running. Example:"
  echo "DB_PASS='strong-pass' DB_NAME='blackmango_db' DB_USER='blackmango_user' ./deploy/scripts/setup_postgres.sh"
  exit 1
fi

sudo systemctl enable --now postgresql

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

echo "Testing connectivity..."
PGPASSWORD="${DB_PASS}" psql -h 127.0.0.1 -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT current_database(), current_user;"

echo "PostgreSQL setup complete."

