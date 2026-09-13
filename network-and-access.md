# Network & Access

## Addresses
| Network | Address | Reachable from |
|---|---|---|
| Home LAN | `192.168.1.160` | Any device on the same home Wi-Fi (subnet `192.168.1.0/24`) |
| Tailscale | `100.82.241.64` | Any device logged into the same Tailscale account, from anywhere with internet |

Router gateway: `192.168.1.254`

## SSH
```
ssh lacrevetteserver@192.168.1.160
```
Password auth — no SSH key set up yet. Reachable from the home LAN and, since the Tailscale interface allows all ports (see below), also over Tailscale using the same command against `100.82.241.64` if ever needed while away from home (SSH config would need `Host` set to that IP, or just `ssh lacrevetteserver@100.82.241.64`).

**Always verify you're on the right machine before making changes** — run `hostname` and confirm it prints `lacrevetteserver`. Earlier in this server's setup, commands were accidentally run on Cheikh's personal computer instead, because both machines' terminals looked similar. Don't assume; check.

## Tailscale
- Installed via `curl -fsSL https://tailscale.com/install.sh | sh` then `sudo tailscale up`
- Logged into the account `bamba.deme00@...` (Cheikh's Tailscale account)
- To let a new device (phone, another laptop) reach this server: install the Tailscale app on it and log into the same account. It will then be able to reach `100.82.241.64` directly, from anywhere, no extra configuration.
- Useful commands: `tailscale status`, `tailscale ip -4`

### Tailscale HTTPS (`tailscale serve`)
Tailscale can issue a real, browser-trusted Let's Encrypt certificate for this machine's MagicDNS name (`lacrevetteserver.tail9991b1.ts.net`) and renew it automatically — no domain purchase, no port forwarding. It is used to put Agelcom behind proper HTTPS; see `docker-services.md`.

Requires "HTTPS Certificates" to be enabled once for the tailnet at <https://login.tailscale.com/admin/dns>, and `tailscale cert`/`serve` need root unless the operator is set:
```bash
sudo tailscale set --operator=$USER        # once per machine
tailscale serve --bg --https=443 http://127.0.0.1:80
tailscale serve status
```
`tailscale serve` listens on the `tailscale0` interface only, which the existing blanket ufw rule already allows — no new firewall rule is needed, and it stays invisible from the LAN and the internet.

## Firewall (ufw)
Default policy: **deny incoming, allow outgoing**.

Current rules:
```
Anywhere on tailscale0       ALLOW IN   Anywhere        # ALL ports/protocols open over Tailscale
22/tcp                       ALLOW IN   192.168.1.0/24  # SSH from home LAN
80/tcp                       ALLOW IN   192.168.1.0/24  # HTTP (Caddy) from home LAN
443/tcp                      ALLOW IN   192.168.1.0/24  # HTTPS from home LAN — currently unused, see note
8080/tcp                     ALLOW IN   192.168.1.0/24  # Nextcloud from home LAN
Anywhere (v6) on tailscale0  ALLOW IN   Anywhere (v6)
```

The `443/tcp` LAN rule is now vestigial: nothing listens on 443 over the LAN. HTTPS is terminated by `tailscale serve`, which binds 443 on the `tailscale0` interface only. The rule is harmless and left in place in case Caddy ever terminates TLS again.

**Important nuance for future deployments:** any *new* port a future app publishes is automatically reachable over Tailscale (the `tailscale0` rule allows everything on that interface), but will **not** be reachable from the home LAN until you explicitly add a rule:
```bash
sudo ufw allow from 192.168.1.0/24 to any port <PORT> proto tcp
```
Check current state any time with `sudo ufw status verbose`.

## No public/internet exposure (by design)
- No domain name is owned.
- No ports are forwarded on the router.
- Nothing on this server is reachable from the open internet — only via Tailscale or the home LAN.
- If a future project needs to be public (e.g. a portfolio site anyone can visit without installing Tailscale), that requires: buying a domain, forwarding ports 80/443 on the router to this server, and getting the domain a real TLS certificate (Caddy can do this automatically via Let's Encrypt once the domain is live and pointed here).
