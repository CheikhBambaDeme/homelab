#!/usr/bin/env bash
# SessionStart: a few lines of orientation. Kept deliberately small — the detail
# lives in the homelab-conventions skill, which loads only when it is relevant.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../config.sh" 2>/dev/null || true

cat <<CTX
<homelab-plugin>
Deployment target available: ${HOMELAB_HOSTNAME:-lacrevetteserver} (${HOMELAB_LAN_HOST:-192.168.1.160} on the LAN, ${HOMELAB_TS_HOST:-100.82.241.64} over Tailscale).
Skills: /homelab:deploy /homelab:redeploy /homelab:status /homelab:logs /homelab:caddy-route /homelab:backup /homelab:doctor /homelab:teardown.
Never run docker/ufw/tailscale commands for that server locally — use "\${CLAUDE_PLUGIN_ROOT}"/scripts/hl-ssh.sh, which verifies the far-end hostname first.
Never publish host port 443 from Docker on that server; tailscale serve owns it.
</homelab-plugin>
CTX
