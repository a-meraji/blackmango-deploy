#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

maybe_sudo apt update
maybe_sudo apt -y upgrade
maybe_sudo apt install -y curl ca-certificates gnupg lsb-release git ufw nginx postgresql postgresql-contrib build-essential

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | maybe_sudo -E bash -
  maybe_sudo apt install -y nodejs
fi

if ! command -v pm2 >/dev/null 2>&1; then
  maybe_sudo npm i -g pm2
fi

maybe_sudo systemctl enable --now postgresql
maybe_sudo systemctl enable --now nginx

maybe_sudo ufw allow OpenSSH
maybe_sudo ufw allow 'Nginx Full'
maybe_sudo ufw --force enable

echo "Prerequisites installed."
node -v
npm -v
pm2 -v
maybe_sudo ufw status
