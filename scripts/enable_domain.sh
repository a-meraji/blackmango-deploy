#!/usr/bin/env bash
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
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://${DOMAIN}}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@${DOMAIN}}"
NGINX_SITE="/etc/nginx/sites-available/bbm-domain.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/bbm-domain.conf"

log() {
  printf '\n==> %s\n' "$*"
}

update_backend_env_for_https() {
  local env_file="${BACKEND_ROOT}/.env"

  if [[ ! -f "${env_file}" ]]; then
    echo "Missing ${env_file}"
    exit 1
  fi

  log "Updating backend .env for HTTPS production"

  sed -i "s|^NODE_ENV=.*|NODE_ENV=production|" "${env_file}"
  sed -i "s|^COOKIE_SECURE=.*|COOKIE_SECURE=true|" "${env_file}"
  sed -i "s|^COOKIE_SAME_SITE=.*|COOKIE_SAME_SITE=lax|" "${env_file}"
  sed -i "s|^APP_URL=.*|APP_URL=${PUBLIC_BASE_URL}|" "${env_file}"
  sed -i "s|^CLIENT_APP_URL=.*|CLIENT_APP_URL=${PUBLIC_BASE_URL}|" "${env_file}"
  sed -i "s|^CORS_ORIGINS=.*|CORS_ORIGINS=https://${DOMAIN},https://www.${DOMAIN}|" "${env_file}"
  sed -i "s|^ZARINPAL_CALLBACK_URL=.*|ZARINPAL_CALLBACK_URL=${PUBLIC_BASE_URL}/payment/callback|" "${env_file}"
  sed -i 's|^DAILY_NOTIFICATION_CRON=.*|DAILY_NOTIFICATION_CRON="0 7 * * *"|' "${env_file}"
}

render_nginx_domain_config() {
  log "Rendering Nginx config for ${DOMAIN}"
  sed \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__FRONTEND_DIST__|${FRONTEND_DIST}|g" \
    -e "s|__BACKEND_PORT__|${BACKEND_PORT}|g" \
    "${DEPLOY_ROOT}/nginx/bbm-domain-http.conf.template" \
    | maybe_sudo tee "${NGINX_SITE}" >/dev/null

  maybe_sudo ln -sf "${NGINX_SITE}" "${NGINX_ENABLED}"
  maybe_sudo rm -f /etc/nginx/sites-enabled/bbm-ip-http.conf
  maybe_sudo rm -f /etc/nginx/sites-enabled/default
  maybe_sudo nginx -t
  maybe_sudo systemctl reload nginx
}

install_certbot_if_needed() {
  if command -v certbot >/dev/null 2>&1; then
    return
  fi

  log "Installing Certbot"
  maybe_sudo apt update
  maybe_sudo apt install -y certbot python3-certbot-nginx
}

issue_ssl_certificate() {
  log "Issuing Let's Encrypt certificate"
  maybe_sudo certbot --nginx \
    -d "${DOMAIN}" \
    -d "www.${DOMAIN}" \
    --non-interactive \
    --agree-tos \
    -m "${CERTBOT_EMAIL}" \
    --redirect
}

restart_backend_production() {
  log "Restarting backend in production mode"
  pm2 restart bbm-backend --update-env --env production
  pm2 save
}

verify_domain() {
  log "Verifying domain"
  curl -fsSI "https://${DOMAIN}/" | sed -n '1,5p'
  curl -fsSI "https://${DOMAIN}/api/v1/health" | sed -n '1,5p'
}

main() {
  log "Domain setup for ${DOMAIN}"

  if ! getent hosts "${DOMAIN}" >/dev/null; then
    echo "DNS for ${DOMAIN} is not resolving yet."
    echo "Create these DNS records first, wait 5-30 minutes, then rerun:"
    echo "  A   @    -> your server IP"
    echo "  A   www  -> your server IP"
    exit 1
  fi

  render_nginx_domain_config
  update_backend_env_for_https
  install_certbot_if_needed
  issue_ssl_certificate
  restart_backend_production
  verify_domain

  echo
  echo "Domain setup complete:"
  echo "  https://${DOMAIN}"
  echo "  https://www.${DOMAIN}"
}

main "$@"
