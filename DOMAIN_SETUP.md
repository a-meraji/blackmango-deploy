# Domain Setup: masoudrazaghi.com on ParsPack VPS

Server IP: `185.7.212.18`  
Project path: `/var/www/blackmango`

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

## Step 2) Enable domain + HTTPS (automated)

On server:

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
