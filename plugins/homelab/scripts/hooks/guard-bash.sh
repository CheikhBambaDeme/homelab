#!/usr/bin/env bash
# PreToolUse guard for the homelab plugin.
#
# Denies the handful of actions that are known to break this specific server or
# destroy data that exists nowhere else, and adds a note when a server-shaped
# command looks like it is about to run on the local machine instead.
#
# Everything here is either documented in the homelab notes as having already
# gone wrong once, or is irreversible. It deliberately does not try to be a
# general-purpose safety net.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0   # no jq: stay out of the way

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

case "$tool" in
  Bash)
    text="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" ;;
  Write)
    text="$(printf '%s' "$input" | jq -r '(.tool_input.file_path // "") + "\n" + (.tool_input.content // "")')" ;;
  Edit|MultiEdit)
    text="$(printf '%s' "$input" | jq -r '(.tool_input.file_path // "") + "\n" + (.tool_input.new_string // "") + "\n" + ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))')" ;;
  *)
    exit 0 ;;
esac

[ -n "$text" ] || exit 0

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

note() {
  jq -n --arg m "$1" '{ systemMessage: $m }'
  exit 0
}

lc="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

# --- 1. Publishing host port 443 -------------------------------------------
# Docker publishing 443 binds 0.0.0.0:443, which shadows the Tailscale
# interface. `tailscale serve` then silently loses the port and every HTTPS
# connection dies in the TLS handshake with nothing in any log. This cost a
# debugging session during the Agelcom deployment.
if printf '%s' "$lc" | grep -Eq '(-p|--publish)[[:space:]=]*["'"'"']?([0-9.]+:)?443:' \
   || printf '%s' "$lc" | grep -Eq '^[[:space:]]*-[[:space:]]*["'"'"']?([0-9.]+:)?443:[0-9]' \
   || printf '%s' "$lc" | grep -q '443:443'; then
  deny "Refusing to publish host port 443.

On this server TLS is terminated by \`tailscale serve\`, which binds 443 on the tailscale0 interface. Docker publishing 443 binds 0.0.0.0:443, shadows it, and every HTTPS connection then fails in the TLS handshake with no error in any log.

Instead: publish nothing, put the app behind Caddy on port 80, and let tailscale serve handle HTTPS. See /homelab:conventions or run /homelab:doctor.

If you genuinely intend to move TLS termination to Caddy, move \`tailscale serve\` to another port first, and run the command yourself."
fi

# --- 2. Irreversible data loss ---------------------------------------------
if printf '%s' "$lc" | grep -Eq 'docker[ -]compose[^|;&]*\bdown\b[^|;&]*(-v|--volumes)'; then
  deny "Refusing \`docker compose down -v\`. That deletes the stack's named volumes, which on this server means a database that exists nowhere else (Agelcom holds a real shop's sales and stock history, and off-machine backups are still an open item).

Use \`docker compose down\` without -v to stop the stack, and take a dump first with /homelab:backup if you really need to wipe state."
fi

if printf '%s' "$lc" | grep -Eq 'docker[[:space:]]+volume[[:space:]]+(rm|prune)'; then
  deny "Refusing to remove Docker volumes — this server's volumes hold Nextcloud files and the Agelcom database, neither of which is backed up off-machine yet.

Run /homelab:backup first, then remove the volume manually if it is still what you want."
fi

if printf '%s' "$lc" | grep -Eq 'docker[[:space:]]+system[[:space:]]+prune[^|;&]*--volumes'; then
  deny "Refusing \`docker system prune --volumes\` — it deletes unused volumes, and 'unused' includes any volume whose stack is merely stopped. Drop --volumes, or run it yourself after a backup."
fi

if printf '%s' "$lc" | grep -Eq 'rm[[:space:]]+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)[^|;&]*(docker-apps|/backups)'; then
  deny "Refusing a recursive delete under docker-apps or backups. Those directories hold the compose projects, their .env files (the only copy of every generated secret) and the backups themselves.

Use /homelab:teardown to remove a single app cleanly."
fi

# --- 3. Cutting off your own access ----------------------------------------
if printf '%s' "$lc" | grep -Eq '\bufw[[:space:]]+(disable|--force[[:space:]]+reset|reset)\b'; then
  deny "Refusing to disable or reset ufw. Its default is deny-incoming with a small set of scoped allow rules; resetting drops them all, including SSH from the LAN, and the blanket allow on tailscale0.

To change one rule, add or delete just that rule."
fi

if printf '%s' "$lc" | grep -Eq '\btailscale[[:space:]]+(down|logout)\b'; then
  deny "Refusing \`tailscale $(printf '%s' "$lc" | grep -oE 'tailscale[[:space:]]+(down|logout)' | awk '{print $2}')\`. Tailscale is the only way this server is reachable when you are not on the home LAN, and the only way Agelcom is reachable at all.

If you are on the LAN and certain, run it yourself."
fi

if printf '%s' "$lc" | grep -Eq '\btailscale[[:space:]]+serve[^|;&]*(reset|--https=443[[:space:]]+off|off)'; then
  deny "Refusing to tear down \`tailscale serve\`. It terminates TLS for https://${HOMELAB_TS_NAME:-lacrevetteserver.tail9991b1.ts.net}; removing it takes Agelcom offline, and its PWA service worker will not reinstall without a valid certificate.

Check the current state first with: tailscale serve status"
fi

# --- 4. Right machine? ------------------------------------------------------
# Commands that only make sense on the server, not wrapped in ssh. Commands were
# once run against the wrong machine during this server's setup; see
# network-and-access.md.
via_remote() {
  printf '%s' "$lc" | grep -Eq '(^|[|;&(`$[:space:]/])(ssh|hl-ssh\.sh|scp|rsync|homelab)([[:space:]]|$)'
}
server_shaped() {
  # A compose/docker action against the server's app directory, or a command
  # that only ever makes sense on the server itself.
  { printf '%s' "$lc" | grep -q 'docker-apps' \
      && printf '%s' "$lc" | grep -Eq '(^|[|;&[:space:]])(docker[[:space:]]|compose|cd[[:space:]]|cat[[:space:]]*>|tee[[:space:]])'; } \
  || printf '%s' "$lc" | grep -Eq '(^|[|;&[:space:]])(sudo[[:space:]]+)?ufw[[:space:]]' \
  || printf '%s' "$lc" | grep -Eq 'tailscale[[:space:]]+serve'
}

if [ "$tool" = "Bash" ] && ! via_remote && server_shaped; then
  note "This command looks like it is meant for ${HOMELAB_HOSTNAME:-lacrevetteserver}, but it is about to run on the local machine. Run it through \"\${CLAUDE_PLUGIN_ROOT}\"/scripts/hl-ssh.sh instead — that wrapper refuses to execute anything unless \`hostname\` on the far end matches. (Commands have landed on the wrong machine on this setup before.)"
fi

exit 0
