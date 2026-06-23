#!/usr/bin/env bash
# First-time HTTPS setup for the admin SPA at admin.<domain>.
#
# Prereqs (operator actions — see DOMAIN_SETUP.md / the deploy runbook):
#   1. DNS: an A record  admin.<domain> -> <server IP>  exists and has propagated.
#   2. admin-dist is built and published (run deploy/scripts/deploy_admin.sh first).
#   3. A TLS cert valid for admin.<domain> is placed on disk:
#        - default: reuse the apex cert at /etc/ssl/bbm/<domain>/ whose SAN list now
#          includes admin.<domain>  (CERT_DIR defaults here), OR
#        - a standalone admin cert: set CERT_DIR=/etc/ssl/bbm/admin.<domain> and place
#          fullchain.pem + privkey.pem there.
#
# This script does NOT touch backend/.env: admin self-proxies its own /api + /uploads to the
# shared backend, so every admin call is same-origin → no CORS, no CORS_ORIGINS change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
ADMIN_DIST="${ADMIN_DIST:-$APP_ROOT/admin-dist}"
DEPLOY_ROOT="${DEPLOY_ROOT:-$APP_ROOT/deploy}"
BACKEND_PORT="${BACKEND_PORT:-3000}"

DOMAIN="${DOMAIN:-masoudrazaghi.com}"
ADMIN_HOST="admin.${DOMAIN}"
CERT_DIR="${CERT_DIR:-/etc/ssl/bbm/${DOMAIN}}"

NGINX_SITE="/etc/nginx/sites-available/bbm-admin.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/bbm-admin.conf"

log() { printf '\n==> %s\n' "$*"; }

check_admin_dist() {
  if [[ ! -f "${ADMIN_DIST}/index.html" ]]; then
    echo "Admin build not found at ${ADMIN_DIST}/index.html"
    echo "Run deploy/scripts/deploy_admin.sh first."
    exit 1
  fi
  log "Admin build found at ${ADMIN_DIST}"
}

check_cert_files() {
  local missing=0
  for f in fullchain.pem privkey.pem; do
    [[ -f "${CERT_DIR}/${f}" ]] || { echo "Missing: ${CERT_DIR}/${f}"; missing=1; }
  done
  if [[ $missing -eq 1 ]]; then
    echo
    echo "Place a cert valid for ${ADMIN_HOST} before running this script."
    echo "Default CERT_DIR is the apex cert (${CERT_DIR}); it must list ${ADMIN_HOST} as a SAN."
    echo "To use a standalone admin cert instead:"
    echo "  mkdir -p /etc/ssl/bbm/${ADMIN_HOST}"
    echo "  cat > /etc/ssl/bbm/${ADMIN_HOST}/fullchain.pem   # paste, Ctrl+D"
    echo "  cat > /etc/ssl/bbm/${ADMIN_HOST}/privkey.pem     # paste, Ctrl+D"
    echo "  chmod 600 /etc/ssl/bbm/${ADMIN_HOST}/privkey.pem"
    echo "  CERT_DIR=/etc/ssl/bbm/${ADMIN_HOST} ./deploy/scripts/install_admin_ssl.sh"
    exit 1
  fi
  log "Cert files found at ${CERT_DIR}"
  # Warn (don't fail) if the cert does not cover the admin host.
  if ! openssl x509 -noout -text -in "${CERT_DIR}/fullchain.pem" 2>/dev/null | grep -q "${ADMIN_HOST}"; then
    echo "WARNING: ${CERT_DIR}/fullchain.pem does not appear to list ${ADMIN_HOST}."
    echo "         Browsers will reject it. Use a cert whose SAN includes ${ADMIN_HOST}."
  fi
}

render_nginx_https_config() {
  log "Rendering Nginx HTTPS config for ${ADMIN_HOST}"
  sed \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__ADMIN_DIST__|${ADMIN_DIST}|g" \
    -e "s|__CERT_DIR__|${CERT_DIR}|g" \
    -e "s|__BACKEND_PORT__|${BACKEND_PORT}|g" \
    "${DEPLOY_ROOT}/nginx/bbm-admin-https.conf.template" \
    | maybe_sudo tee "${NGINX_SITE}" >/dev/null

  maybe_sudo ln -sf "${NGINX_SITE}" "${NGINX_ENABLED}"
  maybe_sudo nginx -t
  maybe_sudo systemctl reload nginx
}

verify() {
  log "Verifying"
  sleep 2
  curl -fsSI "https://${ADMIN_HOST}/" | head -5 || {
    echo "Could not reach https://${ADMIN_HOST}/ yet — check DNS propagation and cert SAN."
  }
}

main() {
  log "Admin HTTPS install for ${ADMIN_HOST}"
  check_admin_dist
  check_cert_files
  render_nginx_https_config
  verify
  echo
  echo "Done. Admin panel live at https://${ADMIN_HOST}"
  echo "Reminder: if you reused the apex cert, renewing it (every ~90 days) covers admin too."
}

main "$@"
