#!/usr/bin/env bash
set -euo pipefail

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
npm_ci_install
npm run build

rm -rf "${FRONTEND_DIST}"
mkdir -p "${FRONTEND_DIST}"
cp -R dist/* "${FRONTEND_DIST}/"

echo "Frontend deploy complete: ${FRONTEND_DIST}"
