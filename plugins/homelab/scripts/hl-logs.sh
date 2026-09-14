#!/usr/bin/env bash
# hl-logs.sh <app> [lines]   — tail of a Compose project's logs. Always exits 0.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/config.sh"

APP="${1:-}"
LINES="${2:-100}"

if [ -z "$APP" ]; then
  echo "Apps on the server:"
  "$HERE/hl-ssh.sh" "ls -1 ${HOMELAB_APPS_ROOT} 2>/dev/null" 2>&1 | sed 's/^/  /'
  echo
  echo "usage: hl-logs.sh <app> [lines]"
  exit 0
fi

"$HERE/hl-ssh.sh" "
if [ -f ${HOMELAB_APPS_ROOT}/${APP}/docker-compose.yml ] || [ -f ${HOMELAB_APPS_ROOT}/${APP}/compose.yml ]; then
  cd ${HOMELAB_APPS_ROOT}/${APP} && docker compose ps && echo && docker compose logs --tail=${LINES} --no-color
else
  echo 'No compose project at ${HOMELAB_APPS_ROOT}/${APP} — falling back to container logs'
  docker logs --tail=${LINES} ${APP} 2>&1
fi
" 2>&1
exit 0
