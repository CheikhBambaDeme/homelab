---
name: setup-ssh
description: Set up key-based SSH to the homelab server so this plugin's scripts can run without a password prompt.
disable-model-invocation: true
allowed-tools: Bash(homelab:*)
---

# Set up key-based SSH to the homelab

Every script in this plugin runs non-interactively and cannot type a password,
so they all fail until a key is in place. This is a one-time fix per machine.

## Current state

!`homelab check 2>&1 || true`

## Steps

**If the check above says key-based SSH already works, stop — there is nothing
to do here.** It may be working through an existing default key
(`~/.ssh/id_ed25519` or similar) rather than the dedicated one named above; that
is fine. Create the dedicated key only if you want this access separable from
your other SSH access.

### 1. Generate a key, if there is none

A dedicated key, so it can be revoked without touching anything else:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homelab -N "" -C "homelab-$(hostname)"
```

### 2. Copy it to the server

This asks for the server's login password once. It needs an interactive
terminal, so run it yourself rather than asking Claude to:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_homelab.pub lacrevetteserver@192.168.1.160
```

Away from home, use the Tailscale address instead:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_homelab.pub lacrevetteserver@100.82.241.64
```

### 3. Confirm

```bash
homelab target
```

It should print the address it connected on. That means key auth works and the
far end really is `lacrevetteserver`.

### 4. Optional: a shorter name

```
Host homelab
    HostName 192.168.1.160
    User lacrevetteserver
    IdentityFile ~/.ssh/id_ed25519_homelab
```

in `~/.ssh/config`, so `ssh homelab` works by hand.

## Worth doing at the same time

With keys working, password login can be turned off entirely on the server —
`PasswordAuthentication no` in `/etc/ssh/sshd_config.d/`, then
`sudo systemctl reload ssh`. Do that only from a session where the key is
already proven to work, and keep that session open until a second one connects,
or a mistake locks you out of a machine with no console.

Update `network-and-access.md` and `open-todos.md` in the homelab docs — both
currently record that no key is set up.
