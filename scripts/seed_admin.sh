#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
BACKEND_ROOT="${BACKEND_ROOT:-$APP_ROOT/backend}"

if [[ ! -f "${BACKEND_ROOT}/.env" ]]; then
  echo "Missing ${BACKEND_ROOT}/.env"
  exit 1
fi

cd "${BACKEND_ROOT}"
set -a
# shellcheck disable=SC1090
source .env
set +a

if [[ -z "${ADMIN_MOBILE:-}" ]]; then
  echo "ADMIN_MOBILE is not set in backend/.env"
  exit 1
fi

npx ts-node --transpile-only prisma/seed-admin.ts
echo "Admin seed complete for ${ADMIN_MOBILE}"
