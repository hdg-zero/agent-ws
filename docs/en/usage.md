# Daily usage

## Main commands

Enter the Distrobox:

```bash
agent-ia-enter
```

Open a graphical terminal as the AI user:

```bash
agent-shell
```

Run a host command as the AI user:

```bash
agent-run <command> [arguments...]
```

The following shortcut is also installed:

```bash
ai <command> [arguments...]
```

`agent-run` runs a host command as `agent`. It uses `/run/user/<uid-agent>` as `XDG_RUNTIME_DIR` so application IPC sockets, for example VS Code sockets, are created on the `agent` side, while the main Wayland socket is passed as an absolute path. It also forces Wayland backends (`ELECTRON_OZONE_PLATFORM_HINT`, `MOZ_ENABLE_WAYLAND`, `GDK_BACKEND`, `QT_QPA_PLATFORM`). It starts from `/home/agent` so it does not inherit an inaccessible current directory such as `/home/hdg`.

## Recommended working directory

Inside the container, work in:

```bash
cd /Projets
```

This maps to the host shared directory, typically `/srv/ia-projets`.



## Best practices

- Keep projects under Git and create a checkpoint commit before AI-assisted changes.
- Avoid storing long-lived secrets in the shared directory.
- Treat `/home/agent` as part of the AI environment, not as a personal workspace.
- Recreate the Distrobox if the environment becomes unstable or over-customized.

## Limits

This architecture is good for practical isolation and workstation hygiene. It is not a substitute for a VM when running untrusted or hostile code.
