#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://185.7.212.18}"
DOMAIN="${DOMAIN:-masoudrazaghi.com}"

echo "Checking Nginx homepage..."
curl -fsS -I "${PUBLIC_BASE_URL}/" | sed -n '1,5p'

echo "Checking API through Nginx..."
curl -fsS -I "${PUBLIC_BASE_URL}/api/v1/health" | sed -n '1,5p' || true

echo "Checking uploads path through Nginx..."
curl -fsS -I "${PUBLIC_BASE_URL}/uploads/" | sed -n '1,5p' || true

# ── Admin/customer host routing (the "admin shows the home page" check) ───────
# Fetch each host through the local nginx and assert it serves the RIGHT app. The admin
# index.html title contains 'مدیریت'; the customer one does not.
fetch_index() {
  local host="$1"
  curl -fsSk --resolve "${host}:443:127.0.0.1" "https://${host}/" 2>/dev/null ||
    curl -fsS --resolve "${host}:80:127.0.0.1" "http://${host}/" 2>/dev/null
}

echo "Checking admin.${DOMAIN} serves the ADMIN app (not the home page)..."
if [[ -e /etc/nginx/sites-enabled/bbm-admin.conf ]]; then
  if fetch_index "admin.${DOMAIN}" | grep -q 'مدیریت'; then
    echo "  OK: admin.${DOMAIN} -> admin app"
  else
    echo "  FAIL: admin.${DOMAIN} is serving the customer home page (admin block not matching host)."
  fi
else
  echo "  SKIP: admin nginx block not enabled — run install_admin_ssl.sh (DOMAIN_SETUP.md Step 5)."
fi

echo "PM2 status:"
pm2 status

echo "Nginx status:"
maybe_sudo systemctl status nginx --no-pager | sed -n '1,15p'

echo "Verify complete."
