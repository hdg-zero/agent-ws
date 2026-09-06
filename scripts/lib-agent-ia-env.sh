#!/usr/bin/env bash

# Guard contre le double-sourcing
[[ -n "${_LIB_AGENT_IA_ENV_LOADED:-}" ]] && return 0
_LIB_AGENT_IA_ENV_LOADED=1

bold() { printf "\033[1m%s\033[0m\n" "$*" >&2; }
info() { printf "\n[INFO] %s\n" "$*" >&2; }
warn() { printf "\n[ATTENTION] %s\n" "$*" >&2; }
err() { printf "\n[ERREUR] %s\n" "$*" >&2; }

print_agent_ws_banner() {
  cat >&2 <<'EOF'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Crée un fichier temporaire dans $_AGENT_IA_WORK_DIR si disponible, sinon dans /tmp.
_make_temp() {
  if [[ -n "${_AGENT_IA_WORK_DIR:-}" ]]; then
    mktemp "${_AGENT_IA_WORK_DIR}/tmp.XXXXXX"
  else
    mktemp
  fi
}

# Valide qu'un identifiant (nom d'utilisateur, groupe, etc.) ne contient que des caractères sûrs.
validate_identifier() {
  local label="$1" value="$2"
  if [[ ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
    err "$label invalide : '$value'. Utilise uniquement lettres, chiffres, tirets et underscores."
    exit 1
  fi
}

# Valide qu'un chemin est absolu, ne contient pas de traversée (..) et utilise des caractères sûrs.
validate_path() {
  local label="$1" value="$2"
  if [[ ! "$value" =~ ^/[a-zA-Z0-9/_.-]+$ || "$value" =~ \.\. ]]; then
    err "$label invalide : '$value'. Le chemin doit être absolu, ne pas contenir de '..' et n'utiliser que des caractères sûrs."
    exit 1
  fi
}

run_sudo() {
  sudo "$@"
}

require_not_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    err "Lance ce script avec ton utilisateur principal, pas directement en root. Le script utilisera sudo quand nécessaire."
    exit 1
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local answer suffix
  if [[ "$default" == "y" ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
  while true; do
    read -r -p "$prompt $suffix " answer || true
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES|o|O|oui|OUI) return 0 ;;
      n|N|no|NO|non|NON) return 1 ;;
      *) echo "Réponds par y ou n." ;;
    esac
  done
}

ask_value() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default] : " value || true
  printf "%s" "${value:-$default}"
}

confirm_step() {
  local title="$1"
  local description="$2"
  bold "$title"
  printf "%s\n" "$description"
  ask_yes_no "Exécuter cette étape ?" "y"
}

range_conflicts() {
  local start="$1"
  local end=$((start + 65535))
  awk -F: -v s="$start" -v e="$end" '
    NF >= 3 {
      a=$2; b=$2+$3-1;
      if (s <= b && e >= a) found=1
    }
    END { exit found ? 0 : 1 }
  ' /etc/subuid /etc/subgid 2>/dev/null
}

pick_free_subid_start() {
  local start=2000000
  while range_conflicts "$start"; do
    start=$((start + 65536))
  done
  printf "%s" "$start"
}

set_default_setup_values() {
  MAIN_USER="${MAIN_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
  AGENT_USER="${AGENT_USER:-agent}"
  SHARED_GROUP="${SHARED_GROUP:-iawork}"
  SHARED_DIR="${SHARED_DIR:-/srv/ia-projets}"
  BOX_NAME="${BOX_NAME:-agent-ia}"
  BOX_IMAGE="${BOX_IMAGE:-docker.io/library/archlinux:latest}"
  WAYLAND_ALIAS="${WAYLAND_ALIAS:-wayland-agent}"
  PREFERRED_TERMINAL="${PREFERRED_TERMINAL:-foot}"
  CONFIG_FILE="${CONFIG_FILE:-/etc/agent-ia-env.conf}"
}

