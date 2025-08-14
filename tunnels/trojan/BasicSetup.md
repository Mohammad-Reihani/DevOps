# Trojan server

Here we are using docker. thats it. so ensure you HAVE docker installed on your server
and I'm using Debian 12, but it should work fine everywhere.

## Overview

We configured a Trojan server in Docker on Debian 12 with:

- TLS issued via Let’s Encrypt (certbot),
- Trojan container (`trojangfw/trojan`),
- an internal nginx backend serving a fake website at `/opt/trojan/webroot`,
- a small `plain_http_response` fallback for plaintext scanners,

---

## Prereqs (what we assumed)

- Debian 12 VPS with root / sudo.
- Docker & Docker Compose installed.
- Domain `vpn.your.domain` pointing to VPS IPv4 (A record) and if you are using Cloudflare, put the proxy = **OFF** (grey cloud).
- Port 443 and 80 available during cert issuance (certbot standalone binds 80).

---

## 1 — Obtain TLS certificate (certbot apt method, Debian 12)

Stop any temporary web server on port 80 then install certbot:

```bash
sudo apt update
sudo apt install certbot -y
```

Issue cert for the exact hostname (subdomain):

```bash
sudo certbot certonly --standalone -d vpn.your.domain --non-interactive --agree-tos -m you@your.email
```

Files created:

- `/etc/letsencrypt/live/vpn.your.domain/fullchain.pem`
- `/etc/letsencrypt/live/vpn.your.domain/privkey.pem`

Test (dry run):

```bash
sudo certbot renew --dry-run
```

---

## 2 — Create plain_http_response file

Trojan expects a file path. We put:

```bash
sudo mkdir -p /opt/trojan
sudo tee /opt/trojan/plain_http_response.html > /dev/null <<'EOF'
HTTP/1.1 404 Not Found
Content-Type: text/html

<html><body><h1>404 Not Found</h1></body></html>
EOF
```

This file is a raw HTTP response Trojan sends on plain/non-TLS connections to port 443. I guess you may change it accordingly

---

## 3 — Fake website (nginx webroot)

Create webroot and a convincing `index.html`:

```bash
sudo mkdir -p /opt/trojan/webroot
sudo tee /opt/trojan/webroot/index.html > /dev/null <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>Not Found</title></head>
<body>
  <h1>404 Not Found</h1>
  <p>The requested resource was not found on this server.</p>
</body>
</html>
EOF
```

of course later you can put your full website here! no body will know!

nginx config `/opt/trojan/nginx.conf`:

```nginx
server {
  listen 80;
  server_name vpn.your.domain;
  root /usr/share/nginx/html;
  index index.html;
  location / {
    try_files $uri $uri/ =404;
  }
  error_page 404 /index.html;
}
```

We do **not** expose nginx on host port 80 in Docker Compose — it’s internal only; Trojan forwards to it. don't worry

---

## 4 — Trojan configuration

Create `/etc/trojan/config.json` — example (multi-user password array):

```json
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "web",
  "remote_port": 80,
  "password": ["user1-REPLACE_THIS", "user2-REPLACE_THIS"],
  "log_level": 1,
  "ssl": {
    "cert": "/config/fullchain.pem",
    "key": "/config/privkey.pem",
    "key_password": "",
    "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256",
    "prefer_server_cipher": true,
    "alpn": ["http/1.1"],
    "reuse_session": true,
    "session_ticket": false,
    "session_timeout": 600,
    "plain_http_response": "/config/plain_http_response.html",
    "curves": "",
    "dhparam": ""
  },
  "tcp": {
    "prefer_ipv4": true
  }
}
```

Notes:

- `remote_addr: "web"` points to the internal nginx service in Compose.
- Add or remove passwords here to manage users.
- You can generate safe passwords using:

  ```bash
  openssl rand -base64 20
  # Or HEX
  openssl rand -hex 20
  ```

---

## 5 — Docker Compose ( `~/trojan/docker-compose.yml` )

```yaml
version: "3.8"
services:
  trojan:
    image: trojangfw/trojan:latest
    container_name: trojan
    restart: unless-stopped
    ports:
      - "443:443/tcp"
    volumes:
      - /etc/trojan/config.json:/config/config.json:ro
      - /etc/letsencrypt/live/vpn.your.domain/fullchain.pem:/config/fullchain.pem:ro
      - /etc/letsencrypt/live/vpn.your.domain/privkey.pem:/config/privkey.pem:ro
      - /opt/trojan/plain_http_response.html:/config/plain_http_response.html:ro
    depends_on:
      - web
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  web:
    image: nginx:stable-alpine
    container_name: trojan-web
    restart: unless-stopped
    volumes:
      - /opt/trojan/webroot:/usr/share/nginx/html:ro
      - /opt/trojan/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "2"
```

Deploy:

```bash
cd /opt/trojan
sudo docker compose up -d
```

Logs:

```bash
sudo docker logs -f trojan
sudo docker logs -f trojan-web
```

---

## 6 — Client connection (V2RayNG / Clash / other)

Manual Trojan URI:

```url
trojan://<password>@vpn.your.domain:443
```

---

## 7 — Renewals / reload Trojan on cert change

Create a deploy hook or script to restart the container after renewal. Example script `/usr/local/bin/certbot-reload-trojan.sh`:

```bash
#!/bin/bash
cd /opt/trojan || exit 1
/usr/bin/docker compose restart trojan
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/certbot-reload-trojan.sh
```

When requesting certs via certbot, pass:

```bash
sudo certbot renew --deploy-hook "/usr/local/bin/certbot-reload-trojan.sh"
```

Or add the deploy hook in `/etc/letsencrypt/renewal-hooks/deploy/`.

---

## 8 — User management (add/remove)

**Add user**: edit `/etc/trojan/config.json`, append new password in `password` array, then:

```bash
cd /opt/trojan
sudo docker compose restart trojan
```

**Remove user**: remove password line and restart.

> Optionally script this for atomic changes.

---

## 9 — Firewall (ufw example)

Allow SSH + 443 only, for example:

```bash
sudo apt install ufw -y
sudo ufw allow ssh
sudo ufw allow 443/tcp
sudo ufw enable
```

If you use IPv6, add rules accordingly.

---

## What's next?

- **Add-Delete users automation** can be handled via small shell script
- **Fail2ban** for Docker/Trojan logs: block repeated bad TLS connections (if you want).

## Any Ideas?

Just tell me, I'll add. well, I'll try to.
