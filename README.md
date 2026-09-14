# Homelab Documentation

This folder documents Cheikh's home server (`lacrevetteserver`) — an old laptop repurposed to host files, apps, and web services. It's written so an AI assistant (or future Cheikh) can pick up a deployment task with full context, without re-discovering the setup from scratch.

Last updated: 2026-09-14

## Files in this folder
- `network-and-access.md` — how to reach the server (SSH, Tailscale, LAN), current firewall rules
- `docker-services.md` — every service currently running: what it is, how it's configured, how to reach it
- `deployment-guide.md` — the standard step-by-step pattern for adding a new app/site to this server
- `open-todos.md` — known gaps and unfinished items, worth checking before assuming something works

## Quick facts
- Server hostname: `lacrevetteserver`
- Reachable at: `192.168.1.160` (home LAN only) or `100.82.241.64` (Tailscale — from anywhere, once a device is logged into Tailscale)
- SSH: `ssh lacrevetteserver@192.168.1.160` — key auth works from Cheikh's laptop
  (one entry in the server's `authorized_keys`), so deploy scripts can run
  unattended. Password auth is still enabled as the fallback.
- OS: Ubuntu 26.04.1 LTS ("Resolute Raccoon"), kernel 7.0.0-31-generic, x86_64
- Hardware: 4 CPU cores, 15 GB RAM, ~422 GB free disk (of 468 GB total)
- It's a laptop running Ubuntu **Desktop** (not Server) — GNOME and other desktop services are still installed and untouched; they're just not used for hosting
- Connects over home Wi-Fi (`wlp1s0`); the Ethernet port (`enp0s31f6`) exists but is unplugged/down
- Docker (v29.8.0) was already installed on this machine before any of this setup began
- No domain name owned yet — nothing here is exposed to the public internet

## Philosophy of the setup
- Nothing is port-forwarded on the router. All remote access goes through **Tailscale**, a private mesh VPN — no public exposure, no dynamic DNS, no domain required just to reach things yourself from anywhere.
- The `ufw` firewall denies all incoming traffic by default; explicit rules allow specific ports, scoped to either the home LAN subnet or the Tailscale interface.
- Every app lives in its own folder under `~/docker-apps/<app>/` on the server as an independent Docker Compose project — isolated, easy to inspect, easy to tear down.
- A shared external Docker network called `web` lets any container be reverse-proxied through Caddy without extra networking work.
- Where an app needs a certificate a browser genuinely trusts (a PWA, anything needing a secure context), `tailscale serve` terminates TLS in front of Caddy using a real Let's Encrypt cert for the machine's `*.ts.net` name — still no domain, still no ports forwarded. Agelcom is the worked example.
- Tailscale issues **one certificate per machine name**, so a second app that also needs real HTTPS cannot have its own hostname. It gets its own *port* instead: GymLog is served on `:8443`, terminating on a second Caddy listener on host port 81. The certificate is the same one — a cert covers a host, not a port. See `docker-services.md`.

## What is running
Portainer, Caddy, Nextcloud, **Agelcom** (a Django shop-management app, deployed 2026-09-13, at <https://lacrevetteserver.tail9991b1.ts.net>) and **GymLog** (Cheikh's own workout tracker, deployed 2026-09-14, at <https://lacrevetteserver.tail9991b1.ts.net:8443>).

Agelcom holds a real business's data and is the reason the "no backups" item in `open-todos.md` is the most pressing thing on this server. GymLog now adds a second Postgres database to that same gap.

Read the other files in this folder before deploying anything new — especially `deployment-guide.md` and `open-todos.md`.
