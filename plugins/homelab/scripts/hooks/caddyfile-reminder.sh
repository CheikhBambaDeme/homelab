#!/usr/bin/env bash
# PostToolUse: a Caddyfile edit does nothing until Caddy is reloaded.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
case "$path" in
  *Caddyfile*|*caddyfile*) ;;
  *) exit 0 ;;
esac
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "Caddyfile changed. It has no effect until Caddy reloads, and a syntax error will take every site down rather than just the new one. Validate then reload:\n  \"${CLAUDE_PLUGIN_ROOT}\"/scripts/hl-caddy.sh reload\nIf this file is the local copy rather than the one on the server, push it first.\nReminder for a Tailscale-served site: the block must be written as host:80 (so Caddy does not try to get its own certificate) and the reverse_proxy needs `header_up X-Forwarded-Proto https` (or an HTTPS-enforcing app redirect-loops)."
  }
}'
