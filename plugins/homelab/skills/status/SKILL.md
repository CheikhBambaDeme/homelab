---
name: status
description: Show what is running on the lacrevetteserver homelab — containers, disk, listening ports, firewall, Tailscale and Caddy. Use when asked what is running on that server, whether it is up, or what state it is in.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*)
---

# Homelab status

!`"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-status.sh 2>&1 || true`

## Reading this

Summarise it for the person rather than repeating it. Call out anything that
needs attention:

- A container in `Restarting` or `Exited` — the app is down. `/homelab:logs <app>`.
- `docker context ls` without `*` on `default` — every Docker command will fail
  confusingly until that is fixed.
- Disk above ~85% — Docker images and backups are the usual culprits.
- Something listening on `0.0.0.0:443` — that shadows `tailscale serve` and has
  already silently killed all HTTPS on this server once.
- `tailscale serve status` empty — HTTPS is down for every `*.ts.net` site.
- A published port with no matching ufw rule — reachable over Tailscale, invisible
  from the LAN.

If the server is unreachable, say which addresses were tried and what the likely
cause is rather than guessing at the app level.
