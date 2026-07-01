# Architecture

## Principle

The main user keeps their graphical session and private home directory. A second Linux user, dedicated to AI tools, runs rootless Podman and the Distrobox container. Projects are exchanged through an explicit shared directory.

Example roles:

- main user: `archuser`
- AI user: `agent`
- shared group: `iawork`
- shared directory: `/srv/ia-projets`
- Distrobox: `agent-ia`

## Why not rely on Distrobox alone

Distrobox is excellent for:

- reproducibility;
- developer ergonomics;
- GUI integration;
- dependency isolation.

However, it is not a strict security sandbox. Its purpose is host integration, not VM-grade separation. The actual boundary must therefore be the dedicated Linux account.

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

The main home directory must not be exposed:

```text
agent user ─X─> /home/<main-user>
```

Recommended minimum protection:

```bash
chmod 700 /home/<main-user>
```

## Wayland GUI flow

GUI applications run inside Distrobox, but display in the main user's Wayland session.

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

Access is granted through ACLs on:

- the main user's runtime directory;
- the active Wayland socket;
- the AI user's runtime directory.

## Component roles

### Main user

Keeps:

- personal home directory;
- graphical session;
- sensitive files and secrets;
- administrative control through `sudo`.

### AI user

Owns:

- AI caches and tokens;
- rootless Podman containers;
- the Distrobox environment;
- development tools and dependencies.

### Shared group

The shared group allows both users to write to the same project space. The script configures:

```bash
chown root:iawork /srv/ia-projets
chmod 2770 /srv/ia-projets
setfacl -m g:iawork:rwx /srv/ia-projets
setfacl -d -m g:iawork:rwx /srv/ia-projets
```

The `setgid` bit guarantees group inheritance on new files.

### Rootless Podman

Podman must be launched with the correct user runtime:

```text
XDG_RUNTIME_DIR=/run/user/<uid-agent>
```

If Podman reuses the main account's runtime, you may see errors such as:

```text
chmod /run/user/1000/libpod: operation not permitted
```

## Realistic security assumptions

This architecture significantly improves isolation for AI-assisted development, but it remains below a VM.

It protects well against:

- accidental reading of the main home directory;
- polluting the main workstation with dependencies;
- uncontrolled project sprawl.

It does not protect well against:

- actively malicious code;
- deep host compromise;
- workloads requiring strong system-level isolation.

## When to choose something else

Use a VM or a separate machine if:

- you run untrusted code;
- you manipulate highly sensitive secrets;
- you need strong defensive isolation rather than practical workstation hygiene.
