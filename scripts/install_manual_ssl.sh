#!/usr/bin/env bash
# Use when certbot cannot reach Let's Encrypt (e.g. Iranian VPS network blocks).
# Expects cert files already placed by the operator — see DOMAIN_SETUP.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
BACKEND_ROOT="${BACKEND_ROOT:-$APP_ROOT/backend}"
FRONTEND_DIST="${FRONTEND_DIST:-$APP_ROOT/frontend-dist}"
DEPLOY_ROOT="${DEPLOY_ROOT:-$APP_ROOT/deploy}"
BACKEND_PORT="${BACKEND_PORT:-3000}"

DOMAIN="${DOMAIN:-masoudrazaghi.com}"
PUBLIC_BASE_URL="https://${DOMAIN}"

CERT_DIR="/etc/ssl/bbm/${DOMAIN}"
NGINX_SITE="/etc/nginx/sites-available/bbm-domain.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/bbm-domain.conf"

log() { printf '\n==> %s\n' "$*"; }

check_cert_files() {
  local missing=0
  for f in fullchain.pem privkey.pem; do
    if [[ ! -f "${CERT_DIR}/${f}" ]]; then
      echo "Missing: ${CERT_DIR}/${f}"
      missing=1
    fi
  done

  if [[ $missing -eq 1 ]]; then
    echo
    echo "Place the certificate files before running this script:"
    echo
    echo "  mkdir -p ${CERT_DIR}"
    echo "  # paste fullchain.pem (Certificate + full chain from Parspack):"
    echo "  cat > ${CERT_DIR}/fullchain.pem"
    echo "  # paste privkey.pem (Private Key from Parspack):"
    echo "  cat > ${CERT_DIR}/privkey.pem"
    echo "  chmod 600 ${CERT_DIR}/privkey.pem"
    echo
    exit 1
  fi

  log "Cert files found at ${CERT_DIR}"
}

secure_cert_permissions() {
  maybe_sudo chmod 600 "${CERT_DIR}/privkey.pem"
  maybe_sudo chmod 644 "${CERT_DIR}/fullchain.pem"
  maybe_sudo chown root:root "${CERT_DIR}/privkey.pem" "${CERT_DIR}/fullchain.pem"
}

render_nginx_https_config() {
  log "Rendering Nginx HTTPS config for ${DOMAIN}"
  sed \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__FRONTEND_DIST__|${FRONTEND_DIST}|g" \
    -e "s|__BACKEND_PORT__|${BACKEND_PORT}|g" \
    "${DEPLOY_ROOT}/nginx/bbm-domain-https.conf.template" \
    | maybe_sudo tee "${NGINX_SITE}" >/dev/null

  maybe_sudo ln -sf "${NGINX_SITE}" "${NGINX_ENABLED}"
  maybe_sudo rm -f /etc/nginx/sites-enabled/bbm-ip-http.conf
  maybe_sudo rm -f /etc/nginx/sites-enabled/default
  maybe_sudo nginx -t
  maybe_sudo systemctl reload nginx
}

update_backend_env_for_https() {
  local env_file="${BACKEND_ROOT}/.env"
  [[ -f "${env_file}" ]] || { echo "Missing ${env_file}"; exit 1; }

  log "Updating backend .env for HTTPS production"
  sed -i "s|^NODE_ENV=.*|NODE_ENV=production|"                              "${env_file}"
  sed -i "s|^COOKIE_SECURE=.*|COOKIE_SECURE=true|"                         "${env_file}"
  sed -i "s|^COOKIE_SAME_SITE=.*|COOKIE_SAME_SITE=lax|"                    "${env_file}"
  sed -i "s|^APP_URL=.*|APP_URL=${PUBLIC_BASE_URL}|"                        "${env_file}"
  sed -i "s|^CLIENT_APP_URL=.*|CLIENT_APP_URL=${PUBLIC_BASE_URL}|"          "${env_file}"
  sed -i "s|^CORS_ORIGINS=.*|CORS_ORIGINS=https://${DOMAIN},https://www.${DOMAIN}|" "${env_file}"
  sed -i "s|^ZARINPAL_CALLBACK_URL=.*|ZARINPAL_CALLBACK_URL=${PUBLIC_BASE_URL}/payment/callback|" "${env_file}"
  sed -i 's|^DAILY_NOTIFICATION_CRON=.*|DAILY_NOTIFICATION_CRON="0 7 * * *"|' "${env_file}"
}

restart_backend() {
  log "Restarting backend"
  pm2 restart bbm-backend --update-env --env production
  pm2 save
}

verify() {
  log "Verifying"
  sleep 2
  curl -fsSI "https://${DOMAIN}/"          | head -5
  curl -fsSI "https://${DOMAIN}/api/v1/health" | head -5
}

main() {
  log "Manual SSL install for ${DOMAIN}"
  check_cert_files
  secure_cert_permissions
  render_nginx_https_config
  update_backend_env_for_https
  restart_backend
  verify

  echo
  echo "Done. Site is live at https://${DOMAIN}"
  echo
  echo "IMPORTANT: These certs expire in ~90 days (check Parspack panel)."
  echo "Renew before expiry and re-run this script with the new certs."
}

main "$@"