load_config_or_defaults() {
  local config_file="${1:-${CONFIG_FILE:-/etc/agent-ia-env.conf}}"
  CONFIG_FILE="$config_file"
  if [[ -r "$config_file" ]]; then
    # shellcheck disable=SC1090
    source "$config_file"
  else
    set_default_setup_values
    WAYLAND_SOURCE_SOCKET="${WAYLAND_SOURCE_SOCKET:-}"
    AGENT_UID="${AGENT_UID:-}"
    AGENT_RUNTIME="${AGENT_RUNTIME:-}"
  fi
}

write_config_file() {
  local tmp config_file="${1:-${CONFIG_FILE:-/etc/agent-ia-env.conf}}"
  tmp="$(_make_temp)"
  cat > "$tmp" <<EOF_CONF
# Configuration générée par setup-agent-ia-env.sh
MAIN_USER="$MAIN_USER"
AGENT_USER="$AGENT_USER"
SHARED_GROUP="$SHARED_GROUP"
SHARED_DIR="$SHARED_DIR"
BOX_NAME="$BOX_NAME"
BOX_IMAGE="$BOX_IMAGE"
WAYLAND_ALIAS="$WAYLAND_ALIAS"
WAYLAND_SOURCE_SOCKET="$WAYLAND_SOCKET"
WAYLAND_AVAILABLE="${WAYLAND_AVAILABLE:-0}"
AGENT_UID="$AGENT_UID"
AGENT_RUNTIME="$AGENT_RUNTIME"
PREFERRED_TERMINAL="${PREFERRED_TERMINAL:-foot}"
EOF_CONF
  run_sudo install -m 0644 "$tmp" "$config_file"
  rm -f "$tmp"
}

validate_wayland_session() {
  WAYLAND_AVAILABLE=0
  WAYLAND_SOCKET=""
  if [[ -z "${XDG_RUNTIME_DIR:-}" || -z "${WAYLAND_DISPLAY:-}" ]]; then
    warn "XDG_RUNTIME_DIR ou WAYLAND_DISPLAY est vide. Pas de session Wayland active détectée."
    return 0
  fi

  if [[ "$WAYLAND_DISPLAY" =~ ^/ ]]; then
    WAYLAND_SOCKET="$WAYLAND_DISPLAY"
  else
    WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  fi

  if [[ ! -S "$WAYLAND_SOCKET" ]]; then
    warn "Le socket Wayland n'existe pas ou n'est pas un socket : $WAYLAND_SOCKET. Pas de session Wayland active détectée."
    WAYLAND_SOCKET=""
    return 0
  fi

  WAYLAND_AVAILABLE=1
}

run_as_agent() {
  sudo -H -u "$AGENT_USER" env \
    XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
    WAYLAND_DISPLAY="${WAYLAND_ALIAS:-${WAYLAND_DISPLAY:-}}" \
    XDG_SESSION_TYPE=wayland \
    HOME="/home/$AGENT_USER" \
    USER="$AGENT_USER" \
    LOGNAME="$AGENT_USER" \
    SHELL=/bin/bash \
    "$@"
}

run_box_command_logged() {
  local box_name="$1"
  local log_file="$2"
  shift 2
  run_as_agent distrobox enter --no-workdir "$box_name" -- "$@" >"$log_file" 2>&1
}

print_setup_summary() {
  bold "Résumé de la configuration"
  cat <<EOF_SUM
Utilisateur principal : $MAIN_USER
Utilisateur IA       : $AGENT_USER
Groupe partagé       : $SHARED_GROUP
Dossier partagé      : $SHARED_DIR
Distrobox            : $BOX_NAME
Image                : $BOX_IMAGE
Socket Wayland hôte  : $WAYLAND_SOCKET
Alias dans conteneur : $WAYLAND_ALIAS
Terminal préféré     : $PREFERRED_TERMINAL
EOF_SUM
}

