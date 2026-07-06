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

You can then use the scripts only if you want to reproduce or automate this behavior.

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

The repository provides two variants:

- `scripts/setup-agent-ia-env.sh`: interactive version, suitable for a first installation;
- `scripts/setup-agent-ia-env-noninteractive.sh`: non-interactive version, suitable for automation.

To run the interactive setup script:

```bash
chmod +x scripts/setup-agent-ia-env.sh
./scripts/setup-agent-ia-env.sh
```

The script asks for confirmation before each structural step.

## Non-interactive installation

The non-interactive variant executes the same main stages without intermediate prompts.

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

- `--preferred-terminal NAME`: specifies the preferred terminal emulator (e.g. `foot`, `alacritty`, `kitty`, etc.).
- `--recreate-box`
- `--skip-host-packages`
- `--skip-launchers`
- `--skip-subids`
- `--skip-agent-runtime`

### Headless execution support
The setup script automatically detects the presence of a Wayland session. If no Wayland session is active (for example during an installation on a headless server via SSH or provisioning/automation tools), the script no longer crashes. It automatically falls back to CLI-only mode: the Distrobox container is created without mounting graphical sockets, and Wayland ACL steps are skipped with a warning message.

## What the script does

### 1. Installs host packages

On Arch Linux, the script installs if necessary:

- `podman`
- `distrobox`
- `acl`
- `fuse-overlayfs`
- `slirp4netns`
- `passt`

### 2. Creates or reuses the AI user

By default:

- AI user: `agent`
- shell: `/bin/bash`
- locked password

The account is designed to be used via `sudo -u`, not as a full graphical session.

### Default image

The validated v1 documentation defaults to:

```text
docker.io/library/archlinux:latest
```

### 3. Verifies SubUID/SubGID

The script checks that the AI user has a range in `/etc/subuid` and `/etc/subgid`.

If a range is missing, it adds an available range using `usermod --add-subuids` and `usermod --add-subgids`. Without these mappings, Podman might create a container that fails to map UID 0, causing Distrobox creation to fail at the end.

### 4. Prepares the shared directory

By default:

```text
/srv/ia-projets
```

With:

- shared group `iawork`;
- permissions `2770`;
- default read/write/execute ACLs for the shared group.

### 5. Protects the main home directory

The script proposes:

```bash
chmod 700 /home/<main-user>
```

This is a key step. Without it, main home isolation is weak or non-existent.

### 6. Prepares the AI user runtime

The script enables linger:

```bash
sudo loginctl enable-linger agent
```

Then it waits for the real runtime to exist:

```text
/run/user/<uid-agent>
```

It no longer creates this directory manually.

### 7. Prepares Wayland access

The script:

- detects the current Wayland socket;
- temporarily grants the required ACLs to the AI account;
- saves the source socket path in the configuration file.

### 8. Creates the Distrobox

The Distrobox is created as the AI user, with at minimum:

- mount of `/srv/ia-projets` to `/Projets`;
- mount of the Wayland socket into the AI account's runtime;
- required Wayland environment variables.

### 9. Installs launchers

The script writes:

- `/etc/agent-ia-env.conf`
- `/usr/local/bin/agent-ia-enter`
- `/usr/local/bin/agent-shell`
- `/usr/local/bin/agent-run`
- `/usr/local/bin/ai`

## Manual installation of tools inside the container

Installing development tools is no longer automated by the setup script. This is intentional: this step is not strictly required for setting up the environment, and it adds unnecessary fragility to the setup process.

Once inside the Distrobox, install only what you need.

Example for Arch inside the container:

```bash
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm git curl wget base-devel nodejs npm python python-pip
```

## Post-installation checks

### Check that the AI user cannot read the main home directory

```bash
sudo -H -u agent ls /home/<main-user>
```

Expected result:

```text
Permission denied
```

### Check the shared directory

```bash
ls -ld /srv/ia-projets
getfacl /srv/ia-projets
```

### Enter the AI environment

```bash
agent-ia-enter
```

Then inside the container:

```bash
cd /Projets
```

## Uninstall

Two variants are available:

- `scripts/uninstall-agent-ia-env.sh`: interactive version;
- `scripts/uninstall-agent-ia-env-noninteractive.sh`: non-interactive version.

The uninstall script is:

```bash
chmod +x scripts/uninstall-agent-ia-env.sh
./scripts/uninstall-agent-ia-env.sh
```

It allows you to selectively remove:

- the Distrobox;
- the launchers;
- Wayland ACLs;
- the configuration file;
- the shared directory;
- AI user sessions/processes;
- the `/run/user/<uid-agent>` runtime;
- `/etc/subuid` and `/etc/subgid` entries;
- the AI user;
- the shared group.

Non-interactive example:

```bash
chmod +x scripts/uninstall-agent-ia-env-noninteractive.sh
./scripts/uninstall-agent-ia-env-noninteractive.sh \
  --remove-box \
  --remove-launchers \
  --remove-config
```

To remove everything within the scope managed by the script:

```bash
./scripts/uninstall-agent-ia-env-noninteractive.sh --all
```

`--all` also removes the AI user, its home directory, runtime, SubUID/SubGID entries, the shared group, and the shared project directory.

Without any options, the non-interactive variant fails intentionally with a usage message instead of silently doing nothing.
