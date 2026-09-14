#!/usr/bin/env bash
# Print the address currently used to reach the server, or an explanation.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/config.sh"
if target=$(hl_target); then
  echo "$target"
else
  hl_unreachable_message
  exit 1
fi
