# Troubleshooting

## `chmod /run/user/1000/libpod: operation not permitted`

### Likely cause

Rootless Podman was started as the AI user but with the main user's `XDG_RUNTIME_DIR`.

### Fix

Make sure the AI user runs with:

```text
XDG_RUNTIME_DIR=/run/user/<uid-agent>
```

The `setup-agent-ia-env.sh` script builds the launchers specifically around this constraint.

## `failed to connect to wayland; no compositor running?`

### Likely causes

- the current Wayland socket is no longer the one mounted when the Distrobox was created;
- ACLs on the runtime directory or socket were lost after logout/reconnection;
- the script is not being launched from an actual Wayland session;
- the socket no longer exists under the expected name.

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

If a tool such as `antigravity` needs to open the browser automatically, also verify that `xdg-open` resolves to `mullvad-browser.desktop`. After fixing the default browser or the local desktop entry, restart `antigravity` and, if needed, the browser process that was already running.

## The AI user can still read `/home/<main-user>`

### Likely cause

The main home directory permissions or ACLs are too permissive.

### Check

```bash
sudo -H -u agent ls /home/<main-user>
```

### Fix

```bash
chmod 700 /home/<main-user>
getfacl /home/<main-user>
```

Then remove any unexpected ACLs if needed.

## The main user cannot edit files created by the AI user

### Likely cause

The shared group, `setgid`, or default ACLs on the shared directory are wrong.

### Check

```bash
ls -ld /srv/ia-projets
getfacl /srv/ia-projets
id <main-user>
id agent
```

### Fix

```bash
sudo chown root:iawork /srv/ia-projets
sudo chmod 2770 /srv/ia-projets
sudo setfacl -m g:iawork:rwx /srv/ia-projets
sudo setfacl -d -m g:iawork:rwx /srv/ia-projets
sudo setfacl -d -m m::rwx /srv/ia-projets
```

If the group was just added to a user, a re-login may be required.

## `agent-shell` does not open

### Likely causes

- `foot` is not installed on the host or in the expected path;
- the current session is not Wayland;
- the current socket ACLs could not be applied.

### Check

```bash
command -v foot
echo "$XDG_RUNTIME_DIR"
echo "$WAYLAND_DISPLAY"
```

### Fix

Re-run the setup or adapt the launcher if you prefer another terminal emulator.

## The Distrobox already exists but no longer works properly

### Fix

Remove and recreate the container with the setup script, especially if:

- the name of the Wayland socket has changed;
- the mounted volumes no longer match;
- container dependencies are corrupted.

## Start over from scratch

If trials have left too much intermediate state, the most reliable way is to delete the AI user completely and recreate the environment.

```bash
sudo loginctl terminate-user agent 2>/dev/null || true
sudo pkill -u agent 2>/dev/null || true
sudo rm -f /usr/local/bin/agent-ia-enter /usr/local/bin/agent-shell /usr/local/bin/agent-run /usr/local/bin/ai /etc/agent-ia-env.conf
sudo loginctl disable-linger agent 2>/dev/null || true
sudo userdel -r agent
sudo rm -rf /home/agent /run/user/1001
sudo sed -i '/^agent:/d' /etc/subuid
sudo sed -i '/^agent:/d' /etc/subgid
sudo groupdel iawork 2>/dev/null || true
```

Only remove `/srv/ia-projets` if you want to wipe the shared projects:

```bash
sudo rm -rf /srv/ia-projets
```

## Loss of session cache / tokens on Antigravity (forced to log in on every launch)

### Likely cause

The Antigravity application uses a Go-based backend (`language_server`) that attempts to store its authentication tokens directly via the Linux DBus Secret Service API (specifically resolving the `/org/freedesktop/secrets/aliases/default` alias).

In our isolated environment running under the dedicated system user `agent`, there is no active graphical desktop session and the user's password is locked. As a result, no default keyring (`login.keyring`) was initialized. The language server fails to unlock the collection (error `failed to unlock correct collection` in `language_server.log`), preventing the session from being persisted.

### Fix

You need to manually initialize a persistent and unlocked (blank password) `login.keyring` for the `agent` user.

1. **Install gnome-keyring** inside the Distrobox container:
   ```bash
   sudo pacman -S --needed gnome-keyring
   ```

2. **Manually create the default keyring**:
   Create the file `/home/agent/.local/share/keyrings/login.keyring` with the following contents to disable automatic locking:
   ```ini
   [keyring]
   display-name=login
   ctime=0
   mtime=0
   lock-on-idle=false
   lock-after=false
   ```

3. **Set the correct file permissions**:
   ```bash
   chmod 700 /home/agent/.local/share/keyrings
   chmod 600 /home/agent/.local/share/keyrings/login.keyring
   ```

4. **Restart the keyring daemon** or the container. The next time the application is started, the session token will be successfully saved to the automatically unlocked virtual keyring.

## Antigravity does not start (the command exits immediately without opening any window)

### Likely cause

The Antigravity application (based on Electron) uses a single-instance lock. If a residual or zombie `antigravity` process is already running in the background (e.g., after a sudden graphical logout or crash), any new launch attempt will detect the lock, request the existing instance to focus, and immediately exit (returning the command prompt). If the existing instance is stuck, no window will ever appear.

A DBus warning may be displayed in the terminal:
```text
Failed to connect to the bus: Failed to connect to socket /run/dbus/system_bus_socket: No such file or directory
```
This warning is related to the container isolation, is harmless, and does not prevent the application from running.

### Fix

Kill all residual `antigravity` processes in the background to release the lock:

```bash
killall -9 antigravity
```

Then launch the application again normally.

## File/folder explorer error (Request ended / cannot open display)

### Likely cause

In recent versions of Electron/Chromium, applications attempt to use the XDG Desktop Portal API (`org.freedesktop.portal.FileChooser`) via DBus to show native file dialogs.

Because the Distrobox container shares the user's DBus session bus, the request wakes up the `xdg-desktop-portal-gtk.service` on the host side for the AI user. However, this systemd service starts **on the host** (outside the container) where it cannot access the Wayland socket directly, resulting in a `cannot open display:` error and aborting the request (`Request ended (non-user cancelled)` error).

### Fix

Force the GTK portal service to run in the background **inside** the container (where the Wayland socket is properly mounted and accessible) so that DBus requests are handled locally.

Add the following block to the end of `/home/agent/.bash_profile` inside the container:

```bash
# Start GTK portal in the background inside the container if not already running
if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && ! pgrep -u "$USER" -f "/usr/lib/xdg-desktop-portal-[g]tk" >/dev/null; then
    /usr/lib/xdg-desktop-portal-gtk -r >/dev/null 2>&1 &
fi
```

## When to stop debugging and switch to a VM

If you find yourself adding endless exceptions, mounts, or workarounds to make unreliable tools function, the architecture is moving outside its intended scope. At that stage, a dedicated VM is more appropriate.
