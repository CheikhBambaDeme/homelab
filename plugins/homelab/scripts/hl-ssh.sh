#!/usr/bin/env bash
# Run a command on the homelab server, with a hostname guard.
#
#   hl-ssh.sh 'docker ps'
#   echo "$SOME_STDIN" | hl-ssh.sh 'cat > ~/docker-apps/foo/.env'
#
# The guard and the command run inside the *same* remote shell, so there is no
# window in which the connection could be to a different machine than the one
# that was checked. This exists because commands were once run against the wrong
# machine during this server's setup; see network-and-access.md.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if [ $# -eq 0 ]; then
  echo "usage: hl-ssh.sh <remote command>" >&2
  exit 64
fi

REMOTE_CMD="$*"

target=$(hl_target) || { hl_unreachable_message >&2; exit 69; }

opts=()
mapfile -t opts < <(hl_ssh_base_opts)

ssh "${opts[@]}" "${HOMELAB_SSH_USER}@${target}" \
  "if [ \"\$(hostname)\" != '${HOMELAB_HOSTNAME}' ]; then
     echo \"REFUSED: connected to \$(hostname), expected ${HOMELAB_HOSTNAME}\" >&2
     exit 99
   fi
   ${REMOTE_CMD}"
rc=$?
if [ $rc -eq 99 ]; then
  echo "Nothing was run. Check HOMELAB_HOSTNAME / the address being used." >&2
fi
exit $rc
