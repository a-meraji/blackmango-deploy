# Debian Deployment Runbook

## Fastest path (no manual env edits)

If the project is already on the server, use the one-command bootstrap:

```bash
cd /path/to/big_black_mango
chmod +x deploy/scripts/*.sh
./deploy/scripts/bootstrap_server.sh
```

Full copy-paste commands: [COPY_PASTE.md](COPY_PASTE.md)

---

This runbook deploys `big_black_mango` on Debian with:

- local PostgreSQL
- backend on PM2
- frontend static files on Nginx
- Nginx reverse proxy for `/api` and `/uploads`
- IP-based HTTP (`http://185.7.212.18`) for now

## Important Constraint in This Codebase

Backend environment validation enforces:

- `NODE_ENV=production` requires `COOKIE_SECURE=true`
- secure cookies require HTTPS

Because you are deploying on IP + HTTP right now, run backend with:

- `NODE_ENV=staging`
- `COOKIE_SECURE=false`

When domain + HTTPS is ready, switch to:

- `NODE_ENV=production`
- `COOKIE_SECURE=true`

## 0) Variables Used in Commands

Set these once in your SSH session:

```bash
export APP_USER=deploy
export APP_GROUP=www-data
export APP_ROOT=/var/www/big_black_mango
export BACKEND_ROOT=$APP_ROOT/backend
export FRONTEND_ROOT=$APP_ROOT/frontend
export FRONTEND_DIST=$APP_ROOT/frontend-dist
export BACKEND_PORT=3000
export PUBLIC_IP=185.7.212.18
export DB_NAME=blackmango_db
export DB_USER=blackmango_user
export DB_PASS='CHANGE_THIS_STRONG_DB_PASSWORD'
```

## 1) System Preparation

```bash
sudo apt update && sudo apt -y upgrade
sudo apt install -y curl ca-certificates gnupg lsb-release git ufw nginx postgresql postgresql-contrib build-essential
```

Install Node 22 LTS:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
node -v
npm -v
```

Install PM2 globally:

```bash
sudo npm i -g pm2
pm2 -v
```

Firewall:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
sudo ufw status
```

## 2) PostgreSQL Setup

```bash
sudo systemctl enable --now postgresql
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
```

Connectivity test:

```bash
PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;"
```

## 3) Project Layout and Permissions

```bash
sudo mkdir -p "$APP_ROOT"
sudo chown -R "$USER":"$USER" "$APP_ROOT"
cd "$APP_ROOT"
```

Copy your project (git clone or rsync). Expected result:

- `$BACKEND_ROOT`
- `$FRONTEND_ROOT`

Create persistent uploads dir:

```bash
mkdir -p "$BACKEND_ROOT/uploads"
```

## 4) Backend Environment

Create backend env file:

```bash
cp "$BACKEND_ROOT/.env.example" "$BACKEND_ROOT/.env"
```

Edit `backend/.env` with real values. Minimum required for HTTP/IP phase:

```env
DATABASE_URL=postgresql://blackmango_user:CHANGE_THIS_STRONG_DB_PASSWORD@127.0.0.1:5432/blackmango_db
NODE_ENV=staging
PORT=3000
API_PREFIX=/api/v1
APP_URL=http://185.7.212.18
ENABLE_SWAGGER=false
CORS_ORIGINS=http://185.7.212.18
JWT_ACCESS_SECRET=CHANGE_THIS_TO_32_PLUS_CHARS_ACCESS_SECRET
JWT_REFRESH_SECRET=CHANGE_THIS_TO_32_PLUS_CHARS_REFRESH_SECRET
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
VAPID_PUBLIC_KEY=FILL_ME
VAPID_PRIVATE_KEY=FILL_ME
VAPID_SUBJECT=mailto:admin@example.com
ZARINPAL_MERCHANT_ID=FILL_ME
ZARINPAL_CALLBACK_URL=http://185.7.212.18/payment/callback
ZARINPAL_SANDBOX=true
PAYMENT_DEV_MOCK=true
CLIENT_APP_URL=http://185.7.212.18
DAILY_NOTIFICATION_CRON=0 7 * * *
```

Generate VAPID keys if missing:

```bash
cd "$BACKEND_ROOT"
node -e "const w=require('web-push');console.log(w.generateVAPIDKeys())"
```

## 5) Build Backend (Prisma Included)

```bash
cd "$BACKEND_ROOT"
npm ci
npm run build
```

`npm run build` already executes:

- `prisma generate`
- `prisma migrate deploy`
- `prisma/seed-admin.ts`
- Nest build to `dist/`

## 6) Frontend Environment and Build

Create frontend env file:

```bash
cp "$FRONTEND_ROOT/.env.example" "$FRONTEND_ROOT/.env"
```

Recommended values:

```env
VITE_API_BASE_URL=/api/v1
VITE_APP_STORE_URL=
VITE_PLAY_STORE_URL=
VITE_DELIVERY_FEE=25000
```

Build and publish static files:

```bash
cd "$FRONTEND_ROOT"
npm ci
npm run build
rm -rf "$FRONTEND_DIST"
mkdir -p "$FRONTEND_DIST"
cp -R dist/* "$FRONTEND_DIST/"
```

## 7) PM2 for Backend

From repo root on server:

```bash
cd "$APP_ROOT"
pm2 start deploy/pm2/backend.ecosystem.config.cjs --env staging
pm2 save
pm2 startup systemd -u "$USER" --hp "$HOME"
```

Run the printed `sudo` command from `pm2 startup`.

Check:

```bash
pm2 status
pm2 logs bbm-backend --lines 150
```

## 8) Nginx Configuration

Copy included config:

```bash
sudo cp "$APP_ROOT/deploy/nginx/bbm-ip-http.conf" /etc/nginx/sites-available/bbm-ip-http.conf
sudo ln -sf /etc/nginx/sites-available/bbm-ip-http.conf /etc/nginx/sites-enabled/bbm-ip-http.conf
sudo rm -f /etc/nginx/sites-enabled/default
```

Validate and reload:

```bash
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

## 9) Verify End-to-End

```bash
curl -I "http://$PUBLIC_IP/"
curl -i "http://$PUBLIC_IP/api/v1"
curl -I "http://$PUBLIC_IP/uploads/"
pm2 status
sudo systemctl status nginx --no-pager
```

Also test in browser:

- `http://185.7.212.18`
- open an app deep link route directly (SPA fallback check)
- auth/login flow
- upload flow

## 10) Operations: Backups, Logs, Restarts

Install PM2 log rotation:

```bash
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 20M
pm2 set pm2-logrotate:retain 14
pm2 set pm2-logrotate:compress true
```

Enable PostgreSQL backup cron (2:30 AM daily):

```bash
chmod +x "$APP_ROOT/deploy/scripts/backup_postgres.sh"
(crontab -l 2>/dev/null; echo "30 2 * * * $APP_ROOT/deploy/scripts/backup_postgres.sh >> /var/log/bbm-backup.log 2>&1") | crontab -
```

Quick restart commands:

```bash
pm2 restart bbm-backend
sudo systemctl reload nginx
```

## 11) When Domain + SSL Is Ready

1. Point DNS to server.
2. Install certbot and issue certificate.
3. Change backend env:
   - `NODE_ENV=production`
   - `COOKIE_SECURE=true`
   - `CORS_ORIGINS=https://your-domain`
   - `APP_URL=https://your-domain`
   - `CLIENT_APP_URL=https://your-domain`
4. Restart PM2 + Nginx.

