# Installation

## Requirements

The current script mainly targets:

- Arch Linux;
- a Wayland session, typically Hyprland;
- working `sudo`;
- network connectivity;
- permissions to install packages and create users.

## Recommended installation

The recommended path is the manual installation flow. It is the best way to understand:

- where the real security boundary is;
- which permissions are being granted;
- which host paths are exposed;
- which system assumptions the setup depends on.

The scripts in this repository are automation helpers, not the reference path.

## Security rule before anything else

Do not automatically run shell scripts found in repositories, including this one, without reading them first.

Before running a script:

1. read its contents;
2. identify `sudo`, `rm`, `useradd`, `usermod`, `setfacl`, `distrobox`, and `podman` commands;
3. verify the paths being modified;
4. confirm that the expected behavior matches your machine.

## Manual installation

The recommended manual flow is:

1. create a dedicated Linux user;
2. protect the main home directory with strict permissions;
3. create a shared group and shared directory;
4. verify valid SubUID/SubGID entries for the AI user;
5. enable linger to get `/run/user/<uid-agent>`;
6. grant temporary ACLs to the Wayland socket;
7. create the Distrobox as the AI user;
8. mount the shared directory and Wayland socket;
9. install tools inside the container.

### Validated manual creation

After creating the user, group, and shared directory, the validated process uses the AI user's SubUID/SubGID entries and enables its runtime:

```bash
grep '^agent:' /etc/subuid /etc/subgid
sudo loginctl enable-linger agent
```

The validated Distrobox creation command is:

```bash
AGENT_UID="$(id -u agent)"
USER_WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

sudo -H -u agent \
  env \
  XDG_RUNTIME_DIR="/run/user/$AGENT_UID" \
  WAYLAND_DISPLAY="wayland-user" \
  XDG_SESSION_TYPE=wayland \
  HOME=/home/agent \
  USER=agent \
  LOGNAME=agent \
  SHELL=/bin/bash \
  distrobox create --name agent-ia \
    --image docker.io/library/archlinux:latest \
    --volume /srv/ia-projets:/Projets:rw \
    --volume "$USER_WAYLAND_SOCKET:/run/user/$AGENT_UID/wayland-user"
```

The validated entry command is:

```bash
AGENT_UID="$(id -u agent)"

sudo -H -u agent \
  env \
  XDG_RUNTIME_DIR="/run/user/$AGENT_UID" \
  WAYLAND_DISPLAY="wayland-user" \
  XDG_SESSION_TYPE=wayland \
  HOME=/home/agent \
  USER=agent \
  LOGNAME=agent \
  SHELL=/bin/bash \
  distrobox enter agent-ia
```

## Script-assisted installation

The repository now provides two variants:

- `scripts/setup-agent-ia-env.sh`: interactive setup, suitable for first-time installation.
- `scripts/setup-agent-ia-env-noninteractive.sh`: non-interactive setup for automation.

Use the interactive setup script:

```bash
chmod +x scripts/setup-agent-ia-env.sh
./scripts/setup-agent-ia-env.sh
```

The script asks for confirmation before each structural step.

## Non-interactive installation

The non-interactive variant runs the same main stages without intermediate prompts.

Minimal example:

```bash
chmod +x scripts/setup-agent-ia-env-noninteractive.sh
./scripts/setup-agent-ia-env-noninteractive.sh
```

Example with options:

```bash
./scripts/setup-agent-ia-env-noninteractive.sh \
  --agent-user agent \
  --shared-group iawork \
  --shared-dir /srv/ia-projets \
  --box-name agent-ia
```

Useful options:

- `--recreate-box`
- `--skip-host-packages`
- `--skip-launchers`
- `--skip-subids`
- `--skip-agent-runtime`

## What the script does

1. Installs host packages such as `podman`, `distrobox`, `acl`, `fuse-overlayfs`, `slirp4netns`, and `passt`.
2. Creates or reuses the AI user, `agent` by default.
3. Verifies SubUID/SubGID entries for the AI user and creates a free range if missing.
4. Creates the shared group and shared project directory.
5. Protects the main home directory with `chmod 700`.
6. Enables linger and waits for the real `/run/user/<uid-agent>` runtime.
7. Applies temporary ACLs for the active Wayland socket.
8. Creates the Distrobox with shared volumes and Wayland variables.
9. Installs helper launchers and writes `/etc/agent-ia-env.conf`.

## Default image

The validated v1 documentation uses:

```text
docker.io/library/archlinux:latest
```


## Manual installation of tools inside the container

The setup script no longer installs a base development toolchain automatically inside the Distrobox. This is intentional: it is not required for the environment itself, and it adds unnecessary fragility to the installation flow.

Once inside the container, install only what you actually need.

Example for Arch inside the container:

```bash
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm git curl wget base-devel nodejs npm python python-pip
```



## Post-installation checks

Check that the AI user cannot read the main home directory:

```bash
sudo -H -u agent ls /home/<main-user>
```

Expected result:

```text
Permission denied
```

Check the shared directory:

```bash
ls -ld /srv/ia-projets
getfacl /srv/ia-projets
```

Enter the environment:

```bash
agent-ia-enter
cd /Projets
```

The setup also installs `agent-shell`, `agent-run`, and `ai`.

## Uninstall

Two variants are available:

- `scripts/uninstall-agent-ia-env.sh`: interactive uninstall.
- `scripts/uninstall-agent-ia-env-noninteractive.sh`: non-interactive uninstall.

Use:

```bash
chmod +x scripts/uninstall-agent-ia-env.sh
./scripts/uninstall-agent-ia-env.sh
```

The uninstall script can selectively remove the container, launchers, ACLs, configuration, shared directory, AI user sessions/processes, `/run/user/<uid-agent>`, SubUID/SubGID entries, the AI user, and the shared group.

Non-interactive example:

```bash
chmod +x scripts/uninstall-agent-ia-env-noninteractive.sh
./scripts/uninstall-agent-ia-env-noninteractive.sh \
  --remove-box \
  --remove-launchers \
  --remove-config
```

To remove everything handled by the script:

```bash
./scripts/uninstall-agent-ia-env-noninteractive.sh --all
```

`--all` also removes the AI user, its home, runtime directory, SubUID/SubGID entries, the shared group, and the shared directory.

Without any option, the non-interactive variant now fails intentionally with a usage message instead of silently doing nothing.
