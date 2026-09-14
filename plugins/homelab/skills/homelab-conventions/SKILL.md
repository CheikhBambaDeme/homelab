---
name: homelab-conventions
description: How the lacrevetteserver homelab is built, and the specific mistakes it punishes — addresses and SSH, the shared `web` Docker network, Caddy behind `tailscale serve` for TLS, ufw scoping, where secrets live. Use whenever work involves deploying, hosting, reverse-proxying, HTTPS, firewall rules or Docker on that server.
---

# lacrevetteserver: how this machine works

An old laptop running Ubuntu Desktop, hosting Docker services for personal and
family use. Nothing is exposed to the public internet, and there is no domain.

## Reaching it

| Path | Address | From |
|---|---|---|
| Home LAN | `192.168.1.160` | devices on the home Wi-Fi (`192.168.1.0/24`) |
| Tailscale | `100.82.241.64` | anywhere, for devices on the tailnet |
| MagicDNS | `lacrevetteserver.tail9991b1.ts.net` | anywhere on the tailnet, with real TLS |

Never run a command intended for the server on the local machine. Use
`"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh '<command>'`, which refuses to execute
anything unless `hostname` on the far end matches. Commands have landed on the
wrong machine on this setup before, which is why that wrapper exists.

Those scripts need key-based SSH; the server was set up with password auth only.
If they report that they cannot connect, run `/homelab:setup-ssh` once.

## Layout

- One folder per app under `~/docker-apps/<app>/`, each an independent Compose
  project. Tearing one down never touches another.
- A shared external Docker network named `web` lets Caddy reach any container by
  its service name. Apps needing a private backend get their own `internal`
  network as well, and only the web-facing service joins `web`.
- Secrets live in `~/docker-apps/<app>/.env` on the server, mode 600, generated
  there with `openssl rand -base64 24`. That file is the only copy — it is
  excluded from every rsync and is not in any repo.

## Two Docker contexts

`docker context ls` must show `*` on `default`. The leftover `desktop-linux`
context points at a socket that is not running; selecting it produces
"cannot connect to the Docker daemon" errors that look like Docker is broken.

## How TLS works here, and why it is easy to break

```
Browser --HTTPS--> tailscale serve --HTTP--> Caddy --HTTP--> app container
          (TLS)      (on the host)           (:80)          (name:port)
```

Tailscale issues and renews a genuine Let's Encrypt certificate for the
`*.ts.net` name. No domain, no port forwarding, no certificate to diarise.

Three rules follow from that, and each one has already caused a confusing outage:

1. **Nothing may publish host port 443.** Docker's `443:443` binds
   `0.0.0.0:443` and shadows the Tailscale interface. `tailscale serve`
   silently loses the port and every HTTPS connection dies in the TLS
   handshake, with no entry in any log. Caddy's own 443 publish was removed for
   this reason.
2. **Caddy site blocks are written `host:80`**, never bare `host`. A bare
   hostname makes Caddy try to provision its own certificate, which it cannot.
3. **`reverse_proxy` needs `header_up X-Forwarded-Proto https`.** Without it the
   backend thinks the connection was plain HTTP; any app that enforces HTTPS
   answers with a redirect, forever.

## Firewall

Default deny incoming. `tailscale0` is allowed on every port, so anything the
server listens on is automatically reachable over Tailscale. LAN access is not:
a newly published port needs its own rule.

```bash
sudo ufw allow from 192.168.1.0/24 to any port <PORT> proto tcp
```

Ports in use: 22 SSH, 80 Caddy, 443 `tailscale serve` (never Docker), 8080
Nextcloud, 9443 Portainer (Tailscale only). Apps routed through Caddy publish no
host port at all and need no rule.

## Apps have their own allowlists

Separate from the firewall, and the usual reason something loads from one device
but not another:

- Nextcloud rejects any `Host` header not in `trusted_domains`.
- Django needs the hostname in `ALLOWED_HOSTS`, and the `https://` origin in
  `CSRF_TRUSTED_ORIGINS`.

Check this before suspecting the network.

## What is running

Portainer (9443, Tailscale only), Caddy (80), Nextcloud (8080), and Agelcom —
a Django shop-management PWA at `https://lacrevetteserver.tail9991b1.ts.net`,
routed through Caddy with no published port. Agelcom has **no authentication at
all** by its client's decision, and holds a real business's sales, stock and
cash history.

## What this setup is fragile about

No off-machine backups, no UPS, Wi-Fi rather than Ethernet, and a LAN IP that is
probably DHCP-assigned. The backup gap is the pressing one because Agelcom's
database exists nowhere else — `/homelab:backup` addresses it. Treat data on
this server as unreplicated unless you have checked otherwise.