# Valide qu'un dossier partagé n'est pas un répertoire système critique ou utilisateur avant suppression.
validate_shared_dir_for_deletion() {
  local value="$1"
  validate_path "Dossier partagé" "$value"

  local canon
  canon="$(realpath -m "$value" 2>/dev/null || printf "%s" "$value")"
  local blacklisted=( "/" "/home" "/usr" "/var" "/etc" "/bin" "/lib" "/boot" "/root" "/sys" "/proc" "/dev" "/run" )

  if [[ -n "${MAIN_USER:-}" ]]; then
    local main_home
    main_home="$(getent passwd "$MAIN_USER" 2>/dev/null | cut -d: -f6)"
    [[ -z "$main_home" ]] && main_home="/home/$MAIN_USER"
    blacklisted+=( "$main_home" "/home/$MAIN_USER" )
  fi
  if [[ -n "${AGENT_USER:-}" ]]; then
    local agent_home
    agent_home="$(getent passwd "$AGENT_USER" 2>/dev/null | cut -d: -f6)"
    [[ -z "$agent_home" ]] && agent_home="/home/$AGENT_USER"
    blacklisted+=( "$agent_home" "/home/$AGENT_USER" )
  fi

  for path in "${blacklisted[@]}"; do
    local canon_bl
    canon_bl="$(realpath -m "$path" 2>/dev/null || printf "%s" "$path")"
    if [[ "$canon" == "$canon_bl" ]]; then
      err "Suppression interdite pour le répertoire système critique ou utilisateur : $value"
      exit 1
    fi
  done
}

# --- FONCTIONS DE CONFIGURATION (SETUP) PARTAGÉES (DRY) ---

setup_install_host_packages() {
  if ! command_exists pacman; then
    err "pacman introuvable. Ce script est prévu pour Arch Linux."
    exit 1
  fi
  run_sudo pacman -S --needed podman distrobox acl fuse-overlayfs slirp4netns passt
}

setup_ensure_agent_user() {
  if id "$AGENT_USER" >/dev/null 2>&1; then
    info "L'utilisateur $AGENT_USER existe déjà."
  else
    run_sudo useradd -m -s /bin/bash "$AGENT_USER"
    run_sudo passwd -l "$AGENT_USER" || true
  fi

  # Configuration de l'umask 0002 pour l'utilisateur IA afin de garantir les droits d'écriture de groupe
  local agent_home
  agent_home="$(getent passwd "$AGENT_USER" 2>/dev/null | cut -d: -f6)"
  [[ -z "$agent_home" ]] && agent_home="/home/$AGENT_USER"
  if [[ -d "$agent_home" ]]; then
    for profile_file in "$agent_home/.bashrc" "$agent_home/.profile" "$agent_home/.bash_profile"; do
      if [[ -f "$profile_file" ]]; then
        if ! grep -q "umask 0002" "$profile_file"; then
          run_sudo sh -c "echo 'umask 0002' >> '$profile_file'"
        fi
      else
        run_sudo sh -c "echo 'umask 0002' > '$profile_file'"
        run_sudo chown "$AGENT_USER:$AGENT_USER" "$profile_file"
      fi
    done
  fi

  # Configuration de Git côté agent pour partager l'écriture sur les dépôts
  if command_exists git; then
    run_as_agent git config --global core.sharedRepository group 2>/dev/null || true
  fi
}

setup_setup_shared_dir() {
  if getent group "$SHARED_GROUP" >/dev/null 2>&1; then
    info "Le groupe $SHARED_GROUP existe déjà."
  else
    run_sudo groupadd "$SHARED_GROUP"
  fi

  run_sudo usermod -aG "$SHARED_GROUP" "$MAIN_USER"
  run_sudo usermod -aG "$SHARED_GROUP" "$AGENT_USER"
  run_sudo mkdir -p "$SHARED_DIR"
  run_sudo chown -R root:"$SHARED_GROUP" "$SHARED_DIR"
  run_sudo chmod 2770 "$SHARED_DIR"
  run_sudo find "$SHARED_DIR" -type d -exec chmod 2770 {} + 2>/dev/null || true
  run_sudo chmod -R g+rwX "$SHARED_DIR" 2>/dev/null || true
  run_sudo setfacl -R -m "g:$SHARED_GROUP:rwx,m::rwx" "$SHARED_DIR"
  run_sudo setfacl -R -d -m "g:$SHARED_GROUP:rwx,m::rwx" "$SHARED_DIR"
}

