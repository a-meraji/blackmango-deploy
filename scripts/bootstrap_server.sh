#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

SOURCE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Defaults: use current project folder (e.g. /var/www/blackmango)
export APP_ROOT="${APP_ROOT:-${SOURCE_ROOT}}"
export BACKEND_ROOT="${BACKEND_ROOT:-$APP_ROOT/backend}"
export FRONTEND_ROOT="${FRONTEND_ROOT:-$APP_ROOT/frontend}"
export FRONTEND_DIST="${FRONTEND_DIST:-$APP_ROOT/frontend-dist}"
export DEPLOY_ROOT="${DEPLOY_ROOT:-$APP_ROOT/deploy}"
export PUBLIC_IP="${PUBLIC_IP:-185.7.212.18}"
export PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://$PUBLIC_IP}"
export BACKEND_PORT="${BACKEND_PORT:-3000}"
export DB_NAME="${DB_NAME:-blackmango_db}"
export DB_USER="${DB_USER:-blackmango_user}"
export APP_ENV="${APP_ENV:-staging}"
export BACKUP_DIR="${BACKUP_DIR:-/var/backups/blackmango}"
export ADMIN_MOBILE="${ADMIN_MOBILE:-09033018426}"
export ADMIN_FIRST_NAME="${ADMIN_FIRST_NAME:-مدیر}"
export ADMIN_LAST_NAME="${ADMIN_LAST_NAME:-رستوران}"

SECRETS_FILE="${DEPLOY_ROOT}/.generated.env"
PM2_CONFIG="${DEPLOY_ROOT}/pm2/backend.ecosystem.config.cjs"
NGINX_AVAILABLE="/etc/nginx/sites-available/bbm-ip-http.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/bbm-ip-http.conf"

log() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

random_hex() {
  openssl rand -hex 32
}

sync_project_to_app_root() {
  if [[ "${SOURCE_ROOT}" == "${APP_ROOT}" ]]; then
    log "Using project at ${APP_ROOT}"
    return
  fi

  log "Syncing project to ${APP_ROOT}"
  maybe_sudo mkdir -p "${APP_ROOT}"
  maybe_sudo rsync -a \
    --delete \
    --exclude node_modules \
    --exclude backend/uploads \
    --exclude frontend/dist \
    --exclude deploy/.generated.env \
    "${SOURCE_ROOT}/" "${APP_ROOT}/"
  maybe_sudo chown -R "${USER}:${USER}" "${APP_ROOT}"
}

