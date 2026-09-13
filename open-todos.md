# Open items / known gaps

Check this list before assuming the server is in a fully finished state — these were identified during setup but not all were resolved.

## RESOLVED — sleep / lid-close behavior
Verified on `lacrevetteserver` itself on 2026-09-13 (previous check had been run on the wrong machine). The server is safe to keep lidded:
```
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
sleep.target suspend.target hibernate.target hybrid-sleep.target   -> all masked
org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type     -> 'nothing'
```
Nothing further to do. Re-check if the machine is ever reinstalled.

## No domain name yet
Everything is accessed by IP:port over Tailscale or the LAN. That's fine for personal/family use. It becomes a blocker the moment something needs to be publicly visible to people who don't have Tailscale installed (e.g. a portfolio site to share with anyone).

## Running on Wi-Fi, not Ethernet
`enp0s31f6` (the wired port) shows as down/unplugged; the server currently depends on Wi-Fi (`wlp1s0`). Wi-Fi is generally less reliable for a 24/7 server than a wired connection. Worth plugging in an Ethernet cable if one is reachable.

## LAN IP may not be static
`192.168.1.160` is presumably DHCP-assigned. If the router ever reassigns it, every LAN reference in this documentation (and Nextcloud's `trusted_domains` entry for it) goes stale. Consider a DHCP reservation for this machine's MAC address in the router's admin panel, or configuring a static IP directly on the server.

## RESOLVED — Caddy has a real route
Agelcom (deployed 2026-09-13) is routed by hostname through Caddy and served over real HTTPS via `tailscale serve`. Its Caddyfile block is the template for the next site — see `docker-services.md` and step 5 of `deployment-guide.md`. The placeholder `:80` block is kept deliberately as the catch-all.

## No backups configured — now actually urgent
Nextcloud's data volume was already unbacked. As of 2026-09-13 the server also holds **Agelcom's Postgres database, which is a real shop's sales, stock and cash history** — data that exists nowhere else and cannot be reconstructed. This is the most pressing open item on this list.

Minimum viable version, as a nightly cron:
```bash
docker compose -f ~/docker-apps/agelcom/docker-compose.yml exec -T db \
  pg_dump -U agelcom agelcom | gzip > ~/backups/agelcom-$(date +%F).sql.gz
docker run --rm -v nextcloud_data:/data -v ~/backups:/backup alpine \
  tar czf /backup/nextcloud-$(date +%F).tar.gz /data
```
Backups on the same disk as the data protect against software mistakes but not against the disk dying — getting a copy off this machine (external drive, or into Nextcloud-synced storage on another device) is the part that actually matters.

## Agelcom requires Tailscale on every device that uses it
Agelcom is served only at `https://lacrevetteserver.tail9991b1.ts.net`, which resolves only for devices on the tailnet. That is a deliberate trade: it buys a genuinely valid TLS certificate — which the app's offline mode requires — with no domain purchase and no ports forwarded. The cost is that the shopkeeper's phone must have the Tailscale app installed and stay logged in.

Worth being explicit about the wider fragility, since this is a real business's data and not a personal toy: the shop is in Senegal and the server is a laptop on home Wi-Fi here, with no backups, no UPS and a possibly-DHCP address. The app is built to work fully offline and sync later, which absorbs a lot of that, but an extended server outage still means no sync and no reports. If this becomes the shop's real day-to-day system rather than a trial, it deserves either a hosted deployment (the Railway path is still documented in the app's `DEPLOY.md`) or, at minimum, the backup item above being solved first.
