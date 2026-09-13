# How to deploy a new app or site on this server

This is the standard pattern used for everything on this server so far (Portainer, Caddy, Nextcloud). Follow it so a new AI session — or future Cheikh — deploys consistently with what's already there.

1. **SSH into the server and confirm you're on it**
   ```bash
   ssh lacrevetteserver@192.168.1.160
   hostname   # must print "lacrevetteserver" — don't skip this check
   ```

2. **Create a folder for the app**
   ```bash
   mkdir -p ~/docker-apps/<app-name>
   cd ~/docker-apps/<app-name>
   ```

3. **Check the Docker context is correct** (only strictly needed if something seems broken):
   ```bash
   docker context ls   # "default" should have the *
   ```

4. **Write a `docker-compose.yml`** for the app.
   - Join the external `web` network if it should sit behind Caddy, or needs to reach another `web`-attached service:
     ```yaml
     networks:
       web:
         external: true
     ```
   - If the app needs a database or other private backend, give the stack its own internal network too (see `~/docker-apps/nextcloud/docker-compose.yml` as a template — `db` and `app` share an `internal` network, only `app` also joins `web`).
   - Put secrets (passwords, API keys) in a `.env` file in the same folder, `chmod 600` it, and reference values with `${VAR}` in the compose file — never hardcode secrets directly in `docker-compose.yml`. Generate random secrets with `openssl rand -base64 24` rather than choosing them by hand.

5. **Decide how the app will be reached:**
   - **Via Caddy (recommended for actual websites/apps you want under a clean address):** add a route to `~/docker-apps/caddy/Caddyfile` pointing at the container's internal port — Caddy reaches other containers by their Docker container/service name over the `web` network. Then reload:
     ```bash
     docker exec caddy caddy reload --config /etc/caddy/Caddyfile
     ```
     The app then needs **no published port and no ufw rule at all** — Agelcom is the worked example; see `docker-services.md`.
   - **Via Caddy behind `tailscale serve`, when the app needs real HTTPS:** anything that must be a secure context (PWAs and service workers, `getUserMedia`, WebAuthn) needs a certificate a browser actually trusts, which a self-signed one is not. Tailscale will issue a genuine Let's Encrypt cert for the machine's `*.ts.net` name and renew it itself, with no domain purchase and no ports forwarded:
     ```bash
     sudo tailscale set --operator=$USER        # once per machine
     tailscale serve --bg --https=443 http://127.0.0.1:80
     ```
     Requires "HTTPS Certificates" enabled at <https://login.tailscale.com/admin/dns>, and `sudo tailscale set --operator=$USER` once per machine. **Nothing else may publish host port 443** — Docker's `443:443` binds `0.0.0.0:443` and shadows the Tailscale interface, so `tailscale serve` silently loses the port and every HTTPS connection dies in the TLS handshake with no log entry anywhere. Caddy's 443 publish was removed for exactly this reason. Two things must then be right in the Caddyfile, or the app breaks in confusing ways — write the site block as `host:80` so Caddy does not try to get its own certificate, and add `header_up X-Forwarded-Proto https` to the `reverse_proxy` so the backend knows the browser's connection really was HTTPS. Skipping the second one gives an infinite redirect loop on any app that enforces HTTPS. Copy Agelcom's block as the template.
   - **Via a dedicated published port (simple, used so far for Nextcloud and Portainer):** publish a host port in the compose file (`ports: ["XXXX:internal_port"]`). Pick a port not already in use — see the table in this file.

6. **If using a dedicated port, open it on the LAN firewall** (Caddy-routed apps don't need this since port 80 is already open, and Tailscale-served ones need nothing at all):
   ```bash
   sudo ufw allow from 192.168.1.0/24 to any port <PORT> proto tcp
   ```
   Tailscale access to the new port works automatically — the `tailscale0` firewall rule already allows every port over that interface. This step only affects LAN reachability.

7. **Bring it up and check it started cleanly:**
   ```bash
   docker compose up -d
   docker compose ps
   ```

8. **Check for the app's own access restrictions**, separate from the OS firewall. Some apps maintain their own allow-list of hostnames/IPs (Nextcloud's `trusted_domains` is the known example here — see `docker-services.md`). If something loads on one device/address but not another, this is the first thing to check, not the network.

9. **Test from both the LAN (`192.168.1.160`) and Tailscale (`100.82.241.64`)** before considering the deployment done — they're gated by different firewall rules and are easy to accidentally leave one broken.

## Current port usage (don't reuse these)
| Port | Service |
|---|---|
| 22 | SSH |
| 80 | Caddy (HTTP) |
| 443 | `tailscale serve` (HTTPS termination, Tailscale interface only) — **not** Caddy |
| 8080 | Nextcloud |
| 9443 | Portainer (Tailscale-only, not on LAN) |

Update this table whenever a new dedicated port is used.

Apps routed through Caddy do not appear here — they have no host port of their own. Agelcom is the first of those.
