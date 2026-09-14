---
name: configure
description: Show or change which server this plugin talks to, and where its settings come from.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*)
---

# Homelab plugin configuration

## Current settings

!`"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-config.sh 2>&1 || true`

## How these resolve

Highest priority first:

1. `HOMELAB_*` environment variables set in the shell
2. `~/.config/homelab/config.env`
3. the plugin's `userConfig` values, editable in `/plugin` — these reach hook
   processes only, not the scripts
4. the built-in defaults

## Changing them

Write the file, using the `: "${VAR:=value}"` form so an explicit environment
variable still wins:

```bash
mkdir -p ~/.config/homelab
cat > ~/.config/homelab/config.env <<'EOF'
: "${HOMELAB_SSH_USER:=lacrevetteserver}"
: "${HOMELAB_HOSTNAME:=lacrevetteserver}"
: "${HOMELAB_LAN_HOST:=192.168.1.160}"
: "${HOMELAB_TS_HOST:=100.82.241.64}"
: "${HOMELAB_TS_NAME:=lacrevetteserver.tail9991b1.ts.net}"
: "${HOMELAB_APPS_ROOT:=~/docker-apps}"
: "${HOMELAB_LAN_SUBNET:=192.168.1.0/24}"
: "${HOMELAB_DOCS_DIR:=$HOME/Desktop/homelab}"
EOF
```

`HOMELAB_HOSTNAME` is the safety check: every remote command is refused unless
`hostname` on the far end matches it. Only change it when genuinely pointing at
a different machine.

To override for a single command without touching the file:

```bash
HOMELAB_HOST=100.82.241.64 "${CLAUDE_PLUGIN_ROOT}"/scripts/hl-status.sh
```

Then verify:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/hl-target.sh
```

## If the LAN address changed

It is DHCP-assigned. Find the new one from the router, or from a tailnet device
with `tailscale status`, update the file above, and also update Nextcloud's
`trusted_domains` and the homelab docs, which both hard-code the old address.
