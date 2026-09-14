#!/usr/bin/env bash
# Can we reach the server without a password prompt? Always exits 0.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
echo "ssh key:   $HOMELAB_SSH_KEY ($([ -f "$HOMELAB_SSH_KEY" ] && echo present || echo 'not created yet'))"
echo "ssh user:  $HOMELAB_SSH_USER"
echo "addresses: $HOMELAB_LAN_HOST (LAN), $HOMELAB_TS_HOST (Tailscale)"
echo
if target=$(hl_target 2>/dev/null); then
  echo "Key-based SSH works, via $target, and the far end really is $HOMELAB_HOSTNAME."
  echo "Nothing to do."
else
  echo "Key-based SSH is not working yet — follow the steps below."
  echo
  hl_unreachable_message
fi
exit 0
