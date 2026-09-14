---
name: deploy
description: Deploy this project to the lacrevetteserver homelab for the first time.
argument-hint: "[app-name]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*)
---

# Deploy to lacrevetteserver

Take the project in the current directory from source to running on the homelab,
following the pattern every other app on that server already uses. App name:
`$ARGUMENTS` (if empty, propose one from the directory name and confirm it).

## Live server state

Ports and apps already there:

!`"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ports.sh 2>&1 || true`

Current Caddy routes:

!`"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-caddy.sh show 2>&1 || true`

If the section above says the server is unreachable, stop and resolve that
first — usually `/homelab:setup-ssh`, sometimes just not being on the tailnet.

## 1. Understand what is being deployed

Read the project before writing any config. Establish, and state back briefly:

- Language, framework, and how it is normally started.
- Whether it already has a `Dockerfile` and a compose file.
- The port the app listens on inside the container.
- Whether it needs a database, and which one.
- Whether it needs a **secure context** — a PWA or service worker, `getUserMedia`,
  WebAuthn, or notifications. This decides the exposure mode below.
- What configuration it reads from the environment, and which of those are
  secrets.
- Any host allowlist it enforces (`ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`,
  `trusted_domains`).

Confirm the app name is not already taken in the list above.

## 2. Choose how it will be reached

| Situation | Mode | Result |
|---|---|---|
| Needs real HTTPS (PWA, service worker, camera, WebAuthn) | Caddy behind `tailscale serve` | `https://<host>.tail9991b1.ts.net`, valid certificate, tailnet only |
| An ordinary web app or site | Caddy on port 80 | `http://192.168.1.160/` by hostname, no new port, no firewall rule |
| Something Caddy should not front (an admin UI, a non-HTTP service) | Dedicated published port | `http://192.168.1.160:<port>`, needs a ufw rule |

Default to Caddy. Pick a dedicated port only with a reason. State which mode you
chose and why before continuing.

`tailscale serve` is already bound to 443 and forwards to Caddy on 127.0.0.1:80,
so the HTTPS mode needs no new `tailscale serve` command — only a Caddy route on
a `*.ts.net` hostname. Check with `hl-ssh.sh 'tailscale serve status'` if unsure.

## 3. Write the container config

Follow [compose-rules](../compose-rules/SKILL.md); full worked examples are in
[reference.md](reference.md). In short: no `version:` key, no published port
unless the mode calls for one, never host port 443, `restart: unless-stopped`,
database on an `internal` network only, secrets through `${VAR}` from `.env`.

Write these into the project repo (not only on the server) so the deployment is
reproducible: `Dockerfile`, `docker-compose.yml`, `.dockerignore`, and add
`.env` to `.gitignore`.

## 4. Create the app directory and its secrets on the server

Secrets are generated on the server and stay there. Do not write them into any
local file, and do not echo them back in full.

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'mkdir -p ~/docker-apps/<app>'
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'cd ~/docker-apps/<app> && \
  { echo "POSTGRES_PASSWORD=$(openssl rand -base64 24)"; \
    echo "SECRET_KEY=$(openssl rand -base64 48)"; } > .env && chmod 600 .env && ls -l .env'
```

Add whatever other non-secret environment the app needs to that same file.

## 5. Push the source

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-push.sh . <app>
```

This rsyncs the working directory to `~/docker-apps/<app>/`, excluding `.git`,
`.env`, `node_modules`, `__pycache__` and `.venv`. The remote `.env` is never
overwritten.

## 6. Add the Caddy route (Caddy modes only)

Append a block to `~/docker-apps/caddy/Caddyfile` **above** the trailing
catch-all `:80` block, then validate and reload:

```
<hostname>:80 {
    reverse_proxy <container-name>:<port> {
        header_up X-Forwarded-Proto https
    }
}
```

The `:80` and the `X-Forwarded-Proto` line are both required — see
[reference.md](reference.md) for why each one bites. Then:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-caddy.sh reload
```

`/homelab:caddy-route` does this edit-validate-reload cycle for you.

## 7. Open the firewall (dedicated-port mode only)

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'sudo ufw allow from 192.168.1.0/24 to any port <PORT> proto tcp'
```

Tailscale access already works without this; the rule is only for the LAN. It
needs a sudo password, so expect to run it in a terminal yourself.

## 8. Bring it up

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'cd ~/docker-apps/<app> && docker compose up -d --build && docker compose ps'
```

Then check the logs actually show a clean start rather than a restart loop:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-logs.sh <app> 50
```

## 9. Verify properly

A deployment is not done until both paths are checked — they are gated by
different rules and it is easy to leave one broken.

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'curl -sS -o /dev/null -w "%{http_code}\n" -H "Host: <hostname>" http://127.0.0.1/'
curl -sS -o /dev/null -w "%{http_code}\n" http://192.168.1.160/ -H "Host: <hostname>"   # LAN
curl -sS -o /dev/null -w "%{http_code}\n" https://<host>.tail9991b1.ts.net/             # Tailscale + TLS
```

A 400 or a redirect loop here is almost always the app's own allowlist, not the
network. Add the hostname to `ALLOWED_HOSTS` / `CSRF_TRUSTED_ORIGINS` (with the
`https://` scheme) and restart. `/homelab:doctor` walks the rest.

## 10. Leave the project able to update itself

Write `deploy/push.sh` into the project so future updates are one command —
copy `${CLAUDE_PLUGIN_ROOT}/templates/push.sh` and adjust the app name. This
matches how Agelcom is updated. `/homelab:redeploy` uses it if present.

## 11. Record it

Update the homelab documentation so the next session starts from fact rather
than discovery. In `$HOMELAB_DOCS_DIR` (default `~/Desktop/homelab`):

- `docker-services.md`: a section for the app — what it is, its containers,
  networks, how it is reached, how to update it, admin commands.
- `deployment-guide.md`: add the port to the table **only** if a dedicated port
  was used.
- `open-todos.md`: anything left unresolved, especially if the app holds data
  that is not backed up.

Then report: the URL, the exposure mode, which host ports were taken, and
anything a person still has to do by hand.
