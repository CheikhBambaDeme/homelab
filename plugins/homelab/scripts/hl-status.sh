#!/usr/bin/env bash
# Read-only snapshot of the server. Always exits 0 so it is safe to inject into
# a skill with !`...` — an unreachable server reports itself in the output
# rather than aborting the skill.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/config.sh"

if ! target=$(hl_target); then
  hl_unreachable_message
  exit 0
fi

echo "Connected to ${HOMELAB_HOSTNAME} via ${target}"
echo

"$HERE/hl-ssh.sh" '
echo "### Uptime / load"
uptime
echo
echo "### Disk"
df -h / | tail -n +1
echo
echo "### Memory"
free -h | head -2
echo
echo "### Docker context (must show * on default)"
docker context ls 2>&1 | sed "s/^/  /"
echo
echo "### Containers"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1
echo
echo "### Stopped / unhealthy containers"
docker ps -a --filter "status=exited" --filter "status=restarting" --format "  {{.Names}}\t{{.Status}}" 2>&1
echo
echo "### Compose projects under ~/docker-apps"
ls -1 ~/docker-apps 2>/dev/null | sed "s/^/  /"
echo
echo "### Listening TCP ports"
ss -tlnp 2>/dev/null | awk "NR>1 {print \$4}" | sort -u | sed "s/^/  /"
echo
echo "### ufw"
sudo -n ufw status 2>/dev/null || echo "  (needs sudo password — run: sudo ufw status verbose on the server)"
echo
echo "### Tailscale"
tailscale status 2>&1 | head -10
echo
echo "### tailscale serve"
tailscale serve status 2>&1 | head -20
' 2>&1
exit 0
