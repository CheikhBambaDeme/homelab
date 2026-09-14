# homelab — a Claude Code plugin for `lacrevetteserver`

Deploy and operate apps on the homelab from inside any project. The plugin
carries the server's conventions, its known footguns, and guards against the
handful of commands that have already broken it once.

## Install

The plugin lives in the homelab docs repo, which doubles as a marketplace.

```bash
claude plugin marketplace add ~/Desktop/homelab
```

```bash
claude plugin install homelab@lacrevette-homelab
```

To try it without installing:

```bash
claude --plugin-dir ~/Desktop/homelab/plugins/homelab
```

Then check that the scripts can reach the server without a password prompt:

```
/homelab:setup-ssh
```

It tells you whether key-based SSH already works and, if not, what to run. The
scripts are non-interactive and cannot type a password, so this is the one
prerequisite.
## Skills

| Skill | What it does |
|---|---|
| `/homelab:deploy [name]` | First deployment of the current project: exposure mode, compose file, secrets, Caddy route, firewall, verification, docs |
| `/homelab:redeploy [name]` | Ship the latest code to an app that is already there |
| `/homelab:status` | Containers, disk, ports, ufw, Tailscale, Caddy — with the warning signs called out |
| `/homelab:logs <app> [n]` | Recent logs, read against this server's usual failure modes |
| `/homelab:doctor [symptom]` | Work through the known causes in order of how often they are the answer |
| `/homelab:caddy-route` | Add, change or remove a route, validate, reload |
| `/homelab:backup [cmd]` | Dump databases and volumes, install the nightly job, pull copies off the server |
| `/homelab:teardown <app>` | Remove an app without leaving a dead route or an orphaned volume |
| `/homelab:setup-ssh` | Key-based SSH, needed once per machine |
| `/homelab:configure` | Show or change which server this points at |

Two more load on their own rather than being invoked:

- **`homelab-conventions`** — how the machine is built and what it punishes.
  Claude reads it whenever work touches that server.
- **`compose-rules`** — path-scoped to `docker-compose.y*ml`, `Caddyfile`,
  `Dockerfile` and `deploy/**`, so the conventions arrive exactly when one of
  those files is being written.

Claude Code has no `rules/` directory inside a plugin — `.claude/rules/` is
project- or user-level only. Those two skills are how this plugin ships the
same thing: one always-available reference, one that loads on matching paths.

## Agents

- **`homelab-deployer`** — takes a project through a full first deployment in
  one pass, and reports what it verified rather than what it hopes.
- **`homelab-troubleshooter`** — read-only diagnosis; proposes fixes, applies
  none.

## Hooks

| Event | Effect |
|---|---|
| `PreToolUse` on Bash/Write/Edit | Refuses publishing host port 443, `docker compose down -v`, volume removal, `docker system prune --volumes`, recursive deletes under `docker-apps`, `ufw disable`/`reset`, `tailscale down`/`logout`, and tearing down `tailscale serve`. Notes when a server-shaped command is about to run locally. |
| `PostToolUse` on Write/Edit | A Caddyfile edit is inert until reload — says so, with the command. |
| `SessionStart` | Five lines of orientation: addresses, the skills, the two rules that matter most. |

Every denial explains the failure it prevents and what to do instead. None of
them is a general safety net; each is something this server has already been
bitten by, or something irreversible.

## Scripts

`bin/homelab` is on `PATH` whenever the plugin is enabled.

```bash
homelab status                      # containers, disk, ports, ufw, Tailscale, Caddy
homelab ports                       # what is already taken
homelab logs agelcom 100
homelab ssh 'docker ps'
homelab caddy show|validate|reload
homelab backup list|run|install|pull [dir]
homelab push . myapp
homelab target                      # which address is in use
homelab config                      # resolved settings
homelab check                       # is key-based SSH working?
```

The skills drive the same CLI, so one permission rule covers all of them:

```json
{ "permissions": { "allow": ["Bash(homelab:*)"] } }
```

Each skill already declares that in its `allowed-tools`, which covers the turn
it runs in; put it in `.claude/settings.json` if you would rather never be
asked. If `bin/` is not on `PATH` in your setup, the same scripts are at
`scripts/hl-*.sh` inside the plugin.
`homelab ssh` is the important one: it runs the hostname check and the command
in the same remote shell, so a command cannot land on a machine other than the
one that was checked. Commands were once run against the wrong machine during
this server's setup, which is why it works that way.

## Configuration

Defaults are the real server's. Resolution order, highest first:

1. `HOMELAB_*` environment variables
2. `~/.config/homelab/config.env`
3. the plugin's `userConfig`, editable in `/plugin` (reaches hooks only)
4. built-in defaults

```bash
HOMELAB_HOST=100.82.241.64 homelab status     # force the Tailscale path
```

`HOMELAB_HOSTNAME` is the safety check, not a label. Change it only when
genuinely pointing at a different machine.

## Layout

```
plugins/homelab/
├── .claude-plugin/plugin.json
├── skills/<name>/SKILL.md        12 skills; deploy/ also has reference.md
├── agents/                       deployer, troubleshooter
├── hooks/hooks.json
├── scripts/                      hl-ssh, hl-push, hl-status, hl-ports,
│   └── hooks/                     hl-logs, hl-caddy, hl-backup, config.sh
├── templates/                    push.sh, Caddyfile block, backup script
└── bin/homelab
```

## Pointing it at a different server

Everything server-specific resolves through `scripts/config.sh`. Set the values
via `/homelab:configure` and the skills follow. The prose in
`skills/homelab-conventions/SKILL.md` and `skills/deploy/reference.md` describes
this particular machine, though — a genuinely different server wants that prose
rewritten, not just the addresses changed.