setup_protect_main_home() {
  local main_home
  main_home="$(getent passwd "$MAIN_USER" 2>/dev/null | cut -d: -f6)"
  [[ -z "$main_home" ]] && main_home="/home/$MAIN_USER"
  run_sudo chmod 700 "$main_home"
  if sudo -H -u "$AGENT_USER" ls "$main_home" >/dev/null 2>&1; then
    err "$AGENT_USER peut encore lire $main_home après chmod 700."
    exit 1
  fi
}

setup_ensure_subids() {
  local start end

  if [[ -f /etc/subuid && -f /etc/subgid ]] && grep -q "^$AGENT_USER:" /etc/subuid && grep -q "^$AGENT_USER:" /etc/subgid; then
    info "Entrées SubUID/SubGID déjà présentes pour $AGENT_USER."
    return 0
  fi

  if [[ -f /etc/subuid ]]; then
    run_sudo sed -i "/^$AGENT_USER:/d" /etc/subuid
  fi
  if [[ -f /etc/subgid ]]; then
    run_sudo sed -i "/^$AGENT_USER:/d" /etc/subgid
  fi
  start="$(pick_free_subid_start)"
  end=$((start + 65535))
  run_sudo usermod --add-subuids "$start-$end" --add-subgids "$start-$end" "$AGENT_USER"
}

setup_prepare_agent_runtime() {
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

setup_apply_wayland_acl() {
  if [[ "${WAYLAND_AVAILABLE:-0}" -eq 1 && -n "${WAYLAND_SOCKET:-}" ]]; then
    run_sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR"
    run_sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$WAYLAND_SOCKET"
  else
    info "Étape ignorée : ACL Wayland (Pas de session Wayland active)."
  fi
}

setup_create_distrobox() {
  local recreate="${1:-0}"
  if run_as_agent distrobox list 2>/dev/null | grep -qE "(^|[[:space:]])$BOX_NAME($|[[:space:]])"; then
    if [[ "$recreate" -eq 1 ]]; then
      info "Suppression du Distrobox existant $BOX_NAME..."
      run_as_agent distrobox rm -f -Y "$BOX_NAME"
    else
      info "Le Distrobox $BOX_NAME existe déjà. Création ignorée."
      return 0
    fi
  fi

  if [[ "${WAYLAND_AVAILABLE:-0}" -eq 1 && -n "${WAYLAND_SOCKET:-}" ]]; then
    run_as_agent distrobox create --yes --name "$BOX_NAME" \
      --image "$BOX_IMAGE" \
      --volume "$SHARED_DIR:/Projets:rw" \
      --volume "$WAYLAND_SOCKET:$AGENT_RUNTIME/$WAYLAND_ALIAS"
  else
    run_as_agent distrobox create --yes --name "$BOX_NAME" \
      --image "$BOX_IMAGE" \
      --volume "$SHARED_DIR:/Projets:rw"
  fi
}

# Alias de rétrocompatibilité pour les scripts
step_install_host_packages() { setup_install_host_packages; }
step_ensure_agent_user() { setup_ensure_agent_user; }
step_setup_shared_dir() { setup_setup_shared_dir; }
step_protect_main_home() { setup_protect_main_home; }
step_ensure_subids() { setup_ensure_subids; }
ensure_agent_subids() { setup_ensure_subids; }
step_prepare_agent_runtime() { setup_prepare_agent_runtime; }
wait_for_agent_runtime() { setup_prepare_agent_runtime; }
step_apply_wayland_acl() { setup_apply_wayland_acl; }
step_create_distrobox() { setup_create_distrobox "$@"; }

write_launchers() {
  local tmp

  # 1. agent-ia-enter
  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 2 ]]; then
  cat >&2 <<'EOF_BANNER'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF_BANNER
fi

CONFIG_FILE="/etc/agent-ia-env.conf"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Configuration introuvable : $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${AGENT_USER:?AGENT_USER manquant dans $CONFIG_FILE}"
: "${AGENT_RUNTIME:?AGENT_RUNTIME manquant dans $CONFIG_FILE}"
: "${BOX_NAME:?BOX_NAME manquant dans $CONFIG_FILE}"
: "${WAYLAND_ALIAS:=wayland-agent}"

