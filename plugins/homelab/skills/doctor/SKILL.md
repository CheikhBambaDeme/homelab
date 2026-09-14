---
name: doctor
description: Diagnose a homelab problem — a site that will not load, a container that will not start, HTTPS failing, or an app reachable from one device but not another. Use when something on the lacrevetteserver homelab is broken.
argument-hint: "[app or symptom]"
allowed-tools: Bash(homelab:*)
---

# Diagnosing: $ARGUMENTS

!`homelab status 2>&1 || true`

## Work through this in order

Most failures on this server are one of a small set of known causes. Check them
before theorising.

### The site does not load at all

1. **Is the container up?** `Restarting` means the app is crashing — go to
   `/homelab:logs <app>`, not the network.
2. **Is it on the `web` network?** Caddy resolves upstreams by container name
   over `web`. A container that is not on it gives Caddy a DNS failure and a 502.
   `hl-ssh.sh 'docker network inspect web --format "{{range .Containers}}{{.Name}} {{end}}"'`
3. **Is there a Caddy route for that hostname?** `hl-caddy.sh show`. Requests for
   an unrouted hostname fall through to the catch-all `:80` block and return the
   "Caddy is running" placeholder — which is a routing miss, not a dead app.
4. **Did the Caddyfile get reloaded?** Edits are inert until reload.

### HTTPS fails but HTTP works

The single most likely cause: **something is publishing host port 443.** Docker
binding `0.0.0.0:443` shadows the Tailscale interface, `tailscale serve` silently
loses the port, and every TLS handshake dies with nothing in any log.

```bash
homelab ssh 'ss -tlnp | grep :443; docker ps --format "{{.Names}} {{.Ports}}" | grep 443; tailscale serve status'
```

Fix by removing the `443:443` publish from that compose file and bringing the
stack back up. Also confirm "HTTPS Certificates" is still enabled for the tailnet
at <https://login.tailscale.com/admin/dns>.

### Endless redirects, or "too many redirects"

The reverse-proxy block is missing `header_up X-Forwarded-Proto https`, so the
app thinks the browser connected over plain HTTP and redirects it to HTTPS,
which arrives as HTTP again. For Django, also check
`SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")`.

### Works on one device, not another

Almost always an application-level allowlist rather than the network:

- Nextcloud: `trusted_domains` — shows "Access through untrusted domain".
- Django: `ALLOWED_HOSTS` (400) and `CSRF_TRUSTED_ORIGINS` (form posts fail).

Second suspect: the LAN firewall. A newly published port is reachable over
Tailscale automatically but not from the LAN until a rule is added.

```bash
homelab ssh 'sudo ufw status verbose'
```

Third: the device is simply not on the tailnet. Anything on a `*.ts.net`
hostname resolves only for tailnet members — Agelcom has no LAN fallback by
design.

### Docker commands fail with "cannot connect to the daemon"

`docker context ls` must show `*` on `default`. The leftover `desktop-linux`
context points at a socket that is not running.

```bash
homelab ssh 'docker context use default && docker context ls'
```

### Nothing is reachable at all

Check the LAN address first — it is DHCP-assigned and may have changed. From a
device on the tailnet, `100.82.241.64` still works regardless. If Tailscale is
also silent, the laptop is off or has lost Wi-Fi.

## Finish

Say what was actually wrong, what you changed, and what is still unverified.
If it turned out to be a new failure mode, add it to `docker-services.md` or
`open-todos.md` so the next session starts ahead of where this one did.
