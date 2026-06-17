#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
BACKEND_ROOT="${BACKEND_ROOT:-$APP_ROOT/backend}"
PM2_CONFIG="${PM2_CONFIG:-$APP_ROOT/deploy/pm2/backend.ecosystem.config.cjs}"
APP_ENV="${APP_ENV:-staging}"

if [[ ! -d "${BACKEND_ROOT}" ]]; then
  echo "Backend directory not found: ${BACKEND_ROOT}"
  exit 1
fi

if [[ ! -f "${BACKEND_ROOT}/.env" ]]; then
  echo "Missing ${BACKEND_ROOT}/.env"
  exit 1
fi

mkdir -p "${BACKEND_ROOT}/uploads"

cd "${BACKEND_ROOT}"
npm ci
npm run build

if pm2 describe bbm-backend >/dev/null 2>&1; then
  pm2 restart bbm-backend --update-env
else
  pm2 start "${PM2_CONFIG}" --env "${APP_ENV}"
fi

pm2 save
pm2 status
pm2 logs bbm-backend --lines 50 --nostream

echo "Backend deploy complete."
