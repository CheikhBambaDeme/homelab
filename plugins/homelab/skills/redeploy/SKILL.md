---
name: redeploy
description: Push this project's latest code to the lacrevetteserver homelab and restart it.
argument-hint: "[app-name]"
disable-model-invocation: true
allowed-tools: Bash(homelab:*)
---

# Redeploy to lacrevetteserver

Update an app that is already deployed. App: `$ARGUMENTS` (if empty, infer from
the directory name or the project's `deploy/push.sh` and confirm).

## 1. Check the working tree

Report uncommitted changes before shipping them — this pushes the working
directory, not a commit. Do not commit on the person's behalf unless asked.

## 2. Prefer the project's own script

If `deploy/push.sh` exists, use it — it carries any build step the app needs
(Tailwind, a bundler, generated assets) that a plain rsync would skip:

```bash
./deploy/push.sh
```

Otherwise run the build yourself, then:

```bash
homelab push . <app>
homelab ssh 'cd ~/docker-apps/<app> && docker compose up -d --build && docker compose ps'
```

The remote `.env` is excluded from the sync and stays as it is.

## 3. Migrations and other one-off steps

If the change includes schema migrations and the entrypoint does not run them,
run them explicitly, and **take a dump first** — this server has no off-machine
backups unless `/homelab:backup pull` has been run:

```bash
homelab ssh 'cd ~/docker-apps/<app> && docker compose exec -T db pg_dump -U <user> <db> | gzip > ~/backups/<app>-pre-migrate-$(date +%F_%H%M).sql.gz'
```

## 4. Verify

```bash
homelab logs <app> 50
```

Confirm a clean start rather than a restart loop, then check the app's URL
responds. If a new hostname or port is involved this is no longer a redeploy —
use `/homelab:deploy`.

## 5. If it broke

`docker compose up -d --build` has already replaced the image. To get back to
working code, revert the source locally and push again; there is no image
history kept on this server. Say so plainly rather than implying a rollback
exists.
