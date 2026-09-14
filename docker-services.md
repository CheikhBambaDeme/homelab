# Docker Services

All services live under `~/docker-apps/` on the server, each app in its own subfolder as an independent Docker Compose project.

**Docker context gotcha:** this machine has two Docker contexts — `default` (→ `unix:///var/run/docker.sock`, the real, running Docker engine) and `desktop-linux` (a leftover Docker Desktop context pointing at a socket that isn't running). Always confirm with `docker context ls` that `default` is the active one (marked with `*`) before running `docker`/`docker compose` commands — using the wrong context produces confusing "cannot connect to daemon" errors.

## Shared network
An external Docker network named `web` connects services meant to be reachable through the Caddy reverse proxy:
```bash
docker network create web   # already created — only needed once, or if it's ever removed
```
Any new app's compose file should join this network (`networks: { web: { external: true } }`) if Caddy needs to reach it, or if it needs to reach another service on it.

---

## `~/docker-apps/docker-compose.yml` — Portainer + Caddy

### Portainer (container management UI)
- Image: `portainer/portainer-ce:latest`, container name `portainer`
- Access: `https://100.82.241.64:9443` (Tailscale only — port 9443 was never opened on the LAN firewall, so it's not reachable via `192.168.1.160`)
- Browser will warn about a self-signed certificate — expected, click through it.
- First-time setup requires a one-time token from the container logs (expires after a few minutes):
  ```bash
  docker logs portainer 2>&1 | grep "setup_token=" | tail -1
  ```
  If it expires before use: `docker restart portainer`, then grab the token again the same way.
- Data persisted in Docker volume `docker-apps_portainer_data`.

### Caddy (reverse proxy)
- Image: `caddy:latest`, container name `caddy`
- Config file: `~/docker-apps/caddy/Caddyfile` (bind-mounted into the container)
- Publishes host ports 80 and 81. 443 is deliberately left unpublished so
  `tailscale serve` can bind it on the Tailscale interface — Docker publishing
  `443:443` grabs `0.0.0.0:443`, which shadows the Tailscale IP and makes every
  HTTPS connection fail the TLS handshake with no useful error. This bit during
  the Agelcom deployment. **TLS on this server is terminated by Tailscale, never
  by Caddy**; if you ever need Caddy to terminate TLS itself, you must move
  `tailscale serve` to another port first.
- Routes by hostname on `:80`, and by port on `:81`. Agelcom is the site behind
  `:80`, with the placeholder kept as the catch-all for anything else; GymLog is
  behind `:81`, because both apps answer to the *same* hostname — see its section
  below for why that forces a second port:
  ```
  lacrevetteserver.tail9991b1.ts.net:80 {
      reverse_proxy agelcom:8000 {
          header_up X-Forwarded-Proto https
      }
  }

  :80 {
      respond "Caddy is running. Add your sites here." 200
  }

  :81 {
      reverse_proxy gymlog:8000 {
          header_up X-Forwarded-Proto https
      }
  }
  ```
  **Why `:80` and a forced `X-Forwarded-Proto`:** TLS is terminated by
  `tailscale serve` in front of Caddy, so Caddy must *not* try to provision its
  own certificate (hence the explicit `:80` on the site block), and it must tell
  the backend the original connection was HTTPS — otherwise an app that enforces
  HTTPS answers every request with a redirect loop. Copy this shape for the next
  Tailscale-served site.
  The pre-GymLog versions of this file and of `~/docker-apps/docker-compose.yml`
  are kept beside them on the server as `*.bak-2026-09-14`.
- Access: `http://100.82.241.64` (Tailscale) or `http://192.168.1.160` (LAN)
- To add a new site, edit the Caddyfile then reload without restarting the container:
  ```bash
  docker exec caddy caddy reload --config /etc/caddy/Caddyfile
  ```
  (a full `docker compose restart caddy` from `~/docker-apps/` also works)
- **A new *port*, though, needs the container recreated**, not just a reload — the
  publish list is fixed at container creation. `docker compose up -d caddy` from
  `~/docker-apps/` does it, and costs every site behind Caddy a couple of seconds
  of downtime. That is how port 81 was added for GymLog.

---

## `~/docker-apps/nextcloud/docker-compose.yml` — Nextcloud (file hosting)

### Database (`nextcloud-db`)
- Image: `mariadb:11`, container name `nextcloud-db`
- On an `internal`-only Docker network — not exposed to the host or other stacks
- Credentials (`MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`) were randomly generated during setup and live only in `~/docker-apps/nextcloud/.env` on the server (mode `600`) — not recorded anywhere else

### App (`nextcloud`)
- Image: `nextcloud:latest`, container name `nextcloud`
- Host port `8080` → container port `80`
- On both the `internal` network (to reach the DB) and `web` (available for Caddy/other services)
- Access: `http://100.82.241.64:8080` (Tailscale) or `http://192.168.1.160:8080` (LAN)
- Version at setup: Nextcloud 34.0.4.1

**Trusted-domains gotcha:** Nextcloud rejects any request whose Host header isn't in its `trusted_domains` config, showing an "Access through untrusted domain" page — this looks like a broken connection but is actually a security setting, and it's the first thing to check if Nextcloud "won't load" from some device but works from another. Currently trusted:
```
0 => '100.82.241.64:8080'
1 => '192.168.1.160:8080'
```
To add another (e.g. a future domain, or a different port):
```bash
docker exec -u www-data nextcloud php occ config:system:set trusted_domains <next_free_index> --value=<host:port>
```
Check the current list any time with:
```bash
docker exec nextcloud cat /var/www/html/config/config.php | grep -A6 trusted_domains
```

---

## `~/docker-apps/agelcom/` — Agelcom (gestion de boutique)

Django app for a grocery shop in Senegal — sales, stock and cash, designed to
work offline on an Android phone. Source lives at `~/Desktop/agelcom` on Cheikh's
laptop; there is no git remote, so the server copy is synced with rsync by
`deploy/push.sh` in that repo. The compose file and Dockerfile are part of the
app repo, so `~/docker-apps/agelcom/` is a full copy of the source tree.

### Database (`agelcom-db`)
- Image: `postgres:17-alpine`, container name `agelcom-db`
- On an `internal`-only Docker network — not reachable from the host or other stacks
- `POSTGRES_PASSWORD` was generated on the server and lives only in
  `~/docker-apps/agelcom/.env` (mode `600`)

### App (`agelcom`)
- Image built locally from the repo's `Dockerfile` (Python 3.12 + gunicorn, 3 workers)
- **No published host port** — the first service here to be reached purely
  through Caddy over the `web` network, rather than via a dedicated port
- `migrate` and `collectstatic` run from the container entrypoint at every start

### How it is reached
```
Browser --HTTPS--> tailscale serve --HTTP--> Caddy --HTTP--> gunicorn
          (TLS)      (on the host)           (:80)         (agelcom:8000)
```
- Address: **<https://lacrevetteserver.tail9991b1.ts.net>**
- The certificate is a genuine Let's Encrypt cert issued by Tailscale, so Chrome
  shows no warning. That matters here specifically: the app is a PWA and a
  service worker will not install without a valid certificate, which is why this
  app is not served over plain HTTP on the LAN like Nextcloud.
- `tailscale serve` renews the certificate on its own — nothing to diarise.
- Enabled with, once, on the server:
  ```bash
  sudo tailscale set --operator=$USER
  tailscale serve --bg --https=443 http://127.0.0.1:80
  tailscale serve status      # inspect
  ```
  This requires "HTTPS Certificates" to be enabled at
  <https://login.tailscale.com/admin/dns>.
- **Any device that needs the app must be on the tailnet** — including the
  shopkeeper's phone. There is no LAN-only fallback, by design.

**No authentication at all**, by explicit decision of the app's client: whoever
has the URL has the shop. Do not share the address beyond its intended users.

### Updating it
From `~/Desktop/agelcom` on the laptop:
```bash
./deploy/push.sh
```
Rebuilds the Tailwind CSS, rsyncs the source (excluding the server's `.env`),
rebuilds the image and restarts the container.

### Admin commands
```bash
cd ~/docker-apps/agelcom
docker compose logs -f app
docker compose exec app python manage.py import_products data/produits_demo.xlsx
docker compose exec -T db pg_dump -U agelcom agelcom | gzip > ~/backups/agelcom-$(date +%F).sql.gz
```

---

## `~/docker-apps/gymlog/` — GymLog (workout tracker)

Django app for tracking Cheikh's own gym sessions — routines, set-by-set logging,
progression and volume. A PWA installed on his Android phone, built to log a full
session with **no connection at all** (the gym has no signal and the server is
behind Tailscale anyway); sets queue in IndexedDB and sync when the phone gets
home. Source lives at `~/Desktop/gymlog` on Cheikh's laptop; there is no git
remote, so the server copy is synced with rsync by `deploy/push.sh` in that repo.

### Database (`gymlog-db`)
- Image: `postgres:17-alpine`, container name `gymlog-db`
- On an `internal`-only Docker network — not reachable from the host or other stacks
- `POSTGRES_PASSWORD` was generated on the server and lives only in
  `~/docker-apps/gymlog/.env` (mode `600`)
- Volume: `gymlog_db_data`

### App (`gymlog`)
- Image built locally from the repo's `Dockerfile` (Python 3.12 + gunicorn, 3 workers)
- **No published host port** — reached purely through Caddy over the `web` network
- `collectstatic` and `migrate` run from the container entrypoint at every start;
  the exercise library (85 exercises) is loaded by a data migration, so a fresh
  database is usable immediately
- The image's `HEALTHCHECK` reads its `Host` header out of `ALLOWED_HOSTS`. Do not
  hardcode `localhost` there: it is not a trusted host, so Django answers 400 and
  the container never goes healthy. This cost one rolled-back deploy.

### How it is reached
```
Phone --HTTPS--> tailscale serve --HTTP--> Caddy  --HTTP--> gunicorn
        (:8443)    (on the host)          (:81)           (gymlog:8000)
```
- Address: **<https://lacrevetteserver.tail9991b1.ts.net:8443>**
- **Why a port and not a hostname:** Tailscale issues one certificate per machine
  name, and Agelcom already holds `tailscale serve` on 443 for
  `lacrevetteserver.tail9991b1.ts.net`. A second app therefore either lives under
  a path prefix on the same origin — which would mean running Django under
  `FORCE_SCRIPT_NAME` and narrowing the service worker's scope — or takes its own
  HTTPS port. The port is the cheaper trade, and the same Let's Encrypt cert
  covers it, because a certificate is issued for a host, not a host:port.
- Enabled with, once:
  ```bash
  tailscale serve --bg --https=8443 http://127.0.0.1:81
  ```
  No ufw rule is needed: traffic arrives on `tailscale0`, which already allows
  every port, and reaches Caddy over loopback.
- **`PUBLIC_ORIGIN` gotcha:** Django's CSRF check compares scheme, host *and
  port*, so `CSRF_TRUSTED_ORIGINS` cannot be derived from `ALLOWED_HOSTS` the way
  Agelcom does it. `PUBLIC_ORIGIN=https://lacrevetteserver.tail9991b1.ts.net:8443`
  is a required env var; get it wrong and every POST answers 403 while GETs look
  perfectly fine.

**No authentication at all**, same as Agelcom: whoever is on the tailnet and has
the URL has the training log. It is personal data rather than a business's, so
the trade is Cheikh's own to make.

### Updating it
From `~/Desktop/gymlog` on the laptop:
```bash
just deploy      # or ./deploy/push.sh
```
Rebuilds the Tailwind CSS, rsyncs the source (excluding the server's `.env`), then
runs `deploy/release.sh deploy` **on the server**: snapshot, rebuild, wait for the
container health check, smoke-test `/train/` through Caddy, and roll back
automatically if either fails.

### Admin commands
```bash
cd ~/docker-apps/gymlog
docker compose logs -f app
docker compose exec app python manage.py seed_exercises          # new library entries
docker compose exec app python manage.py rebuild_exercise_stats  # recompute counters
docker compose exec -T db pg_dump -U gymlog gymlog | gzip > ~/backups/gymlog-$(date +%F).sql.gz
```

---

## Adding a new app
See `deployment-guide.md` in this same folder for the full step-by-step pattern.
