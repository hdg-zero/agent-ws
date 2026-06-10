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

`agent-run` runs a host command as `agent`, keeps the main session Wayland runtime, and forces Wayland backends (`MOZ_ENABLE_WAYLAND`, `GDK_BACKEND`, `QT_QPA_PLATFORM`).

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
