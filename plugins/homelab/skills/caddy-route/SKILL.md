---
name: caddy-route
description: Add, change or remove a hostname route in the homelab's Caddy reverse proxy, then validate and reload it.
argument-hint: "[hostname] [container:port]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*)
---

# Caddy route: $ARGUMENTS

## Current Caddyfile

!`"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-caddy.sh show 2>&1 || true`

## Rules for editing it

- New blocks go **above** the trailing catch-all `:80 { respond ... }` block,
  which must stay last.
- Write the site address as `<hostname>:80`, never a bare hostname. TLS is
  terminated by `tailscale serve`; a bare hostname makes Caddy try to provision
  its own certificate and the site never comes up.
- Every `reverse_proxy` needs `header_up X-Forwarded-Proto https`, or an app that
  enforces HTTPS will redirect-loop.
- The upstream is the **container name** and its **internal** port
  (`myapp:8000`), reached over the `web` network — not a host port.
- The target container must be on the external `web` network, or Caddy cannot
  resolve the name. Check with
  `hl-ssh.sh 'docker network inspect web --format "{{range .Containers}}{{.Name}} {{end}}"'`.

## Procedure

1. Edit `~/docker-apps/caddy/Caddyfile` on the server. Take a copy first:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'cp ~/docker-apps/caddy/Caddyfile ~/docker-apps/caddy/Caddyfile.bak'
   ```
   Then write the new content, for example:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'cat > ~/docker-apps/caddy/Caddyfile' <<'EOF'
   ...full file...
   EOF
   ```
2. Validate and reload — validation first, because a syntax error takes down
   every site, not just the new one:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/scripts/hl-caddy.sh reload
   ```
3. If validation fails, restore the backup and reload before doing anything else.
4. Verify the route resolves:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh 'curl -sS -o /dev/null -w "%{http_code}\n" -H "Host: <hostname>" http://127.0.0.1/'
   ```

A route on a `*.ts.net` hostname is served over HTTPS automatically —
`tailscale serve` already forwards all of 443 to Caddy, so no new `serve`
command is needed.
