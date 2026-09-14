---
name: logs
description: Show recent logs for an app on the lacrevetteserver homelab. Use when investigating why a service on that server is failing, restarting, or returning errors.
argument-hint: "<app> [lines]"
allowed-tools: Bash(homelab:*)
---

# Logs for `$ARGUMENTS`

!`homelab logs $ARGUMENTS 2>&1 || true`

## Instructions

Read the output above and explain what is actually wrong, in order:

1. If it listed the available apps instead of logs, ask which one.
2. Identify the first real error, not the last line. A restart loop repeats the
   same failure — the interesting part is at the top of a cycle.
3. Map it to a cause. The usual ones on this server:
   - `connection refused` to a database — the db container is not healthy yet, or
     the app is on the wrong network. The db lives on `internal` only.
   - `DisallowedHost` / "untrusted domain" / CSRF origin failures — the app's own
     allowlist, not the network.
   - Endless redirects — the reverse proxy is missing
     `header_up X-Forwarded-Proto https`.
   - Permission errors on a volume — a UID mismatch between image and volume.
4. Propose the specific fix and, if it needs a file change, say which file.

To follow logs live instead, run on the server:
`cd ~/docker-apps/<app> && docker compose logs -f`
