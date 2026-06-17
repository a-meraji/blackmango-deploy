#!/usr/bin/env bash

export NPM_CONFIG_REGISTRY="${NPM_CONFIG_REGISTRY:-https://package-mirror.liara.ir/repository/npm/}"

maybe_sudo() {
  sudo "$@"
}

write_npmrc() {
  local dir="$1"
  printf 'registry=%s\n' "${NPM_CONFIG_REGISTRY}" >"${dir}/.npmrc"
}

npm_ci_install() {
  npm ci --registry="${NPM_CONFIG_REGISTRY}" "$@"
}

npm_install() {
  npm install --registry="${NPM_CONFIG_REGISTRY}" "$@"
}

prereqs_ready() {
  command -v node >/dev/null 2>&1 &&
    command -v npm >/dev/null 2>&1 &&
    command -v pm2 >/dev/null 2>&1 &&
    command -v nginx >/dev/null 2>&1 &&
    systemctl is-active --quiet postgresql &&
    systemctl is-active --quiet nginx
}

postgres_ready() {
  local db_user="${1:-}"
  local db_name="${2:-}"
  local db_pass="${3:-}"

  [[ -n "${db_user}" && -n "${db_name}" && -n "${db_pass}" ]] || return 1

  PGPASSWORD="${db_pass}" psql -h 127.0.0.1 -U "${db_user}" -d "${db_name}" -c "SELECT 1;" >/dev/null 2>&1
}

pm2_startup_ready() {
  local user="${1:-${USER}}"

  systemctl list-unit-files "pm2-${user}.service" --no-legend 2>/dev/null | grep -q "pm2-${user}.service"
}
