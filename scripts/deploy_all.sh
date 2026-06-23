#!/usr/bin/env bash
set -euo pipefail

# ─── One-shot routine deploy ──────────────────────────────────────────────────
# Rebuilds + publishes BOTH front-ends (customer PWA → frontend-dist, admin SPA → admin-dist),
# reloads nginx, and then VERIFIES that each host serves the RIGHT app:
#   <domain>        → customer PWA
#   admin.<domain>  → admin SPA   (NOT the customer home page)
#
# Run this for every routine deploy after the one-time setup (DNS + TLS + nginx) is done —
# see DOMAIN_SETUP.md Steps 1-5. The verify step fails loudly if admin.<domain> is being
# served the customer home page (i.e. the admin nginx block isn't active).
#
#   DOMAIN=masoudrazaghi.com ./deploy/scripts/deploy_all.sh
#
# Env / flags:
#   DOMAIN=...            domain to deploy + verify         (default: masoudrazaghi.com)
#   SKIP_CUSTOMER=1       don't rebuild the customer PWA
#   SKIP_ADMIN=1          don't rebuild the admin SPA
#   REDEPLOY_BACKEND=1    also rebuild + restart the backend
#   SCHEME=http|https     scheme to verify with            (default: auto-detect from nginx)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
DOMAIN="${DOMAIN:-masoudrazaghi.com}"
ADMIN_HOST="admin.${DOMAIN}"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

build_frontends() {
  if [[ "${SKIP_CUSTOMER:-0}" != "1" ]]; then
    log "Building customer PWA → frontend-dist"
    "${SCRIPT_DIR}/deploy_frontend.sh"
  else
    log "Skipping customer build (SKIP_CUSTOMER=1)"
  fi

  if [[ "${SKIP_ADMIN:-0}" != "1" ]]; then
    log "Building admin SPA → admin-dist"
    "${SCRIPT_DIR}/deploy_admin.sh"
  else
    log "Skipping admin build (SKIP_ADMIN=1)"
  fi

  if [[ "${REDEPLOY_BACKEND:-0}" == "1" ]]; then
    log "Rebuilding backend"
    "${SCRIPT_DIR}/deploy_backend.sh"
  fi
}

check_admin_block_enabled() {
  # The #1 cause of "admin.<domain> shows the home page": the admin nginx server block is not
  # active, so the host falls through to the apex/customer block. Catch it before reloading.
  if [[ ! -e /etc/nginx/sites-enabled/bbm-admin.conf ]]; then
    fail "admin nginx block is NOT enabled (/etc/nginx/sites-enabled/bbm-admin.conf missing).
       admin.${DOMAIN} will fall through to the customer block and serve the home page.
       Run the one-time admin setup first:
         DOMAIN=${DOMAIN} ./deploy/scripts/install_admin_ssl.sh
       (See DOMAIN_SETUP.md Step 5.)"
  fi
  log "admin nginx block is enabled"
}

reload_nginx() {
  log "Reloading nginx"
  maybe_sudo nginx -t
  maybe_sudo systemctl reload nginx
}

# Fetch a host's served index.html through the LOCAL nginx (bypasses external DNS), trying
# https first then http. Uses --resolve so SNI/Host both target this server.
fetch_index() {
  local host="$1"
  local body
  if body="$(curl -fsSk --resolve "${host}:443:127.0.0.1" "https://${host}/" 2>/dev/null)"; then
    printf '%s' "${body}"; return 0
  fi
  if body="$(curl -fsS --resolve "${host}:80:127.0.0.1" "http://${host}/" 2>/dev/null)"; then
    printf '%s' "${body}"; return 0
  fi
  return 1
}

verify_routing() {
  log "Verifying each host serves the right app"

  local apex_html admin_html
  apex_html="$(fetch_index "${DOMAIN}")"   || fail "could not fetch https/http://${DOMAIN}/"
  admin_html="$(fetch_index "${ADMIN_HOST}")" || fail "could not fetch https/http://${ADMIN_HOST}/ — is the admin block + DNS up?"

  # The admin index.html title is "پنل مدیریت بلک منگو" (contains 'مدیریت'); the customer one
  # is just "بلک منگو". This is the precise discriminator for the reported bug.
  if ! grep -q 'مدیریت' <<<"${admin_html}"; then
    fail "${ADMIN_HOST} is NOT serving the admin app — it returned the customer page.
       The admin nginx block isn't matching this host (it's falling through to the apex
       block). Check: ls -l /etc/nginx/sites-enabled/ ; sudo nginx -T | grep -n 'server_name'"
  fi
  log "OK: ${ADMIN_HOST} serves the ADMIN app"

  if grep -q 'مدیریت' <<<"${apex_html}"; then
    fail "${DOMAIN} is unexpectedly serving the ADMIN app — check server_name ordering."
  fi
  log "OK: ${DOMAIN} serves the CUSTOMER app"
}

main() {
  log "Deploying both front-ends for ${DOMAIN}"
  build_frontends
  check_admin_block_enabled
  reload_nginx
  verify_routing

  echo
  echo "Deploy complete and verified:"
  echo "  customer : https://${DOMAIN}"
  echo "  admin    : https://${ADMIN_HOST}"
}

main "$@"
