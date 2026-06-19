#!/usr/bin/env bash
set -euo pipefail

# Builds the CUSTOMER PWA (npm workspace @blackmango/customer) and publishes it to
# frontend-dist. Admin is a separate build — see deploy_admin.sh. A workspace install at the
# repo root wires @blackmango/shared for both apps.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
FRONTEND_ROOT="${FRONTEND_ROOT:-$APP_ROOT/frontend}"
FRONTEND_DIST="${FRONTEND_DIST:-$APP_ROOT/frontend-dist}"

if [[ ! -d "${FRONTEND_ROOT}" ]]; then
  echo "Frontend directory not found: ${FRONTEND_ROOT}"
  exit 1
fi

cd "${FRONTEND_ROOT}"
npm_ci_install                       # root workspace install (hoists deps, links shared)
npm run build                        # = build -w @blackmango/customer → apps/customer/dist

rm -rf "${FRONTEND_DIST}"
mkdir -p "${FRONTEND_DIST}"
cp -R apps/customer/dist/* "${FRONTEND_DIST}/"

echo "Customer PWA deploy complete: ${FRONTEND_DIST}"
