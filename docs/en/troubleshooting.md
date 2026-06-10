# Troubleshooting

## `chmod /run/user/1000/libpod: operation not permitted`

### Likely cause

Rootless Podman was started as the AI user but with the main user's `XDG_RUNTIME_DIR`.

### Fix

Make sure the AI user runs with:

```text
XDG_RUNTIME_DIR=/run/user/<uid-agent>
```

## `failed to connect to wayland; no compositor running?`

### Likely causes

- the current Wayland socket is no longer the one mounted when the Distrobox was created;
- ACLs on the runtime directory or socket were lost after logout/login;
- the command is not being run from an actual Wayland session.

### Checks

```bash
echo "$XDG_RUNTIME_DIR"
echo "$WAYLAND_DISPLAY"
ls -l "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
```

### Fix

1. Run `agent-ia-enter` again from the active graphical session.
2. Rerun `scripts/setup-agent-ia-env.sh` if the host Wayland socket changed.
3. Recreate the Distrobox if its bind mount still points to an old socket.

## `Authorization required, but no authorization protocol specified` then `Error: cannot open display: :1`

### Likely cause

The application is trying to use X11 through `DISPLAY=:1` instead of Wayland. This is a common case with Firefox-based browsers such as `mullvad-browser`.

### Fix

Force Wayland when launching it:

```bash
MOZ_ENABLE_WAYLAND=1 mullvad-browser
```

If needed, clear `DISPLAY` as well:

```bash
DISPLAY= MOZ_ENABLE_WAYLAND=1 mullvad-browser
```

If this fixes it, the application was selecting the wrong graphical backend.

## The AI user can still read `/home/<main-user>`

### Likely cause

The main home directory permissions or ACLs are too permissive.

### Fix

```bash
chmod 700 /home/<main-user>
getfacl /home/<main-user>
```

Remove any ACLs that still grant access if needed.

## The main user cannot edit files created by the AI user

### Likely cause

The shared group, `setgid`, or default ACLs on the shared directory are wrong.

### Fix

```bash
sudo chown root:iawork /srv/ia-projets
sudo chmod 2770 /srv/ia-projets
sudo setfacl -m g:iawork:rwx /srv/ia-projets
sudo setfacl -d -m g:iawork:rwx /srv/ia-projets
sudo setfacl -d -m m::rwx /srv/ia-projets
```

## `agent-shell` does not open

### Likely causes

- `foot` is not installed as expected;
- the current session is not Wayland;
- the current socket ACLs could not be applied.

### Fix

Re-run the setup or adapt the launcher to your preferred terminal emulator.