WAYLAND_SOCKET=""
if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ "$WAYLAND_DISPLAY" =~ ^/ ]]; then
    WAYLAND_SOCKET="$WAYLAND_DISPLAY"
  else
    WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  fi
  if [[ ! -S "$WAYLAND_SOCKET" ]]; then
    WAYLAND_SOCKET=""
  fi
fi

# Changer de répertoire si l'utilisateur IA n'a pas les droits de lecture/exécution sur le répertoire courant
if ! sudo -u "$AGENT_USER" test -x "$PWD" -a -r "$PWD" 2>/dev/null; then
  cd "${SHARED_DIR:-/}" 2>/dev/null || cd /
fi

umask 0002

if [[ -n "$WAYLAND_SOCKET" ]]; then
  sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR" 2>/dev/null || true
  sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$WAYLAND_SOCKET" 2>/dev/null || true

  exec sudo -H -u "$AGENT_USER" env \
    XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
    WAYLAND_DISPLAY="$WAYLAND_ALIAS" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$AGENT_RUNTIME/bus" \
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
    distrobox enter "$BOX_NAME" "$@"
else
  exec sudo -H -u "$AGENT_USER" env \
    XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$AGENT_RUNTIME/bus" \
    HOME="/home/$AGENT_USER" \
    USER="$AGENT_USER" \
    LOGNAME="$AGENT_USER" \
    SHELL=/bin/bash \
    distrobox enter "$BOX_NAME" "$@"
fi
EOF_LAUNCHER
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-ia-enter
  rm -f "$tmp"

  # 2. agent-shell
  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_SHELL'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 2 ]]; then
  cat >&2 <<'EOF_BANNER'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF_BANNER
fi

CONFIG_FILE="/etc/agent-ia-env.conf"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Configuration introuvable : $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${AGENT_USER:?AGENT_USER manquant dans $CONFIG_FILE}"
: "${AGENT_RUNTIME:?AGENT_RUNTIME manquant dans $CONFIG_FILE}"

if [[ -z "${XDG_RUNTIME_DIR:-}" || -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "Ce lanceur requiert une session Wayland active pour ouvrir un terminal graphique." >&2
  exit 1
fi

if [[ "$WAYLAND_DISPLAY" =~ ^/ ]]; then
  CURRENT_SOCKET="$WAYLAND_DISPLAY"
else
  CURRENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
fi

if [[ ! -S "$CURRENT_SOCKET" ]]; then
  echo "Socket Wayland introuvable : $CURRENT_SOCKET" >&2
  exit 1
fi

# Changer de répertoire si l'utilisateur IA n'a pas les droits de lecture/exécution sur le répertoire courant
if ! sudo -u "$AGENT_USER" test -x "$PWD" -a -r "$PWD" 2>/dev/null; then
  cd "${SHARED_DIR:-/}" 2>/dev/null || cd /
fi

sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR" 2>/dev/null || true
sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$CURRENT_SOCKET" 2>/dev/null || true

# Choix du terminal avec fallback
TERM_CMD=""
TERM_ARGS=()

if [[ -n "${PREFERRED_TERMINAL:-}" ]]; then
  if command -v "$PREFERRED_TERMINAL" >/dev/null 2>&1; then
    TERM_CMD="$PREFERRED_TERMINAL"
    case "$TERM_CMD" in
      kitty) TERM_ARGS=("--directory" "/home/$AGENT_USER") ;;
      konsole) TERM_ARGS=("--workdir" "/home/$AGENT_USER") ;;
      *) TERM_ARGS=("--working-directory" "/home/$AGENT_USER") ;;
    esac
  fi
fi

