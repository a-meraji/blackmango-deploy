# Domain Setup: masoudrazaghi.com on ParsPack VPS

> **ParsPack / Iranian VPS note:** Let's Encrypt's HTTP-01 challenge servers cannot reach
> this VPS from the internet, so `certbot --nginx` times out. Use **Option A** below —
> obtain the cert from the Parspack panel and install it manually.

Server IP: `185.7.212.18`  
Project path: `/var/www/blackmango`

> **Repository layout — THREE separate git repos (no all-in-one).** `/var/www/blackmango` is
> a plain container directory (it is **not** a git repo). Inside it live three independent
> repositories cloned side by side:
>
> | Path | Repo |
> | --- | --- |
> | `/var/www/blackmango/backend`  | `git@github.com:amirhoseinqd/blackmango-backend.git` |
> | `/var/www/blackmango/frontend` | `git@github.com:a-meraji/bigblackmango.git` |
> | `/var/www/blackmango/deploy`   | `git@github.com:a-meraji/blackmango-deploy.git` |
>
> First-time clone:
> ```bash
> sudo mkdir -p /var/www/blackmango && sudo chown "$USER" /var/www/blackmango
> cd /var/www/blackmango
> git clone git@github.com:amirhoseinqd/blackmango-backend.git backend
> git clone git@github.com:a-meraji/bigblackmango.git          frontend
> git clone git@github.com:a-meraji/blackmango-deploy.git      deploy
> ```
> To update later, pull each repo — or run the helper `./deploy/scripts/pull_all.sh`.
> Never run `git pull` at `/var/www/blackmango` itself; there is no repo there by design.

## Step 1) DNS in ParsPack panel

Log in to ParsPack and open DNS management for `masoudrazaghi.com`.

Create these records:

| Type | Name/Host | Value | TTL |
|------|-----------|-------|-----|
| A | `@` | `185.7.212.18` | 300 (or default) |
| A | `www` | `185.7.212.18` | 300 (or default) |

Notes:
- If domain DNS is not on ParsPack, set the same A records wherever DNS is managed.
- Remove old A records pointing to another IP.
- Do not add conflicting CNAME for `@` or `www`.

Wait 5-30 minutes, then verify on server:

```bash
dig +short masoudrazaghi.com A
dig +short www.masoudrazaghi.com A
```

Both should return `185.7.212.18`.

## Step 2) Option A — Manual cert install (ParsPack panel certs)

### 2a) Pull latest code on server

```bash
cd /var/www/blackmango
./deploy/scripts/pull_all.sh      # pulls backend + frontend + deploy (three separate repos)
chmod +x deploy/scripts/*.sh
```

### 2b) Place the cert files

Create the directory and paste each cert block. Use `cat >` so you can paste multiple lines, then press **Ctrl+D** to save.

```bash
mkdir -p /etc/ssl/bbm/masoudrazaghi.com
```

**fullchain.pem** — paste the "full chain" value from Parspack (the one with TWO or THREE `-----BEGIN CERTIFICATE-----` blocks):

```bash
cat > /etc/ssl/bbm/masoudrazaghi.com/fullchain.pem
# paste, then Ctrl+D
```

**privkey.pem** — paste the "private key" value from Parspack:

```bash
cat > /etc/ssl/bbm/masoudrazaghi.com/privkey.pem
# paste, then Ctrl+D
chmod 600 /etc/ssl/bbm/masoudrazaghi.com/privkey.pem
```

Verify both files look right:

```bash
openssl x509 -noout -subject -dates -in /etc/ssl/bbm/masoudrazaghi.com/fullchain.pem
openssl rsa  -noout -check        -in /etc/ssl/bbm/masoudrazaghi.com/privkey.pem
```

### 2c) Run the install script

```bash
cd /var/www/blackmango
./deploy/scripts/install_manual_ssl.sh
```

The script will:
- set correct permissions on certs
- render the Nginx HTTPS config from the template
- switch Nginx from IP/HTTP config to domain+HTTPS config
- update `backend/.env` (`COOKIE_SECURE`, `APP_URL`, `CORS_ORIGINS`, etc.)
- restart the backend PM2 process
- verify with curl

