# Daily usage

## Main commands

### Enter the Distrobox

```bash
agent-ia-enter
```

This launcher:

- reloads configuration from `/etc/agent-ia-env.conf`;
- verifies that you are in a Wayland session;
- reapplies required ACLs on the active Wayland socket;
- enters the Distrobox as the AI user.

### Open a graphical terminal as the AI user

```bash
agent-shell
```

The script opens a `foot` terminal under the identity of the AI account directly from the main account's graphical session.

### Run a host command as the AI user

```bash
agent-run <command> [arguments...]
```

The following shortcut is also installed:

```bash
ai <command> [arguments...]
```

`agent-run` launches the command on the host under the identity of `agent`. It uses `/run/user/<uid-agent>` as `XDG_RUNTIME_DIR` so IPC sockets for applications such as VS Code are created on the `agent` side, while passing the main Wayland socket as an absolute path. It also forces Wayland backends (`ELECTRON_OZONE_PLATFORM_HINT`, `MOZ_ENABLE_WAYLAND`, `GDK_BACKEND`, `QT_QPA_PLATFORM`). It starts from `/home/agent` to avoid inheriting an inaccessible working directory such as `/home/hdg`.

Example:

```bash
ai foot --working-directory=/home/agent
```

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
