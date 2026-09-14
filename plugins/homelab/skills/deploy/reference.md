# Deployment reference

Worked templates and the reasoning behind the parts of this setup that are easy
to get wrong.

## A. Web app behind Caddy, no database

`docker-compose.yml`:

```yaml
services:
  app:
    build: .
    container_name: myapp
    restart: unless-stopped
    env_file: .env
    networks: [web]

networks:
  web:
    external: true
```

No `ports:` at all. Caddy reaches `myapp:8000` over the `web` network. Nothing to
open in the firewall, because port 80 is already open.

## B. Web app with Postgres

```yaml
services:
  app:
    build: .
    container_name: myapp
    restart: unless-stopped
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
    networks: [internal, web]

  db:
    image: postgres:17-alpine
    container_name: myapp-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [internal]

volumes:
  db_data:

networks:
  internal:
  web:
    external: true
```

The database joins `internal` only, so it is unreachable from the host and from
every other stack. The app joins both. The named volume gets a Compose project
label, which is how the backup script finds it.

## C. Dedicated published port

```yaml
services:
  app:
    image: someimage:1.2
    container_name: myapp
    restart: unless-stopped
    ports: ["8090:8090"]
    networks: [web]

networks:
  web:
    external: true
```

Then, once:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 8090 proto tcp
```

Without that rule the app is reachable over Tailscale but not from the LAN,
because the `tailscale0` allow rule covers every port while LAN access is
per-port. Add the port to the table in `deployment-guide.md`.

Never choose 443.

## D. Caddyfile block

```
myapp.tail9991b1.ts.net:80 {
    reverse_proxy myapp:8000 {
        header_up X-Forwarded-Proto https
    }
}

:80 {
    respond "Caddy is running. Add your sites here." 200
}
```

Blocks are matched by hostname; the bare `:80` block stays last as the catch-all.

**Why `:80` and not a bare hostname.** TLS is terminated by `tailscale serve` in
front of Caddy. A bare hostname makes Caddy try to provision its own certificate
for a name it does not control on a machine with no inbound 443 — it fails, and
the site never comes up.

**Why `header_up X-Forwarded-Proto https`.** Caddy receives plain HTTP from
`tailscale serve`, so without this the backend believes the browser connected
over HTTP. Any framework with an HTTPS redirect then sends the browser to the
HTTPS URL, which arrives as HTTP again: an infinite redirect loop that looks
like an app bug and is not.

## E. Where TLS comes from

```
Browser --HTTPS--> tailscale serve --HTTP--> Caddy --HTTP--> app container
          (TLS)      (on the host)           (:80)          (name:port)
```

Set up once on the server, already done:

```bash
sudo tailscale set --operator=$USER
tailscale serve --bg --https=443 http://127.0.0.1:80
tailscale serve status
```

It requires "HTTPS Certificates" enabled at
<https://login.tailscale.com/admin/dns>. The certificate is a real Let's Encrypt
one for the `*.ts.net` name and renews itself.

Because `tailscale serve` forwards everything on 443 to Caddy on port 80, a new
HTTPS site needs no new `serve` command — only a Caddy route.

**The failure this creates.** `tailscale serve` binds 443 on the `tailscale0`
interface. Any Docker container publishing `443:443` binds `0.0.0.0:443`, which
takes precedence. `tailscale serve` keeps reporting itself as healthy, and every
HTTPS connection fails during the TLS handshake with nothing logged anywhere.
Caddy's own 443 publish was removed for exactly this reason. This plugin has a
hook that refuses to write or run such a publish.

## F. Secrets

Generated on the server, stored only there:

```bash
cd ~/docker-apps/<app>
{ echo "POSTGRES_PASSWORD=$(openssl rand -base64 24)"
  echo "SECRET_KEY=$(openssl rand -base64 48)"
} > .env
chmod 600 .env
```

`.env` is excluded from every rsync, so a redeploy never clobbers it, and it is
in no repository. That also means it is the only copy: losing the server loses
the secrets. `/homelab:backup` covers data, not `.env` — copy that file
somewhere safe by hand if the app cannot regenerate its secrets.

## G. Django specifics

The app on this server that exercises all of the above is Agelcom.

```python
ALLOWED_HOSTS = ["lacrevetteserver.tail9991b1.ts.net", "192.168.1.160", "127.0.0.1"]
CSRF_TRUSTED_ORIGINS = ["https://lacrevetteserver.tail9991b1.ts.net"]
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

`SECURE_PROXY_SSL_HEADER` is what makes the `header_up` line above actually take
effect. `CSRF_TRUSTED_ORIGINS` entries need the scheme.

Entrypoint pattern, so every restart is self-healing:

```bash
python manage.py migrate --noinput
python manage.py collectstatic --noinput
exec gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 3
```

Three gunicorn workers suits 4 cores with a database and other services on the
same box.

## H. Nextcloud specifics

Nextcloud maintains `trusted_domains` and rejects any other `Host` header with
an "Access through untrusted domain" page. This looks like a network failure and
is not.

```bash
docker exec nextcloud cat /var/www/html/config/config.php | grep -A6 trusted_domains
docker exec -u www-data nextcloud php occ config:system:set trusted_domains <index> --value=<host:port>
```

## I. Constraints worth designing around

4 cores, 15 GB RAM, ~422 GB free, on home Wi-Fi, on a laptop with no UPS, with a
LAN address that is probably DHCP-assigned. No off-machine backups yet.

An app that holds data which exists nowhere else should have `/homelab:backup`
run and pulled before it is treated as a real system of record.