if [[ -z "$TERM_CMD" ]]; then
  # Recherche automatique des terminaux courants
  if command -v foot >/dev/null 2>&1; then
    TERM_CMD="foot"
    TERM_ARGS=("--working-directory" "/home/$AGENT_USER")
  elif command -v alacritty >/dev/null 2>&1; then
    TERM_CMD="alacritty"
    TERM_ARGS=("--working-directory" "/home/$AGENT_USER")
  elif command -v kitty >/dev/null 2>&1; then
    TERM_CMD="kitty"
    TERM_ARGS=("--directory" "/home/$AGENT_USER")
  elif command -v gnome-terminal >/dev/null 2>&1; then
    TERM_CMD="gnome-terminal"
    TERM_ARGS=("--working-directory" "/home/$AGENT_USER")
  elif command -v konsole >/dev/null 2>&1; then
    TERM_CMD="konsole"
    TERM_ARGS=("--workdir" "/home/$AGENT_USER")
  elif command -v xfce4-terminal >/dev/null 2>&1; then
    TERM_CMD="xfce4-terminal"
    TERM_ARGS=("--working-directory" "/home/$AGENT_USER")
  else
    echo "Aucun terminal graphique compatible trouvé (foot, alacritty, kitty, gnome-terminal, konsole, xfce4-terminal)." >&2
    exit 1
  fi
fi

umask 0002

exec sudo -H -u "$AGENT_USER" env \
  XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
  WAYLAND_DISPLAY="$CURRENT_SOCKET" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$AGENT_RUNTIME/bus" \
  XDG_SESSION_TYPE=wayland \
  HOME="/home/$AGENT_USER" \
  USER="$AGENT_USER" \
  LOGNAME="$AGENT_USER" \
  SHELL=/bin/bash \
  "$TERM_CMD" "${TERM_ARGS[@]}" "$@"
EOF_SHELL
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-shell
  rm -f "$tmp"

  # 3. agent-run
  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_RUN'
#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: agent-run <commande> [arguments...]" >&2
  exit 1
fi

if [[ -t 2 ]]; then
  cat >&2 <<'EOF_BANNER'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF_BANNER
fi

CONFIG_FILE="/etc/agent-ia-env.conf"
AGENT_USER="agent"
MAIN_USER="${SUDO_USER:-${USER:-$(id -un)}}"
if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

MAIN_UID="$(id -u "$MAIN_USER" 2>/dev/null || id -u)"
AGENT_UID="$(id -u "$AGENT_USER" 2>/dev/null || echo "1001")"
AGENT_RUNTIME="${AGENT_RUNTIME:-/run/user/$AGENT_UID}"

WAYLAND_SOCKET=""
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ "$WAYLAND_DISPLAY" =~ ^/ ]]; then
    WAYLAND_SOCKET="$WAYLAND_DISPLAY"
  elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  else
    WAYLAND_SOCKET="/run/user/$MAIN_UID/$WAYLAND_DISPLAY"
  fi
  if [[ ! -S "$WAYLAND_SOCKET" ]]; then
    WAYLAND_SOCKET=""
  fi
fi

# Changer de répertoire si l'utilisateur IA n'a pas les droits de lecture/exécution sur le répertoire courant
if ! sudo -u "$AGENT_USER" test -x "$PWD" -a -r "$PWD" 2>/dev/null; then
  cd "${SHARED_DIR:-/}" 2>/dev/null || cd /
fi

umask 0002

if [[ -n "$WAYLAND_SOCKET" ]]; then
  sudo setfacl -m "u:$AGENT_USER:x,m::x" "$(dirname "$WAYLAND_SOCKET")" 2>/dev/null || true
  sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$WAYLAND_SOCKET" 2>/dev/null || true

  exec sudo -H -u "$AGENT_USER" env \
    XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
    WAYLAND_DISPLAY="$WAYLAND_SOCKET" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$AGENT_RUNTIME/bus" \
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
    bash -lc 'umask 0002; exec "$@"' bash "$@"
else
  exec sudo -H -u "$AGENT_USER" env \
    XDG_RUNTIME_DIR="$AGENT_RUNTIME" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$AGENT_RUNTIME/bus" \
    HOME="/home/$AGENT_USER" \
    USER="$AGENT_USER" \
    LOGNAME="$AGENT_USER" \
    SHELL=/bin/bash \
    bash -lc 'umask 0002; exec "$@"' bash "$@"
fi
EOF_RUN
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-run
  rm -f "$tmp"

  # 4. ai
  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_AI'
