#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "\n[ERREUR] Ligne $LINENO. La configuration non interactive a été interrompue." >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-agent-ia-env.sh"

INSTALL_HOST_PACKAGES=1
SETUP_AGENT_USER=1
SETUP_SHARED_DIR=1
PROTECT_MAIN_HOME=1
ENSURE_SUBIDS=1
PREPARE_AGENT_RUNTIME=1
APPLY_WAYLAND_ACL=1
CREATE_DISTROBOX=1
INSTALL_LAUNCHERS=1
RECREATE_BOX=0

usage() {
  cat <<'EOF'
Usage: setup-agent-ia-env-noninteractive.sh [options]

Options:
  --main-user NAME
  --agent-user NAME
  --shared-group NAME
  --shared-dir PATH
  --box-name NAME
  --box-image IMAGE
  --wayland-alias NAME
  --recreate-box
  --skip-host-packages
  --skip-agent-user
  --skip-shared-dir
  --skip-protect-home
  --skip-subids
  --skip-agent-runtime
  --skip-wayland-acl
  --skip-distrobox
  --skip-launchers
  --help
EOF
}

parse_args() {
  set_default_setup_values
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --main-user) MAIN_USER="$2"; shift 2 ;;
      --agent-user) AGENT_USER="$2"; shift 2 ;;
      --shared-group) SHARED_GROUP="$2"; shift 2 ;;
      --shared-dir) SHARED_DIR="$2"; shift 2 ;;
      --box-name) BOX_NAME="$2"; shift 2 ;;
      --box-image) BOX_IMAGE="$2"; shift 2 ;;
      --wayland-alias) WAYLAND_ALIAS="$2"; shift 2 ;;
      --recreate-box) RECREATE_BOX=1; shift ;;
      --skip-host-packages) INSTALL_HOST_PACKAGES=0; shift ;;
      --skip-agent-user) SETUP_AGENT_USER=0; shift ;;
      --skip-shared-dir) SETUP_SHARED_DIR=0; shift ;;
      --skip-protect-home) PROTECT_MAIN_HOME=0; shift ;;
      --skip-subids) ENSURE_SUBIDS=0; shift ;;
      --skip-agent-runtime) PREPARE_AGENT_RUNTIME=0; shift ;;
      --skip-wayland-acl) APPLY_WAYLAND_ACL=0; shift ;;
      --skip-distrobox) CREATE_DISTROBOX=0; shift ;;
      --skip-launchers) INSTALL_LAUNCHERS=0; shift ;;
      --help) usage; exit 0 ;;
      *) err "Option inconnue : $1"; usage; exit 1 ;;
    esac
  done
}

run_step() {
  local enabled="$1" label="$2" fn="$3"
  if [[ "$enabled" -eq 1 ]]; then
    info "$label"
    "$fn"
  else
    info "Étape ignorée : $label"
  fi
}

run_agent_env() {
  sudo -H -u "$AGENT_USER" env \
    XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
    WAYLAND_DISPLAY="$WAYLAND_ALIAS" \
    XDG_SESSION_TYPE=wayland \
    HOME="/home/$AGENT_USER" \
    USER="$AGENT_USER" \
    LOGNAME="$AGENT_USER" \
    SHELL=/bin/bash \
    "$@"
}

step_install_host_packages() {
  if ! command_exists pacman; then
    err "pacman introuvable. Ce script est prévu pour Arch Linux."
    exit 1
  fi
  run_sudo pacman -S --needed podman distrobox acl fuse-overlayfs slirp4netns passt
}

step_ensure_agent_user() {
  if id "$AGENT_USER" >/dev/null 2>&1; then
    info "L'utilisateur $AGENT_USER existe déjà."
  else
    run_sudo useradd -m -s /bin/bash "$AGENT_USER"
    run_sudo passwd -l "$AGENT_USER" || true
  fi
}

