# Architecture

## Principle

The main user keeps the graphical session and the private home directory. A second Linux user, dedicated to AI tools, runs rootless Podman and the Distrobox container. Projects are exchanged through an explicit shared directory.

Typical roles:

- main user: `archuser`
- AI user: `agent`
- shared group: `iawork`
- shared directory: `/srv/ia-projets`
- Distrobox: `agent-ia`

## Why not rely on Distrobox alone

Distrobox is excellent for reproducibility, developer ergonomics, GUI integration, and dependency isolation. It is not meant to be a strict security sandbox. Its purpose is host integration, not VM-grade separation. The actual boundary must therefore be the dedicated Linux account.

## Logical view

```text
┌─────────────────────────────────────────────────────────────┐
│ Linux host                                                   │
│                                                             │
│  Main user                                                  │
│  ├─ Hyprland / Wayland session                              │
│  ├─ /home/<main-user>                                       │
│  └─ Wayland socket /run/user/<uid-main>/wayland-X           │
│                                                             │
│  AI user                                                    │
│  ├─ /home/<agent-user>                                      │
│  ├─ rootless Podman via /run/user/<uid-agent>               │
│  └─ Distrobox                                               │
│                                                             │
│  Shared directory                                           │
│  └─ /srv/ia-projets                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## File flow

The shared directory is the intentionally exposed workspace:

```text
main user  ── rwx ──┐
                    ▼
              /srv/ia-projets
                    ▲
agent user ── rwx ──┘
```

The main home directory should stay blocked:

```text
agent user ─X─> /home/<main-user>
```

Recommended minimum protection:

```bash
chmod 700 /home/<main-user>
```

## Wayland GUI flow

GUI apps run in Distrobox but display inside the main user's Wayland session.

```text
GUI app inside Distrobox
        │
        │ WAYLAND_DISPLAY=<alias>
        ▼
/run/user/<uid-agent>/<alias>
        │
        │ bind mount to the real socket
        ▼
/run/user/<uid-main>/wayland-X
        │
        ▼
Main Wayland / Hyprland session
```

Access is granted through ACLs on the main user's runtime directory and the active Wayland socket.

## Components

### Main user

Keeps:

- the personal home directory;
- the graphical session;
- sensitive files and secrets;
- administrative control through `sudo`.

### AI user

Owns:

- AI caches and tokens;
- rootless Podman containers;
- the Distrobox environment;
- development tools and dependencies.

### Shared group

The shared group allows both users to write to the same project space. The setup script configures ownership, `setgid`, and default ACLs on `/srv/ia-projets`.

### Rootless Podman

Podman must run with the AI user's runtime:

```text
XDG_RUNTIME_DIR=/run/user/<uid-agent>
```

Using the main user's runtime can trigger errors such as:

```text
chmod /run/user/1000/libpod: operation not permitted
```

## Security expectations

This setup significantly improves isolation for AI-assisted development, but it is still below VM-grade isolation.

It protects well against:

- accidental exposure of the main home directory;
- polluting the main workstation with tool dependencies;
- uncontrolled project sprawl.

It does not protect well against:

- actively malicious code;
- deep host compromise;
- workloads that require strong system isolation.
