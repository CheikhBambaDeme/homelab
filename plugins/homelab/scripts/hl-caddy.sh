#!/usr/bin/env bash
# hl-caddy.sh show      — print the current Caddyfile
# hl-caddy.sh validate  — ask Caddy to parse the current file
# hl-caddy.sh reload    — reload without restarting the container
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/config.sh"

case "${1:-show}" in
  show)
    "$HERE/hl-ssh.sh" "cat ${HOMELAB_CADDYFILE}" 2>&1
    ;;
  validate)
    "$HERE/hl-ssh.sh" "docker exec caddy caddy validate --config /etc/caddy/Caddyfile" 2>&1
    ;;
  reload)
    "$HERE/hl-ssh.sh" "docker exec caddy caddy validate --config /etc/caddy/Caddyfile && docker exec caddy caddy reload --config /etc/caddy/Caddyfile && echo 'Caddy reloaded.'" 2>&1
    ;;
  *)
    echo "usage: hl-caddy.sh {show|validate|reload}" >&2
    exit 64
    ;;
esac
