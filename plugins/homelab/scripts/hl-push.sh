#!/usr/bin/env bash
# Sync a local project directory to ~/docker-apps/<app>/ on the server.
#
#   hl-push.sh <local-dir> <app-name> [extra rsync args...]
#
# The remote .env is never overwritten: secrets are generated on the server and
# exist nowhere else.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

SRC="${1:?usage: hl-push.sh <local-dir> <app-name>}"
APP="${2:?usage: hl-push.sh <local-dir> <app-name>}"
shift 2

[ -d "$SRC" ] || { echo "No such directory: $SRC" >&2; exit 66; }

target=$(hl_target) || { hl_unreachable_message >&2; exit 69; }

# Confirm the far end is the right machine before shipping anything to it.
"$(dirname "${BASH_SOURCE[0]}")/hl-ssh.sh" "mkdir -p ${HOMELAB_APPS_ROOT}/${APP}" || exit $?

opts=()
mapfile -t opts < <(hl_ssh_base_opts)
ssh_cmd="ssh"
for o in "${opts[@]}"; do ssh_cmd+=" $(printf '%q' "$o")"; done

rsync -az --delete \
  --exclude '.git/' \
  --exclude '.env' \
  --exclude '__pycache__/' \
  --exclude 'node_modules/' \
  --exclude '*.pyc' \
  --exclude '.venv/' \
  -e "$ssh_cmd" \
  "$@" \
  "${SRC%/}/" "${HOMELAB_SSH_USER}@${target}:${HOMELAB_APPS_ROOT#\~/}/${APP}/"
