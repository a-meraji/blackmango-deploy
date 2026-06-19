#!/usr/bin/env bash
set -euo pipefail

# Builds the ADMIN SPA (npm workspace @blackmango/admin) and publishes it to admin-dist.
# Admin is a plain web app (no service worker / PWA) served at the admin subdomain, which
# proxies its own /api + /uploads to the shared backend (same-origin → zero CORS).
# Deploys independently of the customer PWA — an admin change never bumps the customer SW.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
FRONTEND_ROOT="${FRONTEND_ROOT:-$APP_ROOT/frontend}"
ADMIN_DIST="${ADMIN_DIST:-$APP_ROOT/admin-dist}"

if [[ ! -d "${FRONTEND_ROOT}" ]]; then
  echo "Frontend directory not found: ${FRONTEND_ROOT}"
  exit 1
fi

cd "${FRONTEND_ROOT}"
npm_ci_install                       # root workspace install (hoists deps, links shared)
npm run build:admin                  # = build -w @blackmango/admin → apps/admin/dist

rm -rf "${ADMIN_DIST}"
mkdir -p "${ADMIN_DIST}"
cp -R apps/admin/dist/* "${ADMIN_DIST}/"

echo "Admin SPA deploy complete: ${ADMIN_DIST}"
