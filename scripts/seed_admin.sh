#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
BACKEND_ROOT="${BACKEND_ROOT:-$APP_ROOT/backend}"
ENV_FILE="${BACKEND_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}"
  exit 1
fi

load_backend_seed_env "${ENV_FILE}"

if [[ -z "${ADMIN_MOBILE:-}" ]]; then
  echo "ADMIN_MOBILE is not set in backend/.env"
  exit 1
fi

cd "${BACKEND_ROOT}"
npx ts-node --transpile-only prisma/seed-admin.ts
echo "Admin seed complete for ${ADMIN_MOBILE}"