### 2d) Cert renewal (every ~90 days)

The Parspack panel shows the expiry date. When it's close:
1. Renew in Parspack panel → download new cert files
2. Overwrite the files on server (same `cat >` commands as step 2b)
3. `nginx -t && systemctl reload nginx` — no restart needed, just reload

---

## Step 2 Alt) Option B — Automated certbot (only if certbot can reach internet)

On server (only if `curl https://acme-v02.api.letsencrypt.org` succeeds from the VPS):

```bash
cd /var/www/blackmango
chmod +x deploy/scripts/enable_domain.sh

DOMAIN=masoudrazaghi.com \
CERTBOT_EMAIL=your-email@example.com \
./deploy/scripts/enable_domain.sh
```

This script will:
- switch Nginx from IP config to domain config
- update backend `.env` for HTTPS production
- install Certbot (if missing)
- issue Let's Encrypt SSL for apex + www
- restart backend with PM2 production env

## Step 3) Manual alternative (if script fails)

### Nginx domain config

```bash
DOMAIN=masoudrazaghi.com
APP_ROOT=/var/www/blackmango

sed \
  -e "s|__DOMAIN__|${DOMAIN}|g" \
  -e "s|__FRONTEND_DIST__|${APP_ROOT}/frontend-dist|g" \
  -e "s|__BACKEND_PORT__|3000|g" \
  "${APP_ROOT}/deploy/nginx/bbm-domain-http.conf.template" \
  > /etc/nginx/sites-available/bbm-domain.conf

ln -sf /etc/nginx/sites-available/bbm-domain.conf /etc/nginx/sites-enabled/bbm-domain.conf
rm -f /etc/nginx/sites-enabled/bbm-ip-http.conf
nginx -t && systemctl reload nginx
```

### SSL certificate

```bash
apt update
apt install -y certbot python3-certbot-nginx

certbot --nginx \
  -d masoudrazaghi.com \
  -d www.masoudrazaghi.com \
  --agree-tos \
  -m your-email@example.com \
  --redirect
```

### Backend env (required for production auth cookies)

Edit `/var/www/blackmango/backend/.env`:

```env
NODE_ENV=production
COOKIE_SECURE=true
COOKIE_SAME_SITE=lax
APP_URL=https://masoudrazaghi.com
CLIENT_APP_URL=https://masoudrazaghi.com
CORS_ORIGINS=https://masoudrazaghi.com,https://www.masoudrazaghi.com
ZARINPAL_CALLBACK_URL=https://masoudrazaghi.com/payment/callback
DAILY_NOTIFICATION_CRON="0 7 * * *"
```

Restart backend:

```bash
pm2 restart bbm-backend --update-env --env production
pm2 save
```

## Step 4) Verify

```bash
curl -I https://masoudrazaghi.com/
curl -I https://masoudrazaghi.com/api/v1/health
pm2 status
```

Open in browser:
- https://masoudrazaghi.com
- test login with admin mobile `09033018426`

## ParsPack-specific tips

- Ensure VPS firewall allows ports `80` and `443` (you already allow Nginx Full in UFW).
- If domain was previously on another host, clear old DNS/proxy settings first.
- If Certbot fails with connection timeout, DNS is not propagated yet or port 80 is blocked.
- Auto-renew is handled by certbot systemd timer:

```bash
systemctl status certbot.timer
certbot renew --dry-run
```

## Optional: force www -> apex (or apex -> www)

Certbot `--redirect` enables HTTPS redirect.  
If you want only one canonical host, configure redirect in Nginx after SSL is active.

---

## Step 5) Admin subdomain — admin.masoudrazaghi.com (separated admin SPA)

The admin panel is a **separate** plain SPA (no service worker / PWA). It is served at
`admin.masoudrazaghi.com` and **proxies its own `/api` + `/uploads`** to the same backend
(`127.0.0.1:3000`), so every admin call is same-origin → **no CORS, no `CORS_ORIGINS`
change, no backend edits**.

### 5a) DNS — add the admin A record (ParsPack panel)

