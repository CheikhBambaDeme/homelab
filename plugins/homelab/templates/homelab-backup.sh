#!/usr/bin/env bash
# homelab-backup.sh — installed on the server at ~/bin/homelab-backup.sh
#
# Walks every Compose project under ~/docker-apps, dumps any Postgres or
# MariaDB/MySQL service it finds, and tars every Docker volume belonging to the
# project. Output lands in ~/backups, one dated file per target, with a
# retention window.
#
# A backup on the same disk as the data protects against software mistakes, not
# against the disk dying. Getting a copy OFF this machine is the part that
# actually matters — see `homelab-backup.sh` usage notes and /homelab:backup.
set -uo pipefail

APPS_ROOT="${APPS_ROOT:-$HOME/docker-apps}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
DATE="$(date +%F)"
STAMP="$(date +%F_%H%M%S)"

mkdir -p "$BACKUP_DIR"
exec > >(tee -a "$BACKUP_DIR/backup.log") 2>&1
echo "=== homelab backup $STAMP on $(hostname) ==="

compose_file() {
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -f "$1/$f" ] && { echo "$1/$f"; return 0; }
  done
  return 1
}

fail=0

for dir in "$APPS_ROOT"/*/; do
  [ -d "$dir" ] || continue
  project="$(basename "$dir")"
  cf="$(compose_file "$dir")" || continue
  echo "--- project: $project"

  services="$(cd "$dir" && docker compose ps --services 2>/dev/null)" || continue

  for svc in $services; do
    image="$(cd "$dir" && docker compose images --format json "$svc" 2>/dev/null | head -c 2000)"
    case "$image" in
      *postgres*)
        user="$(cd "$dir" && docker compose exec -T "$svc" printenv POSTGRES_USER 2>/dev/null | tr -d '\r')"
        db="$(cd "$dir" && docker compose exec -T "$svc" printenv POSTGRES_DB 2>/dev/null | tr -d '\r')"
        user="${user:-postgres}"; db="${db:-$user}"
        out="$BACKUP_DIR/${project}-${svc}-${DATE}.sql.gz"
        echo "    pg_dump $db as $user -> $(basename "$out")"
        if (cd "$dir" && docker compose exec -T "$svc" pg_dump -U "$user" "$db") | gzip > "$out.part"; then
          mv "$out.part" "$out"
        else
          echo "    !! pg_dump FAILED for $project/$svc"; rm -f "$out.part"; fail=1
        fi
        ;;
      *mariadb*|*mysql*)
        user="root"
        pass="$(cd "$dir" && docker compose exec -T "$svc" printenv MYSQL_ROOT_PASSWORD 2>/dev/null | tr -d '\r')"
        out="$BACKUP_DIR/${project}-${svc}-${DATE}.sql.gz"
        echo "    mysqldump --all-databases -> $(basename "$out")"
        if (cd "$dir" && MYSQL_PWD="$pass" docker compose exec -T -e MYSQL_PWD="$pass" "$svc" \
              mysqldump -u "$user" --all-databases --single-transaction) | gzip > "$out.part"; then
          mv "$out.part" "$out"
        else
          echo "    !! mysqldump FAILED for $project/$svc"; rm -f "$out.part"; fail=1
        fi
        ;;
    esac
  done

  # Named volumes belonging to this Compose project.
  for vol in $(docker volume ls -q --filter "label=com.docker.compose.project=$project" 2>/dev/null); do
    out="$BACKUP_DIR/vol-${vol}-${DATE}.tar.gz"
    echo "    volume $vol -> $(basename "$out")"
    if docker run --rm -v "$vol":/data:ro -v "$BACKUP_DIR":/backup alpine \
         tar czf "/backup/$(basename "$out").part" -C /data . 2>/dev/null; then
      mv "$out.part" "$out"
    else
      echo "    !! volume dump FAILED for $vol"; rm -f "$out.part"; fail=1
    fi
  done
done

# Volumes not owned by any Compose project under APPS_ROOT (e.g. standalone ones).
for vol in "${EXTRA_VOLUMES:-}"; do
  [ -n "$vol" ] || continue
  out="$BACKUP_DIR/vol-${vol}-${DATE}.tar.gz"
  echo "--- extra volume $vol -> $(basename "$out")"
  docker run --rm -v "$vol":/data:ro -v "$BACKUP_DIR":/backup alpine \
    tar czf "/backup/$(basename "$out")" -C /data . 2>/dev/null || { echo "    !! FAILED"; fail=1; }
done

echo "--- pruning backups older than ${RETENTION_DAYS} days"
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.tar.gz' \) \
  -mtime +"$RETENTION_DAYS" -print -delete

echo "=== done ($(du -sh "$BACKUP_DIR" | cut -f1) total) rc=$fail ==="
exit $fail