load_or_create_secrets() {
  if [[ -f "${SECRETS_FILE}" ]]; then
    log "Loading existing secrets from ${SECRETS_FILE}"
    # shellcheck disable=SC1090
    source "${SECRETS_FILE}"
    return
  fi

  log "Generating secrets"
  DB_PASS="$(random_hex)"
  JWT_ACCESS_SECRET="$(random_hex)"
  JWT_REFRESH_SECRET="$(random_hex)"

  mkdir -p "${DEPLOY_ROOT}"
  cat >"${SECRETS_FILE}" <<EOF
DB_PASS=${DB_PASS}
JWT_ACCESS_SECRET=${JWT_ACCESS_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
EOF
  chmod 600 "${SECRETS_FILE}"

  # shellcheck disable=SC1090
  source "${SECRETS_FILE}"
}

generate_vapid_keys() {
  if [[ -n "${VAPID_PUBLIC_KEY:-}" && -n "${VAPID_PRIVATE_KEY:-}" ]]; then
    log "VAPID keys already present, skipping"
    return
  fi

  log "Generating VAPID keys"
  require_command node
  cd "${BACKEND_ROOT}"
  if [[ ! -d node_modules/web-push ]]; then
    npm_ci_install >/dev/null
  fi

  local vapid_json
  vapid_json="$(node -e "const w=require('web-push');console.log(JSON.stringify(w.generateVAPIDKeys()))")"
  VAPID_PUBLIC_KEY="$(node -e "const k=${vapid_json};console.log(k.publicKey)")"
  VAPID_PRIVATE_KEY="$(node -e "const k=${vapid_json};console.log(k.privateKey)")"

  cat >>"${SECRETS_FILE}" <<EOF
VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
EOF
  chmod 600 "${SECRETS_FILE}"
}

write_backend_env() {
  log "Writing backend .env"
  cat >"${BACKEND_ROOT}/.env" <<EOF
DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@127.0.0.1:5432/${DB_NAME}
NODE_ENV=staging
PORT=${BACKEND_PORT}
API_PREFIX=/api/v1
APP_URL=${PUBLIC_BASE_URL}
ENABLE_SWAGGER=false
CORS_ORIGINS=${PUBLIC_BASE_URL}
JWT_ACCESS_SECRET=${JWT_ACCESS_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
ACCESS_TOKEN_EXPIRES_IN=15m
REFRESH_TOKEN_EXPIRES_IN=30d
COOKIE_SECURE=false
COOKIE_SAME_SITE=lax
OTP_EXPIRES_SECONDS=120
OTP_RETRY_SECONDS=60
DELIVERY_FEE=25000
REQUEST_BODY_LIMIT=1mb
UPLOAD_DIR=uploads
MAX_UPLOAD_SIZE_MB=5
VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
VAPID_SUBJECT=mailto:admin@${PUBLIC_IP}
ZARINPAL_MERCHANT_ID=sandbox-placeholder-merchant
ZARINPAL_CALLBACK_URL=${PUBLIC_BASE_URL}/payment/callback
ZARINPAL_SANDBOX=true
PAYMENT_DEV_MOCK=true
CLIENT_APP_URL=${PUBLIC_BASE_URL}
DAILY_NOTIFICATION_CRON="0 7 * * *"
ADMIN_MOBILE=${ADMIN_MOBILE}
ADMIN_FIRST_NAME=${ADMIN_FIRST_NAME}
ADMIN_LAST_NAME=${ADMIN_LAST_NAME}
EOF
  chmod 600 "${BACKEND_ROOT}/.env"
  write_npmrc "${BACKEND_ROOT}"
}

write_frontend_env() {
  log "Writing frontend .env"
  cat >"${FRONTEND_ROOT}/.env" <<EOF
VITE_API_BASE_URL=/api/v1
VITE_APP_STORE_URL=
VITE_PLAY_STORE_URL=
VITE_DELIVERY_FEE=25000
EOF
  write_npmrc "${FRONTEND_ROOT}"
}

render_runtime_configs() {
  log "Rendering PM2 and Nginx configs"
  sed \
    -e "s|__BACKEND_ROOT__|${BACKEND_ROOT}|g" \
    "${DEPLOY_ROOT}/pm2/backend.ecosystem.config.cjs.template" \
    >"${PM2_CONFIG}"

  sed \
    -e "s|__PUBLIC_IP__|${PUBLIC_IP}|g" \
    -e "s|__FRONTEND_DIST__|${FRONTEND_DIST}|g" \
    -e "s|__BACKEND_PORT__|${BACKEND_PORT}|g" \
    "${DEPLOY_ROOT}/nginx/bbm-ip-http.conf.template" \
    | maybe_sudo tee "${NGINX_AVAILABLE}" >/dev/null

  maybe_sudo ln -sf "${NGINX_AVAILABLE}" "${NGINX_ENABLED}"
  maybe_sudo rm -f /etc/nginx/sites-enabled/default
}

configure_pm2_startup() {
  pm2 save

  if pm2_startup_ready "${USER}"; then
    log "PM2 startup already configured, skipping"
    return
  fi

  log "Configuring PM2 startup on boot"
  local startup_line
  startup_line="$(pm2 startup systemd -u "${USER}" --hp "${HOME}" | grep -E '^sudo ' | tail -n 1 || true)"
  if [[ -n "${startup_line}" ]]; then
    eval "${startup_line}"
  else
    log "PM2 startup command not found in output; service may already be configured"
  fi
}

configure_ops() {
  log "Configuring backups and log rotation"
  maybe_sudo mkdir -p "${BACKUP_DIR}"
  maybe_sudo chown "${USER}:${USER}" "${BACKUP_DIR}"

  if pm2 module:list 2>/dev/null | grep -q pm2-logrotate; then
    log "PM2 logrotate already installed, skipping install"
  else
    pm2 install pm2-logrotate
  fi
  pm2 set pm2-logrotate:max_size 20M
  pm2 set pm2-logrotate:retain 14
  pm2 set pm2-logrotate:compress true

  if [[ -f /etc/logrotate.d/bbm-app ]]; then
    log "Logrotate config already present, skipping copy"
  else
    maybe_sudo cp "${DEPLOY_ROOT}/logrotate/bbm-app.conf" /etc/logrotate.d/bbm-app
  fi

  if crontab -l 2>/dev/null | grep -Fq "${DEPLOY_ROOT}/scripts/backup_postgres.sh"; then
    log "Backup cron already configured, skipping"
  else
    local cron_line="30 2 * * * DB_PASS='${DB_PASS}' DB_NAME='${DB_NAME}' DB_USER='${DB_USER}' BACKUP_DIR='${BACKUP_DIR}' ${DEPLOY_ROOT}/scripts/backup_postgres.sh >> /var/log/bbm-backup.log 2>&1"
    (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
  fi
}

main() {
  require_command openssl

  if [[ "${EUID}" -eq 0 ]]; then
    log "Running as root (supported)"
  fi

  sync_project_to_app_root

  export APP_ROOT BACKEND_ROOT FRONTEND_ROOT FRONTEND_DIST DEPLOY_ROOT PUBLIC_IP PUBLIC_BASE_URL BACKEND_PORT DB_NAME DB_USER APP_ENV

  chmod +x "${APP_ROOT}/deploy/scripts/"*.sh

  if prereqs_ready; then
    log "Step 1/10: Prerequisites already installed, skipping"
  else
    log "Step 1/10: Installing prerequisites"
    "${APP_ROOT}/deploy/scripts/install_prereqs.sh"
  fi

  load_or_create_secrets
  export DB_PASS JWT_ACCESS_SECRET JWT_REFRESH_SECRET

  log "Step 2/10: Setting up PostgreSQL"
  DB_PASS="${DB_PASS}" DB_NAME="${DB_NAME}" DB_USER="${DB_USER}" \
    "${APP_ROOT}/deploy/scripts/setup_postgres.sh"

  generate_vapid_keys
  # shellcheck disable=SC1090
  source "${SECRETS_FILE}"

  write_backend_env
  write_frontend_env
  render_runtime_configs

  log "Step 3/10: Building and starting backend (Prisma migrate included)"
  if pm2 describe bbm-backend >/dev/null 2>&1 && [[ -f "${BACKEND_ROOT}/dist/main.js" ]] && [[ "${REDEPLOY_BACKEND:-0}" != "1" ]]; then
    log "Backend already running, skipping rebuild"
    "${APP_ROOT}/deploy/scripts/seed_admin.sh"
  else
    APP_ROOT="${APP_ROOT}" APP_ENV="${APP_ENV}" \
      "${APP_ROOT}/deploy/scripts/deploy_backend.sh"
  fi

  log "Step 4/10: Building frontend static files"
  if [[ -f "${FRONTEND_DIST}/index.html" ]] && [[ "${REDEPLOY_FRONTEND:-0}" != "1" ]]; then
    log "Frontend already built, skipping"
  else
    APP_ROOT="${APP_ROOT}" FRONTEND_ROOT="${FRONTEND_ROOT}" FRONTEND_DIST="${FRONTEND_DIST}" \
      "${APP_ROOT}/deploy/scripts/deploy_frontend.sh"
  fi

  log "Step 5/10: Enabling Nginx"
  maybe_sudo nginx -t
  maybe_sudo systemctl enable --now nginx
  maybe_sudo systemctl reload nginx

  configure_pm2_startup
  configure_ops

  log "Step 6/10: Verifying deployment"
  PUBLIC_BASE_URL="${PUBLIC_BASE_URL}" "${APP_ROOT}/deploy/scripts/verify_deploy.sh"

  log "Deployment complete"
  echo
  echo "App URL:        ${PUBLIC_BASE_URL}"
  echo "Project path:   ${APP_ROOT}"
  echo "Backend env:    ${BACKEND_ROOT}/.env"
  echo "Secrets file:   ${SECRETS_FILE}"
  echo "PM2 process:    bbm-backend"
  echo "Frontend dist:  ${FRONTEND_DIST}"
  echo
  echo "Useful commands:"
  echo "  pm2 status"
  echo "  pm2 logs bbm-backend"
  echo "  pm2 restart bbm-backend"
  echo "  systemctl reload nginx"
}

main "$@"