#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  exec agent-ia-enter --no-workdir
elif [ "$1" = "--fix-perms" ]; then
  exec agent-fix-perms
elif [ "$1" = "--bg" ]; then
  shift
  if [ $# -eq 0 ]; then
    echo "Erreur : aucune commande spécifiée après --bg" >&2
    exit 1
  fi
  agent-ia-enter --no-workdir -- "$@" >/dev/null 2>&1 &
  disown
else
  exec agent-ia-enter --no-workdir -- "$@"
fi
EOF_AI
  run_sudo install -m 0755 "$tmp" /usr/local/bin/ai
  rm -f "$tmp"

  # 5. agent-fix-perms
  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_FIXPERMS'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/etc/agent-ia-env.conf"
if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

: "${SHARED_DIR:=/srv/ia-projets}"
: "${SHARED_GROUP:=iawork}"

if [[ ! -d "$SHARED_DIR" ]]; then
  echo "Erreur : le dossier partagé '$SHARED_DIR' n'existe pas." >&2
  exit 1
fi

echo "Correction des permissions sur '$SHARED_DIR' pour le groupe '$SHARED_GROUP'..."
sudo chown -R root:"$SHARED_GROUP" "$SHARED_DIR"
sudo chmod 2770 "$SHARED_DIR"
sudo find "$SHARED_DIR" -type d -exec chmod 2770 {} + 2>/dev/null || true
sudo chmod -R g+rwX "$SHARED_DIR" 2>/dev/null || true
sudo setfacl -R -m "g:$SHARED_GROUP:rwx,m::rwx" "$SHARED_DIR"
sudo setfacl -R -d -m "g:$SHARED_GROUP:rwx,m::rwx" "$SHARED_DIR"
echo "✓ Permissions d'écriture du groupe '$SHARED_GROUP' restaurées avec succès sur '$SHARED_DIR'."
EOF_FIXPERMS
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-fix-perms
  rm -f "$tmp"

  # 6. agent-stop
  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_STOP'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 2 ]]; then
  cat >&2 <<'EOF_BANNER'

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

EOF_BANNER
fi

usage() {
  cat <<'EOF_USAGE'
Usage: agent-stop [options]

Arrête le conteneur Distrobox, les processus et la session de l'utilisateur IA.

Options:
  --box-only       Arrête uniquement le conteneur Distrobox
  --session-only   Ferme uniquement les processus et la session utilisateur systemd
  --fix-perms      Corrige les permissions du dossier partagé avant arrêt
  -h, --help       Affiche cette aide
EOF_USAGE
}

BOX_ONLY=0
SESSION_ONLY=0
FIX_PERMS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --box-only) BOX_ONLY=1; shift ;;
    --session-only) SESSION_ONLY=1; shift ;;
    --fix-perms) FIX_PERMS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$BOX_ONLY" -eq 1 && "$SESSION_ONLY" -eq 1 ]]; then
  echo "Erreur : --box-only et --session-only sont mutuellement exclusives." >&2
  exit 1
fi

CONFIG_FILE="/etc/agent-ia-env.conf"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Configuration introuvable : $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${AGENT_USER:?AGENT_USER manquant dans $CONFIG_FILE}"
: "${BOX_NAME:?BOX_NAME manquant dans $CONFIG_FILE}"
AGENT_UID="$(id -u "$AGENT_USER" 2>/dev/null || echo "1001")"
AGENT_RUNTIME="${AGENT_RUNTIME:-/run/user/$AGENT_UID}"

if [[ "$FIX_PERMS" -eq 1 ]]; then
  if command -v agent-fix-perms >/dev/null 2>&1; then
    agent-fix-perms || true
  fi
fi

echo "Arrêt de l'environnement IA ($AGENT_USER)..."

if [[ "$SESSION_ONLY" -eq 0 ]]; then
  if command -v distrobox >/dev/null 2>&1; then
    echo "- Arrêt du conteneur Distrobox '$BOX_NAME'..."
    sudo -H -u "$AGENT_USER" env XDG_RUNTIME_DIR="$AGENT_RUNTIME" distrobox stop -Y "$BOX_NAME" 2>/dev/null || true
  fi