step_setup_shared_dir() {
  if getent group "$SHARED_GROUP" >/dev/null 2>&1; then
    info "Le groupe $SHARED_GROUP existe déjà."
  else
    run_sudo groupadd "$SHARED_GROUP"
  fi

  run_sudo usermod -aG "$SHARED_GROUP" "$MAIN_USER"
  run_sudo usermod -aG "$SHARED_GROUP" "$AGENT_USER"
  run_sudo mkdir -p "$SHARED_DIR"
  run_sudo chown root:"$SHARED_GROUP" "$SHARED_DIR"
  run_sudo chmod 2770 "$SHARED_DIR"
  run_sudo setfacl -m "g:$SHARED_GROUP:rwx" "$SHARED_DIR"
  run_sudo setfacl -d -m "g:$SHARED_GROUP:rwx" "$SHARED_DIR"
  run_sudo setfacl -d -m "m::rwx" "$SHARED_DIR"
}

step_protect_main_home() {
  run_sudo chmod 700 "/home/$MAIN_USER"
  if sudo -H -u "$AGENT_USER" ls "/home/$MAIN_USER" >/dev/null 2>&1; then
    err "$AGENT_USER peut encore lire /home/$MAIN_USER après chmod 700."
    exit 1
  fi
}

step_ensure_subids() {
  local start end

  if grep -q "^$AGENT_USER:" /etc/subuid && grep -q "^$AGENT_USER:" /etc/subgid; then
    info "Entrées SubUID/SubGID déjà présentes pour $AGENT_USER."
    return 0
  fi

  run_sudo sed -i "/^$AGENT_USER:/d" /etc/subuid
  run_sudo sed -i "/^$AGENT_USER:/d" /etc/subgid
  start="$(pick_free_subid_start)"
  end=$((start + 65535))
  run_sudo usermod --add-subuids "$start-$end" --add-subgids "$start-$end" "$AGENT_USER"
}

step_prepare_agent_runtime() {
  local tries=0

  AGENT_UID="$(id -u "$AGENT_USER")"
  AGENT_RUNTIME="/run/user/$AGENT_UID"
  run_sudo loginctl enable-linger "$AGENT_USER"

  while [[ ! -d "$AGENT_RUNTIME" ]] && (( tries < 20 )); do
    sleep 0.5
    tries=$((tries + 1))
  done

  if [[ ! -d "$AGENT_RUNTIME" ]]; then
    err "$AGENT_RUNTIME n'existe pas après enable-linger. Arrêt."
    exit 1
  fi
}

step_apply_wayland_acl() {
  run_sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR"
  run_sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$WAYLAND_SOCKET"
}

step_create_distrobox() {
  if run_agent_env distrobox list 2>/dev/null | grep -qE "(^|[[:space:]])$BOX_NAME($|[[:space:]])"; then
    if [[ "$RECREATE_BOX" -eq 1 ]]; then
      run_agent_env distrobox rm "$BOX_NAME"
    else
      info "Le Distrobox $BOX_NAME existe déjà. Création ignorée."
      return 0
    fi
  fi

  run_agent_env distrobox create --yes --name "$BOX_NAME" \
    --image "$BOX_IMAGE" \
    --volume "$SHARED_DIR:/Projets:rw" \
    --volume "$WAYLAND_SOCKET:$AGENT_RUNTIME/$WAYLAND_ALIAS"
}

