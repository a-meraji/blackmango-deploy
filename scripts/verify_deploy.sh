#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://185.7.212.18}"

echo "Checking Nginx homepage..."
curl -fsS -I "${PUBLIC_BASE_URL}/" | sed -n '1,5p'

echo "Checking API through Nginx..."
curl -fsS -I "${PUBLIC_BASE_URL}/api/v1/health" | sed -n '1,5p' || true

echo "Checking uploads path through Nginx..."
curl -fsS -I "${PUBLIC_BASE_URL}/uploads/" | sed -n '1,5p' || true

echo "PM2 status:"
pm2 status

echo "Nginx status:"
maybe_sudo systemctl status nginx --no-pager | sed -n '1,15p'

echo "Verify complete."