fi

if [[ "$BOX_ONLY" -eq 0 ]]; then
  echo "- Fermeture des processus résiduels pour l'utilisateur $AGENT_USER..."
  sudo pkill -u "$AGENT_USER" 2>/dev/null || true

  echo "- Clôture de la session systemd ($AGENT_USER)..."
  sudo loginctl terminate-user "$AGENT_USER" 2>/dev/null || true
fi

echo "✓ Environnement IA arrêté."
EOF_STOP
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-stop
  rm -f "$tmp"
}

# --- FONCTIONS DE DÉSINSTALLATION (UNINSTALL) PARTAGÉES ---

uninstall_prepare_runtime() {
  if ! id "$AGENT_USER" >/dev/null 2>&1; then
    warn "L'utilisateur $AGENT_USER n'existe pas. Certaines étapes seront ignorées."
    return 0
  fi

  AGENT_UID="$(id -u "$AGENT_USER")"
  AGENT_RUNTIME="/run/user/$AGENT_UID"
  if [[ ! -d "$AGENT_RUNTIME" ]]; then
    run_sudo install -d -m 700 -o "$AGENT_USER" -g "$AGENT_USER" "$AGENT_RUNTIME" || true
  fi
}

uninstall_disable_linger() {
  run_sudo loginctl disable-linger "$AGENT_USER" || true
}

uninstall_terminate_agent_user() {
  run_sudo loginctl terminate-user "$AGENT_USER" || true
  run_sudo pkill -u "$AGENT_USER" || true
}

uninstall_remove_distrobox() {
  run_as_agent distrobox stop -Y "$BOX_NAME" || true
  run_as_agent distrobox rm -f -Y "$BOX_NAME" || true
}

uninstall_remove_launchers() {
  run_sudo rm -f /usr/local/bin/agent-ia-enter /usr/local/bin/agent-shell /usr/local/bin/agent-run /usr/local/bin/ai /usr/local/bin/agent-stop /usr/local/bin/agent-fix-perms
}

uninstall_remove_wayland_acl() {
  local current_socket source_socket
  current_socket=""
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
    current_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  fi
  source_socket="${WAYLAND_SOURCE_SOCKET:-$current_socket}"
  if [[ -z "$source_socket" && -z "$current_socket" ]]; then
    warn "Aucun socket Wayland connu. Retrait des ACL Wayland ignoré."
    return 0
  fi
  if [[ -n "$source_socket" && -e "$source_socket" ]]; then
    run_sudo setfacl -x "u:$AGENT_USER" "$source_socket" || true
  fi
  if [[ -n "$current_socket" && "$current_socket" != "$source_socket" && -e "$current_socket" ]]; then
    run_sudo setfacl -x "u:$AGENT_USER" "$current_socket" || true
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]]; then
    run_sudo setfacl -x "u:$AGENT_USER" "$XDG_RUNTIME_DIR" || true
  fi
}

uninstall_remove_config() {
  local cfg="${CONFIG_FILE:-/etc/agent-ia-env.conf}"
  run_sudo rm -f "$cfg"
}

uninstall_remove_shared_dir() {
  run_sudo rm -rf --one-file-system "$SHARED_DIR"
}

uninstall_remove_agent_user() {
  uninstall_disable_linger
  uninstall_terminate_agent_user
  run_sudo userdel -r "$AGENT_USER"
}

uninstall_remove_agent_runtime() {
  if [[ -n "${AGENT_RUNTIME:-}" ]]; then
    run_sudo rm -rf --one-file-system "$AGENT_RUNTIME" || true
  fi
}

uninstall_remove_subids() {
  if [[ -f /etc/subuid ]]; then
    run_sudo sed -i "/^$AGENT_USER:/d" /etc/subuid
  fi
  if [[ -f /etc/subgid ]]; then
    run_sudo sed -i "/^$AGENT_USER:/d" /etc/subgid
  fi
}

uninstall_remove_group() {
  if getent group "$SHARED_GROUP" >/dev/null 2>&1; then
    run_sudo groupdel "$SHARED_GROUP" || true
  fi
}


