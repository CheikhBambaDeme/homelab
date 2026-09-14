#!/usr/bin/env bash
# Print the resolved configuration. Always exits 0.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
printf "%-22s %s\n" \
  "config file:"        "$HL_CONFIG_FILE ($([ -f "$HL_CONFIG_FILE" ] && echo present || echo absent))" \
  "ssh user:"           "$HOMELAB_SSH_USER" \
  "expected hostname:"  "$HOMELAB_HOSTNAME" \
  "LAN address:"        "$HOMELAB_LAN_HOST" \
  "Tailscale address:"  "$HOMELAB_TS_HOST" \
  "MagicDNS name:"      "$HOMELAB_TS_NAME" \
  "apps root:"          "$HOMELAB_APPS_ROOT" \
  "LAN subnet:"         "$HOMELAB_LAN_SUBNET" \
  "Caddyfile:"          "$HOMELAB_CADDYFILE" \
  "ssh key:"            "$HOMELAB_SSH_KEY ($([ -f "$HOMELAB_SSH_KEY" ] && echo present || echo absent))" \
  "docs repo:"          "$HOMELAB_DOCS_DIR"
exit 0
