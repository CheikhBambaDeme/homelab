#!/usr/bin/env bash
# deploy/push.sh — update this app on lacrevetteserver.
#
# Copy into the project, set APP, and add any build step the app needs before
# the sync (Tailwind, a frontend bundle, generated assets).
set -euo pipefail

APP="${APP:-CHANGE-ME}"
SSH_USER="${HOMELAB_SSH_USER:-lacrevetteserver}"
EXPECTED_HOST="${HOMELAB_HOSTNAME:-lacrevetteserver}"
LAN_HOST="${HOMELAB_LAN_HOST:-192.168.1.160}"
TS_HOST="${HOMELAB_TS_HOST:-100.82.241.64}"
APPS_ROOT="docker-apps"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
[ -f "$HOME/.ssh/id_ed25519_homelab" ] && SSH_OPTS+=(-i "$HOME/.ssh/id_ed25519_homelab")

# Pick whichever address answers, and confirm it is the right machine.
TARGET=""
for h in "$LAN_HOST" "$TS_HOST"; do
  if ssh "${SSH_OPTS[@]}" "$SSH_USER@$h" "test \"\$(hostname)\" = '$EXPECTED_HOST'" 2>/dev/null; then
    TARGET="$h"; break
  fi
done
[ -n "$TARGET" ] || { echo "Cannot reach $EXPECTED_HOST with key auth (tried $LAN_HOST, $TS_HOST)." >&2; exit 1; }
echo "==> $EXPECTED_HOST via $TARGET"

# --- build steps, if any ----------------------------------------------------
# npm run build
# ---------------------------------------------------------------------------

echo "==> syncing source"
rsync -az --delete \
  --exclude '.git/' --exclude '.env' --exclude 'node_modules/' \
  --exclude '__pycache__/' --exclude '*.pyc' --exclude '.venv/' \
  -e "ssh ${SSH_OPTS[*]}" \
  ./ "$SSH_USER@$TARGET:$APPS_ROOT/$APP/"

echo "==> rebuilding and restarting"
ssh "${SSH_OPTS[@]}" "$SSH_USER@$TARGET" \
  "test \"\$(hostname)\" = '$EXPECTED_HOST' || exit 99
   cd ~/$APPS_ROOT/$APP && docker compose up -d --build && docker compose ps"

echo "==> done"
