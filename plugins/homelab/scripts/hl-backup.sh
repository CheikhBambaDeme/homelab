#!/usr/bin/env bash
# hl-backup.sh list     — what backups exist on the server
# hl-backup.sh run      — run a backup now
# hl-backup.sh install  — install the backup script + a nightly cron entry
# hl-backup.sh pull [local-dir]
#                       — copy backups off the server (the part that matters)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/config.sh"
TPL="$(cd "$HERE/.." && pwd)/templates/homelab-backup.sh"

case "${1:-list}" in
  list)
    "$HERE/hl-ssh.sh" '
      echo "### ~/backups"
      ls -lh ~/backups 2>/dev/null | tail -n +2 || echo "  (no ~/backups directory yet)"
      echo
      echo "### backup schedule"
      crontab -l 2>/dev/null | grep -i backup || echo "  (no backup cron entry)"
      echo
      echo "### last run"
      tail -20 ~/backups/backup.log 2>/dev/null || echo "  (no log yet)"
    ' 2>&1
    ;;
  run)
    "$HERE/hl-ssh.sh" 'test -x ~/bin/homelab-backup.sh' >/dev/null 2>&1 \
      || { echo "Backup script not installed on the server. Run: hl-backup.sh install" >&2; exit 1; }
    "$HERE/hl-ssh.sh" '~/bin/homelab-backup.sh' 2>&1
    ;;
  install)
    [ -f "$TPL" ] || { echo "Missing template: $TPL" >&2; exit 66; }
    "$HERE/hl-ssh.sh" 'mkdir -p ~/bin ~/backups' || exit $?
    "$HERE/hl-ssh.sh" 'cat > ~/bin/homelab-backup.sh && chmod +x ~/bin/homelab-backup.sh' < "$TPL" || exit $?
    "$HERE/hl-ssh.sh" '
      line="30 3 * * * $HOME/bin/homelab-backup.sh >/dev/null 2>&1"
      if crontab -l 2>/dev/null | grep -qF "homelab-backup.sh"; then
        echo "Cron entry already present:"
      else
        (crontab -l 2>/dev/null; echo "$line") | crontab -
        echo "Installed nightly cron entry (03:30):"
      fi
      crontab -l | grep homelab-backup.sh
    ' 2>&1
    ;;
  pull)
    dest="${2:-$HOME/homelab-backups}"
    mkdir -p "$dest"
    target=$(hl_target) || { hl_unreachable_message >&2; exit 69; }
    opts=(); mapfile -t opts < <(hl_ssh_base_opts)
    ssh_cmd="ssh"; for o in "${opts[@]}"; do ssh_cmd+=" $(printf '%q' "$o")"; done
    rsync -avz --progress -e "$ssh_cmd" \
      "${HOMELAB_SSH_USER}@${target}:backups/" "$dest/"
    echo
    echo "Pulled to $dest — this copy is what survives the server's disk dying."
    ;;
  *)
    echo "usage: hl-backup.sh {list|run|install|pull [dir]}" >&2
    exit 64
    ;;
esac
