---
name: backup
description: Back up the homelab's databases and Docker volumes, install the nightly schedule, or pull the backups off the server.
argument-hint: "[list|run|install|pull]"
disable-model-invocation: true
allowed-tools: Bash(homelab:*)
---

# Homelab backups — $ARGUMENTS

This is the most pressing open item on this server. Agelcom's Postgres database
holds a real shop's sales, stock and cash history and exists nowhere else;
Nextcloud's data volume is equally unreplicated.

## Current state

!`homelab backup list 2>&1 || true`

## What to do

Pick from the argument, or from what the state above shows is missing.

**`install`** — put `homelab-backup.sh` on the server and schedule it nightly at
03:30. It walks every Compose project under `~/docker-apps`, dumps any Postgres
or MariaDB service it finds, tars every volume labelled with that project, keeps
14 days, and logs to `~/backups/backup.log`.

```bash
homelab backup install
homelab backup run      # prove it works now
```

**`run`** — take a backup immediately. Do this before migrations, before
`docker compose down`, and before anything that touches a volume.

**`pull`** — copy the backups to this machine. **This is the step that actually
matters.** Backups sitting on the same disk as the data protect against a
software mistake, not against the disk dying, and the server is an old laptop.

```bash
homelab backup pull ~/homelab-backups
```

**`list`** — shown above.

## After running

Verify rather than assume — an empty or truncated dump reports success just as
loudly as a real one:

```bash
homelab ssh 'ls -lh ~/backups | tail -20'
homelab ssh 'gzip -t ~/backups/<file>.sql.gz && zcat ~/backups/<file>.sql.gz | head -20'
```

A real Postgres dump starts with `--` comment lines and a `SET` block. A file of
a few hundred bytes is a failed dump.

Report honestly what is and is not covered. In particular, `.env` files are
**not** backed up: they hold generated secrets that exist only on the server, and
copying them into a backup set that gets synced elsewhere is its own risk. If an
app cannot regenerate its secrets, say that it needs a deliberate manual copy.

If anything changed, update `open-todos.md` in the homelab docs.
