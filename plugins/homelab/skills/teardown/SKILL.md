---
name: teardown
description: Remove an app from the lacrevetteserver homelab cleanly — containers, Caddy route, firewall rule and files.
argument-hint: "<app>"
disable-model-invocation: true
allowed-tools: Bash(homelab:*)
---

# Tear down `$ARGUMENTS`

Removing an app touches four things that live in different places. Missing one
leaves either a dead route or a silently orphaned volume.

## 0. Before anything

State plainly what will be destroyed and get explicit confirmation. Then back up
regardless — volumes are not recoverable:

```bash
homelab backup run
homelab backup pull ~/homelab-backups
```

Note that `~/docker-apps/<app>/.env` is the only copy of that app's generated
secrets. If they might be wanted again, copy it off first.

## 1. Stop the stack

```bash
homelab ssh 'cd ~/docker-apps/<app> && docker compose down'
```

Without `-v`. Volumes are kept deliberately at this stage, and a hook in this
plugin will refuse the `-v` form.

## 2. Remove the Caddy route

Delete the app's block from `~/docker-apps/caddy/Caddyfile`, keeping the trailing
catch-all `:80` block last, then validate and reload:

```bash
homelab caddy reload
```

A route pointing at a container that no longer exists makes Caddy return 502 for
that hostname rather than failing loudly, so this is easy to forget.

## 3. Close the firewall rule

Only if the app had a dedicated published port:

```bash
homelab ssh 'sudo ufw status numbered'
homelab ssh 'sudo ufw delete <number>'
```

Needs a sudo password, so hand this one to the person to run.

## 4. Remove files and volumes

```bash
homelab ssh 'ls ~/docker-apps/<app>'
homelab ssh 'docker volume ls --filter label=com.docker.compose.project=<app>'
```

Show both lists and confirm again before deleting. Volume removal is refused by
this plugin's guard hook — hand the exact command to the person to run in their
own terminal, after the backup above is verified.

## 5. Update the docs

In the homelab docs repo: remove the app's section from `docker-services.md`,
free its port in the `deployment-guide.md` table, and note anything left behind.