write_launchers() {
  local tmp

  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail

print_agent_ws_banner() {
  cat >&2 <<'EOF_BANNER'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF_BANNER
}
print_agent_ws_banner

CONFIG_FILE="/etc/agent-ia-env.conf"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Configuration introuvable : $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

CURRENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR"
sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$CURRENT_SOCKET"

exec sudo -H -u "$AGENT_USER" env \
  XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
  WAYLAND_DISPLAY="$WAYLAND_ALIAS" \
  XDG_SESSION_TYPE=wayland \
  HOME="/home/$AGENT_USER" \
  USER="$AGENT_USER" \
  LOGNAME="$AGENT_USER" \
  SHELL=/bin/bash \
  distrobox enter "$BOX_NAME" "$@"
EOF_LAUNCHER
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-ia-enter

  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_SHELL'
#!/usr/bin/env bash
set -Eeuo pipefail

print_agent_ws_banner() {
  cat >&2 <<'EOF_BANNER'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF_BANNER
}
print_agent_ws_banner

CONFIG_FILE="/etc/agent-ia-env.conf"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Configuration introuvable : $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

CURRENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR"
sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$CURRENT_SOCKET"

exec sudo -H -u "$AGENT_USER" env \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_SESSION_TYPE=wayland \
  HOME="/home/$AGENT_USER" \
  USER="$AGENT_USER" \
  LOGNAME="$AGENT_USER" \
  SHELL=/bin/bash \
  foot --working-directory="/home/$AGENT_USER" "$@"
EOF_SHELL
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-shell

  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_RUN'
#!/usr/bin/env bash
set -euo pipefail

print_agent_ws_banner() {
  cat >&2 <<'EOF_BANNER'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF_BANNER
}
print_agent_ws_banner

CONFIG_FILE="/etc/agent-ia-env.conf"
AGENT_USER=agent
MAIN_USER="${USER:-hdg}"
if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

MAIN_UID="$(id -u "$MAIN_USER")"
AGENT_UID="$(id -u "$AGENT_USER")"
MAIN_WAYLAND_SOCKET="/run/user/$MAIN_UID/$WAYLAND_DISPLAY"

sudo setfacl -m "u:$AGENT_USER:x,m::x" "/run/user/$MAIN_UID"
sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$MAIN_WAYLAND_SOCKET"

exec sudo -H -u "$AGENT_USER" env \
  XDG_RUNTIME_DIR="/run/user/$AGENT_UID" \
  WAYLAND_DISPLAY="$MAIN_WAYLAND_SOCKET" \
  XDG_SESSION_TYPE=wayland \
  ELECTRON_OZONE_PLATFORM_HINT=wayland \
  MOZ_ENABLE_WAYLAND=1 \
  GDK_BACKEND=wayland \
  QT_QPA_PLATFORM=wayland \
  DISPLAY= \
  HOME="/home/$AGENT_USER" \
  USER="$AGENT_USER" \
  LOGNAME="$AGENT_USER" \
  SHELL=/bin/bash \
  bash -lc 'cd "$HOME" && exec "$@"' bash "$@"
EOF_RUN
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-run

  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_AI'
#!/usr/bin/env bash
set -euo pipefail

exec agent-run "$@"
EOF_AI
  run_sudo install -m 0755 "$tmp" /usr/local/bin/ai
}

main() {
  require_not_root
  parse_args "$@"
  validate_identifier "Nom d'utilisateur IA" "$AGENT_USER"
  validate_identifier "Nom du groupe partagé" "$SHARED_GROUP"
  validate_identifier "Nom du Distrobox" "$BOX_NAME"
  validate_identifier "Alias socket Wayland" "$WAYLAND_ALIAS"
  validate_path "Dossier partagé" "$SHARED_DIR"
  validate_wayland_session

  AGENT_UID="${AGENT_UID:-}"
  AGENT_RUNTIME="${AGENT_RUNTIME:-}"
  WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

  print_agent_ws_banner
  info "Démarrage de l'installation non interactive."
  print_setup_summary

  run_step "$INSTALL_HOST_PACKAGES" "Paquets hôte" step_install_host_packages
  run_step "$SETUP_AGENT_USER" "Utilisateur IA" step_ensure_agent_user
  run_step "$SETUP_SHARED_DIR" "Groupe et dossier partagé" step_setup_shared_dir
  run_step "$PROTECT_MAIN_HOME" "Protection du home principal" step_protect_main_home
  run_step "$ENSURE_SUBIDS" "Vérification SubUID/SubGID de l'utilisateur IA" step_ensure_subids

  if [[ "$PREPARE_AGENT_RUNTIME" -eq 1 ]]; then
    run_step 1 "Runtime agent via linger" step_prepare_agent_runtime
  else
    AGENT_UID="$(id -u "$AGENT_USER")"
    AGENT_RUNTIME="/run/user/$AGENT_UID"
    info "Étape ignorée : Runtime agent via linger"
  fi

  run_step "$APPLY_WAYLAND_ACL" "ACL Wayland" step_apply_wayland_acl
  write_config_file
  run_step "$CREATE_DISTROBOX" "Création du Distrobox" step_create_distrobox
  run_step "$INSTALL_LAUNCHERS" "Installation des lanceurs" write_launchers

  info "Configuration non interactive terminée."
}

main "$@"