| Type | Name/Host | Value | TTL |
|------|-----------|-------|-----|
| A | `admin` | `185.7.212.18` | 300 (or default) |

Verify after propagation:

```bash
dig +short admin.masoudrazaghi.com A   # must return 185.7.212.18
```

### 5b) TLS — cert must be valid for admin.masoudrazaghi.com

Two options:

- **Recommended — one SAN cert:** in the Parspack panel, (re)issue the
  `masoudrazaghi.com` cert with `admin.masoudrazaghi.com` added to its SAN list, then
  overwrite `/etc/ssl/bbm/masoudrazaghi.com/{fullchain,privkey}.pem` (same `cat >` flow as
  Step 2b). One cert renews both apex and admin. `install_admin_ssl.sh` uses this dir by
  default.
- **Alternative — standalone admin cert:** obtain a cert for `admin.masoudrazaghi.com` and
  place it at `/etc/ssl/bbm/admin.masoudrazaghi.com/{fullchain,privkey}.pem`, then run the
  install script with `CERT_DIR=/etc/ssl/bbm/admin.masoudrazaghi.com`.

### 5c) Build the admin SPA and bring up the nginx block

```bash
cd /var/www/blackmango
./deploy/scripts/pull_all.sh      # frontend (admin source) + deploy (scripts/templates)
chmod +x deploy/scripts/*.sh

# build admin-dist (independent of the customer PWA)
./deploy/scripts/deploy_admin.sh

# render + enable the admin HTTPS nginx block, then reload nginx
./deploy/scripts/install_admin_ssl.sh
# (standalone cert variant: CERT_DIR=/etc/ssl/bbm/admin.masoudrazaghi.com ./deploy/scripts/install_admin_ssl.sh)
```

### 5d) Verify

```bash
curl -I https://admin.masoudrazaghi.com/            # 200, serves admin index.html
curl -I https://admin.masoudrazaghi.com/api/v1/health
```

In the browser at `https://admin.masoudrazaghi.com`: log in, and confirm in DevTools →
**no Service Worker and no manifest** (admin is a plain SPA), and that API calls are
**same-origin 200s with no `OPTIONS` preflight** (proof CORS is not in play).

---

## Step 6) Routine deploys (after one-time setup above) — one command

Once DNS + TLS + both nginx blocks exist (Steps 1–5), every later code deploy is a single
command. It rebuilds **both** front-ends, reloads nginx, and **verifies each host serves the
right app** — it fails loudly if `admin.<domain>` is serving the customer home page:

```bash
cd /var/www/blackmango
./deploy/scripts/pull_all.sh      # updates all three repos (no all-in-one repo exists)
DOMAIN=masoudrazaghi.com ./deploy/scripts/deploy_all.sh
```

Useful flags:

```bash
SKIP_ADMIN=1        DOMAIN=masoudrazaghi.com ./deploy/scripts/deploy_all.sh   # customer only
SKIP_CUSTOMER=1     DOMAIN=masoudrazaghi.com ./deploy/scripts/deploy_all.sh   # admin only
REDEPLOY_BACKEND=1  DOMAIN=masoudrazaghi.com ./deploy/scripts/deploy_all.sh   # + rebuild backend
```

The deploy aborts with a clear message if the admin nginx block isn't enabled (pointing you
back to Step 5). To re-check routing at any time:

```bash
DOMAIN=masoudrazaghi.com ./deploy/scripts/verify_deploy.sh
```

### Troubleshooting: "admin.<domain> shows the customer home page"

The request to `admin.<domain>` is **not matching the admin nginx block** and is falling
through to the apex/customer block. Diagnose:

```bash
ls -l /etc/nginx/sites-enabled/                       # is bbm-admin.conf present?
sudo nginx -T | grep -nE 'server_name|root /var'      # which server_name owns admin.<domain>?
curl -skI --resolve admin.masoudrazaghi.com:443:127.0.0.1 https://admin.masoudrazaghi.com/
```

Fix = bring up the admin block, then re-verify:

```bash
DOMAIN=masoudrazaghi.com ./deploy/scripts/install_admin_ssl.sh
DOMAIN=masoudrazaghi.com ./deploy/scripts/deploy_all.sh
```
