#!/usr/bin/env bash
# Single source of truth for how to reach the homelab server.
#
# Precedence, highest first:
#   1. HOMELAB_* environment variables already set in the shell
#   2. ~/.config/homelab/config.env      (written by /homelab:configure)
#   3. CLAUDE_PLUGIN_OPTION_* from the plugin's userConfig (hook processes only)
#   4. the built-in defaults below
#
# The config file must use the `: "${VAR:=value}"` form so it never clobbers an
# explicit environment override.

HL_CONFIG_FILE="${HOMELAB_CONFIG_FILE:-$HOME/.config/homelab/config.env}"
# shellcheck source=/dev/null
[ -f "$HL_CONFIG_FILE" ] && . "$HL_CONFIG_FILE"

: "${HOMELAB_SSH_USER:=${CLAUDE_PLUGIN_OPTION_ssh_user:-lacrevetteserver}}"
: "${HOMELAB_HOSTNAME:=${CLAUDE_PLUGIN_OPTION_hostname:-lacrevetteserver}}"
: "${HOMELAB_LAN_HOST:=${CLAUDE_PLUGIN_OPTION_lan_host:-192.168.1.160}}"
: "${HOMELAB_TS_HOST:=${CLAUDE_PLUGIN_OPTION_ts_host:-100.82.241.64}}"
: "${HOMELAB_TS_NAME:=${CLAUDE_PLUGIN_OPTION_ts_name:-lacrevetteserver.tail9991b1.ts.net}}"
: "${HOMELAB_APPS_ROOT:=${CLAUDE_PLUGIN_OPTION_apps_root:-~/docker-apps}}"
: "${HOMELAB_LAN_SUBNET:=${CLAUDE_PLUGIN_OPTION_lan_subnet:-192.168.1.0/24}}"
: "${HOMELAB_DOCS_DIR:=${CLAUDE_PLUGIN_OPTION_docs_dir:-$HOME/Desktop/homelab}}"
: "${HOMELAB_WEB_NETWORK:=web}"
: "${HOMELAB_CADDYFILE:=$HOMELAB_APPS_ROOT/caddy/Caddyfile}"
: "${HOMELAB_SSH_KEY:=$HOME/.ssh/id_ed25519_homelab}"
: "${HOMELAB_SSH_OPTS:=}"

HL_CACHE_DIR="${TMPDIR:-/tmp}/homelab-$(id -u)"
HL_TARGET_CACHE="$HL_CACHE_DIR/target"
HL_TARGET_TTL=600   # seconds

hl_ssh_base_opts() {
  printf '%s\n' \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -o LogLevel=ERROR
  [ -f "$HOMELAB_SSH_KEY" ] && printf '%s\n' -i "$HOMELAB_SSH_KEY"
  # shellcheck disable=SC2086
  [ -n "$HOMELAB_SSH_OPTS" ] && printf '%s\n' $HOMELAB_SSH_OPTS
  return 0
}

# Probe a single address. Succeeds only if SSH works AND the far end really is
# the homelab server.
hl_probe() {
  local host="$1" opts=()
  mapfile -t opts < <(hl_ssh_base_opts)
  ssh "${opts[@]}" "${HOMELAB_SSH_USER}@${host}" \
    "test \"\$(hostname)\" = '${HOMELAB_HOSTNAME}'" >/dev/null 2>&1
}

# Print the address to use, preferring the LAN (fast at home) and falling back
# to Tailscale (works from anywhere). Result is cached briefly so a skill that
# runs several commands doesn't re-probe each time.
hl_target() {
  if [ -n "${HOMELAB_HOST:-}" ]; then
    printf '%s\n' "$HOMELAB_HOST"
    return 0
  fi
  mkdir -p "$HL_CACHE_DIR" 2>/dev/null
  if [ -f "$HL_TARGET_CACHE" ]; then
    local age now mtime
    now=$(date +%s)
    mtime=$(date -r "$HL_TARGET_CACHE" +%s 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    if [ "$age" -lt "$HL_TARGET_TTL" ]; then
      cat "$HL_TARGET_CACHE"
      return 0
    fi
  fi
  local host
  for host in "$HOMELAB_LAN_HOST" "$HOMELAB_TS_HOST" "$HOMELAB_TS_NAME"; do
    [ -n "$host" ] || continue
    if hl_probe "$host"; then
      printf '%s\n' "$host" | tee "$HL_TARGET_CACHE"
      return 0
    fi
  done
  return 1
}

hl_unreachable_message() {
  cat <<MSG
Cannot reach ${HOMELAB_HOSTNAME} over SSH with key authentication.

Tried: ${HOMELAB_LAN_HOST} (LAN), ${HOMELAB_TS_HOST} (Tailscale), ${HOMELAB_TS_NAME}

Most likely causes, in order:
  1. Key-based SSH is not set up yet. These scripts run non-interactively and
     cannot type a password. Run /homelab:setup-ssh once to fix this.
  2. You are away from the home network and this device is not on the tailnet.
     Check with: tailscale status
  3. The server is off, asleep, or its LAN IP changed (it is DHCP-assigned).
MSG
}
