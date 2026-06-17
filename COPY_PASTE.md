# Copy-Paste Deployment Commands

Use this if the project is already on your Debian server (`185.7.212.18`).

The bootstrap script will automatically:

- install PostgreSQL, Nginx, Node.js, PM2
- generate DB/JWT/VAPID secrets
- create `backend/.env` and `frontend/.env`
- run Prisma migrations
- build backend + frontend
- start backend with PM2
- configure Nginx reverse proxy
- enable backups and log rotation

No manual env editing is required.

---

## 1) SSH into server

```bash
ssh root@185.7.212.18
```

---

## 2) Go to project folder

```bash
cd /var/www/blackmango
```

If you are not sure where it is:

```bash
find /root /home /var/www -maxdepth 4 -type d -name big_black_mango 2>/dev/null
```

Then:

```bash
cd /path/to/big_black_mango
```

Example if project is in home:

```bash
cd ~/big_black_mango
```

---

## 3) Run one-command bootstrap (copy all 3 lines)

```bash
chmod +x deploy/scripts/*.sh
./deploy/scripts/bootstrap_server.sh
```

That is it.

---

## 4) After it finishes, open in browser

```bash
http://185.7.212.18
```

Quick checks:

```bash
pm2 status
curl -I http://185.7.212.18/
curl -I http://185.7.212.18/api/v1
```

---

## Optional: upload project from your Mac first

Run this on your Mac (only if code is not on server yet):

```bash
rsync -avz \
  --exclude node_modules \
  --exclude backend/uploads \
  --exclude frontend/dist \
  --exclude .git \
  /Users/khaneapple/Documents/dev/big_black_mango/ \
  YOUR_SSH_USER@185.7.212.18:~/big_black_mango/
```

Then SSH and run bootstrap:

```bash
ssh YOUR_SSH_USER@185.7.212.18
cd ~/big_black_mango
chmod +x deploy/scripts/*.sh
./deploy/scripts/bootstrap_server.sh
```

---

## Generated files on server

- App install path: `/var/www/blackmango` (auto-detected from project folder)
- Backend env: `/var/www/blackmango/backend/.env`
- Frontend env: `/var/www/blackmango/frontend/.env`
- Secrets: `/var/www/blackmango/deploy/.generated.env`
- Frontend served from: `/var/www/blackmango/frontend-dist`

Keep `deploy/.generated.env` safe. It contains DB and JWT secrets.

---

## Re-deploy after code updates

```bash
cd ~/big_black_mango
git pull
./deploy/scripts/bootstrap_server.sh
```

---

## Common maintenance commands

```bash
pm2 restart bbm-backend
pm2 logs bbm-backend --lines 100
sudo systemctl reload nginx
sudo nginx -t
```
