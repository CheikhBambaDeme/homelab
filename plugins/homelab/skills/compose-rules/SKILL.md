---
name: compose-rules
description: Conventions for docker-compose.yml, Dockerfile and Caddyfile files that will run on the lacrevetteserver homelab. Loads automatically when editing those files.
paths:
  - "**/docker-compose.y*ml"
  - "**/compose.y*ml"
  - "**/Caddyfile"
  - "**/Dockerfile"
  - "**/deploy/**"
---

# Writing container config for lacrevetteserver

Apply these when the file is destined for that server. For a compose file that
only ever runs on a developer laptop, ignore them.

## docker-compose.yml

- **No `version:` key.** It has been obsolete since Compose v2 and only produces
  a warning.
- **Never publish host port 443.** `tailscale serve` owns it; publishing from
  Docker shadows the Tailscale interface and silently kills all HTTPS. There is
  a hook in this plugin that refuses such an edit.
- **Prefer publishing no host port at all.** Join the external `web` network and
  let Caddy reach the container by service name. A published port is only for
  something Caddy should not front.
- If a port is published, pick one outside 22 / 80 / 443 / 8080 / 9443 and add a
  matching ufw rule, or it will be reachable over Tailscale but not the LAN.
- **Two networks when there is a database**: the db joins an `internal` network
  only; the app joins both `internal` and `web`. The database must never be
  reachable from the host or another stack.

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

- `restart: unless-stopped` on everything — the host is a laptop that may reboot.
- Give containers explicit `container_name`s; Caddy and the docs refer to them.
- Secrets come from `.env` via `${VAR}` and are never written literally. The
  `.env` lives on the server at mode 600 and is excluded from every sync.
- Name the volume, don't bind-mount data into `~/docker-apps/<app>/` — the
  backup script finds volumes by Compose project label.

## Caddyfile

```
myapp.tail9991b1.ts.net:80 {
    reverse_proxy myapp:8000 {
        header_up X-Forwarded-Proto https
    }
}
```

- The `:80` suffix is required. A bare hostname makes Caddy try to obtain its
  own certificate, which it cannot do here.
- `header_up X-Forwarded-Proto https` is required for any app that enforces
  HTTPS, or it redirect-loops.
- Keep the trailing catch-all `:80 { respond ... }` block last.
- An edit is inert until `caddy reload`. Validate before reloading — a syntax
  error takes down every site, not just the new one.

## Dockerfile

- Pin base image minors (`python:3.12-slim`, `node:22-alpine`), not `latest`.
- The server has 4 cores and 15 GB RAM; a build that assumes a big CI machine
  will be slow. Build locally and push the image, or keep the build light.
- Run migrations and asset collection from the entrypoint so a restart is always
  self-healing.
- Bind to `0.0.0.0`, not `127.0.0.1`, or Caddy cannot reach the container.

## App settings

Whatever hostname the app is served at has to be in its own allowlist —
`ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` for Django, `trusted_domains` for
Nextcloud. Include the `https://` scheme in origin settings.
