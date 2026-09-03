# Daily usage

## Main commands

### Enter the Distrobox

```bash
agent-ia-enter
```

This launcher:

- reloads configuration from `/etc/agent-ia-env.conf`;
- automatically detects whether Wayland is available (graphical session) or switches to CLI/headless mode;
- reapplies required ACLs on the active Wayland socket in a Wayland session;
- applies umask `0002` to preserve group write permissions on newly created files;
- enters the Distrobox as the AI user.

### Open a graphical terminal as the AI user

```bash
agent-shell
```

The script opens the preferred graphical terminal (configured or automatically detected, such as `foot`, `alacritty`, `kitty`, etc.) under the identity of the AI account directly from the main account's graphical session.

### Run a host command as the AI user

```bash
agent-run <command> [arguments...]
```

`agent-run` launches a command on the host under the identity of `agent` (with umask `0002`). In a Wayland session, it passes the main Wayland socket and forces Wayland backends (`ELECTRON_OZONE_PLATFORM_HINT`, `MOZ_ENABLE_WAYLAND`, `GDK_BACKEND`, `QT_QPA_PLATFORM`). In headless or terminal mode, it runs directly in CLI mode. It uses `/run/user/<uid-agent>` as `XDG_RUNTIME_DIR` so IPC sockets are created on the `agent` side.

Example:

```bash
agent-run foot --working-directory=/home/agent
```

### Quick execution inside the Distrobox container (`ai`)

The `ai` shortcut controls the Distrobox environment directly:

```bash
# Open an interactive shell inside the container
ai

# Run a command inside the container
ai <command> [arguments...]

# Run a graphical or long-running command in background (detached)
ai --bg <command> [arguments...]

# Restore shared group write permissions
ai --fix-perms
```

### Restore shared folder write permissions

```bash
agent-fix-perms
```

If third-party programs or tools create files with restrictive permissions, this command instantly reapplies the `setgid` bit (`2770`), `g+rwX` permissions, and default POSIX ACLs on `/srv/ia-projets`.

### Stop the container and AI session

```bash
agent-stop
```

This launcher cleanly terminates the AI environment in multiple steps:

1. stops the Distrobox container (`distrobox stop -Y <box-name>`);
2. terminates remaining processes owned by the AI user (`pkill -u <agent-user>`);
3. closes the systemd user session (`loginctl terminate-user <agent-user>`).

Available options:

- `agent-stop --box-only`: only stops the Distrobox container without terminating the host user session;
- `agent-stop --session-only`: only terminates the systemd session and remaining processes without explicitly calling Distrobox stop;
- `agent-stop --fix-perms`: restores shared directory write permissions before shutting down;
- `agent-stop --help`: displays help.

## Recommended working directory

Inside the container, work in:

```bash
cd /Projets
```

This path maps to the host shared project directory, typically:

```text
/srv/ia-projets
```

## Best practices

### Work in Git

Before letting an agent modify a project:

```bash
git status
git add -A
git commit -m "checkpoint before AI session"
```

After the session:

```bash
git diff
git status
```

### Limit secrets

Avoid storing in `/srv/ia-projets`:

- SSH keys;
- long-lived tokens;
- sensitive `.env` files;
- `kubeconfig`;
- cloud credentials.

Prefer dedicated, revocable, scoped tokens.

### Treat `/home/agent` as exposed to the AI

This home directory is not your personal space; it belongs to the AI environment. Keep only:

- tools;
- caches;
- minimal required credentials;
- temporary working files.

### Recreate the Distrobox if necessary

If the environment becomes unstable or overly cluttered:

1. save useful projects into `/srv/ia-projets`;
2. remove the Distrobox container;
3. rerun the setup script;
4. recreate the container.

## What the architecture allows you to do

- run Linux GUIs from inside the container;
- install SDKs without cluttering the main host;
- keep an explicit, bounded file scope;
- throw away and rebuild the AI environment at will.

## What it does not guarantee

- strong isolation against active malware;
- protection equivalent to a hypervisor / VM;
- perfect security if you mount too many host directories into the container.
