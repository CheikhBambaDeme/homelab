#!/usr/bin/env bash
# Which host ports are already taken on the server. Always exits 0.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/config.sh"

echo "Reserved by convention (see deployment-guide.md):"
echo "  22    SSH"
echo "  80    Caddy (HTTP)"
echo "  443   tailscale serve — NEVER publish this from Docker"
echo "  8080  Nextcloud"
echo "  9443  Portainer (Tailscale only)"
echo
if ! hl_target >/dev/null; then
  echo "(server unreachable — live port list unavailable)"
  hl_unreachable_message
  exit 0
fi
echo "Actually listening right now:"
"$HERE/hl-ssh.sh" '
ss -tlnH 2>/dev/null | awk "{print \$4}" | sed "s/.*://" | sort -n -u | tr "\n" " "
echo
echo
echo "Published by containers:"
docker ps --format "{{.Names}}\t{{.Ports}}" 2>&1
' 2>&1
exit 0
