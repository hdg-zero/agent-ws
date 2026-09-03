# Updating an Existing Environment

If you already have a functional `agent-ws` installation, this guide explains how to update your environment to benefit from recent improvements (automatic `umask 0002` management, the new `agent-fix-perms` launcher, clean separation between `ai` and `agent-run`, headless execution support, and security hardenings).

---

## Method 1: Automatic Update (Recommended)

The non-interactive setup script provides a dedicated `--update` option that updates configuration, profiles, and launchers without touching your data or recreating the container:

```bash
git pull
./scripts/setup-agent-ia-env-noninteractive.sh --update
```

### What this command does:
1. **Preserves existing settings**: reloads variables from `/etc/agent-ia-env.conf` (username, container name, shared directory).
2. **Configures `umask 0002`**: adds `umask 0002` to `/home/agent/.bashrc` and `.profile`, ensuring all new files created by AI agents or their tools remain editable by your primary user.
3. **Configures Git for group sharing**: sets `git config --global core.sharedRepository group` for user `agent`.
4. **Installs and updates launchers**: updates `/usr/local/bin/` with secured versions (`agent-ia-enter`, `agent-shell`, `agent-run`, `ai`, `agent-stop`) and installs the new `agent-fix-perms` launcher.

Once the update completes, apply restored permissions across your existing projects:

```bash
agent-fix-perms
```

---

## Method 2: Manual Step-by-Step Update

If you prefer applying changes manually without running setup scripts:

### 1. Enable umask 0002 for the AI user
```bash
sudo -u agent bash -c 'echo "umask 0002" >> ~/.bashrc'
sudo -u agent bash -c 'echo "umask 0002" >> ~/.profile'
sudo -u agent git config --global core.sharedRepository group
```

### 2. Repair existing file permissions
To fix files already created with restrictive ACL masks (`#effective:r--`):
```bash
sudo chown -R root:iawork /srv/ia-projets
sudo chmod 2770 /srv/ia-projets
sudo find /srv/ia-projets -type d -exec chmod 2770 {} +
sudo chmod -R g+rwX /srv/ia-projets
sudo setfacl -R -m g:iawork:rwx,m::rwx /srv/ia-projets
sudo setfacl -R -d -m g:iawork:rwx,m::rwx /srv/ia-projets
```

### 3. Update launchers only
To update only the launcher scripts in `/usr/local/bin/`:
```bash
./scripts/setup-agent-ia-env-noninteractive.sh --launchers-only
```

---

## Optional: Migrate to Wayland alias `wayland-agent`

If your existing setup was initialized with the legacy `wayland-hdg` alias:
- Your setup continues to work seamlessly without modification, as the alias is read from `/etc/agent-ia-env.conf`.
- If you wish to migrate to the clean default alias:
  1. Edit `/etc/agent-ia-env.conf` and change:
     ```ini
     WAYLAND_ALIAS="wayland-agent"
     ```
  2. Recreate the Distrobox container to apply the updated socket mount:
     ```bash
     ./scripts/setup-agent-ia-env-noninteractive.sh --recreate-box
     ```
