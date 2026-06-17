#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as a regular sudo-capable user, not root."
  exit 1
fi

sudo apt update
sudo apt -y upgrade
sudo apt install -y curl ca-certificates gnupg lsb-release git ufw nginx postgresql postgresql-contrib build-essential

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt install -y nodejs
fi

if ! command -v pm2 >/dev/null 2>&1; then
  sudo npm i -g pm2
fi

sudo systemctl enable --now postgresql
sudo systemctl enable --now nginx

sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

echo "Prerequisites installed."
node -v
npm -v
pm2 -v
sudo ufw status

