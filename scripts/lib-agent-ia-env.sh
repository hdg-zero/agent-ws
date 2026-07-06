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

# Valide qu'un chemin est absolu et ne contient que des caractères sûrs.
validate_path() {
  local label="$1" value="$2"
  if [[ ! "$value" =~ ^/[a-zA-Z0-9/_.-]+$ ]]; then
    err "$label invalide : '$value'. Le chemin doit être absolu et ne contenir que des caractères sûrs."
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
  MAIN_USER="${MAIN_USER:-$(id -un)}"
  AGENT_USER="${AGENT_USER:-agent}"
  SHARED_GROUP="${SHARED_GROUP:-iawork}"
  SHARED_DIR="${SHARED_DIR:-/srv/ia-projets}"
  BOX_NAME="${BOX_NAME:-agent-ia}"
  BOX_IMAGE="${BOX_IMAGE:-docker.io/library/archlinux:latest}"
  WAYLAND_ALIAS="${WAYLAND_ALIAS:-wayland-hdg}"
  PREFERRED_TERMINAL="${PREFERRED_TERMINAL:-foot}"
}

load_config_or_defaults() {
  local config_file="${1:-/etc/agent-ia-env.conf}"
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
  local tmp config_file="${1:-/etc/agent-ia-env.conf}"
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
AGENT_UID="$AGENT_UID"
AGENT_RUNTIME="$AGENT_RUNTIME"
PREFERRED_TERMINAL="${PREFERRED_TERMINAL:-foot}"
EOF_CONF
  run_sudo install -m 0644 "$tmp" "$config_file"
  rm -f "$tmp"
}

validate_wayland_session() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" || -z "${WAYLAND_DISPLAY:-}" ]]; then
    err "XDG_RUNTIME_DIR ou WAYLAND_DISPLAY est vide. Lance ce script depuis ta session Hyprland/Wayland."
    exit 1
  fi

  WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  if [[ ! -S "$WAYLAND_SOCKET" ]]; then
    err "Le socket Wayland n'existe pas ou n'est pas un socket : $WAYLAND_SOCKET"
    exit 1
  fi
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

# Valide qu'un dossier partagé n'est pas un répertoire système critique avant suppression.
validate_shared_dir_for_deletion() {
  local value="$1"
  validate_path "Dossier partagé" "$value"
  local blacklisted=( "/" "/home" "/usr" "/var" "/etc" "/bin" "/lib" "/boot" "/root" "/sys" "/proc" "/dev" "/run" )
  for path in "${blacklisted[@]}"; do
    if [[ "$value" == "$path" || "$value" == "$path/" ]]; then
      err "Suppression interdite pour le répertoire système critique : $value"
      exit 1
    fi
  done
}

write_launchers() {
  local tmp

  # 1. agent-ia-enter
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

: "${AGENT_USER:?AGENT_USER manquant dans $CONFIG_FILE}"
: "${AGENT_RUNTIME:?AGENT_RUNTIME manquant dans $CONFIG_FILE}"
: "${BOX_NAME:?BOX_NAME manquant dans $CONFIG_FILE}"
: "${WAYLAND_ALIAS:?WAYLAND_ALIAS manquant dans $CONFIG_FILE}"

if [[ -z "${XDG_RUNTIME_DIR:-}" || -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "Ce lanceur doit être exécuté depuis la session Wayland." >&2
  exit 1
fi

CURRENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
if [[ ! -S "$CURRENT_SOCKET" ]]; then
  echo "Socket Wayland introuvable : $CURRENT_SOCKET" >&2
  exit 1
fi

# Changer de répertoire si l'utilisateur IA n'a pas les droits de lecture/exécution sur le répertoire courant
if ! sudo -u "$AGENT_USER" test -x "$PWD" -a -r "$PWD" 2>/dev/null; then
  cd "${SHARED_DIR:-/}" 2>/dev/null || cd /
fi

sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR"
sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$CURRENT_SOCKET"

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
EOF_LAUNCHER
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-ia-enter

  # 2. agent-shell
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

: "${AGENT_USER:?AGENT_USER manquant dans $CONFIG_FILE}"
: "${AGENT_RUNTIME:?AGENT_RUNTIME manquant dans $CONFIG_FILE}"

if [[ -z "${XDG_RUNTIME_DIR:-}" || -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "Ce lanceur doit être exécuté depuis la session Wayland." >&2
  exit 1
fi

CURRENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
if [[ ! -S "$CURRENT_SOCKET" ]]; then
  echo "Socket Wayland introuvable : $CURRENT_SOCKET" >&2
  exit 1
fi

# Changer de répertoire si l'utilisateur IA n'a pas les droits de lecture/exécution sur le répertoire courant
if ! sudo -u "$AGENT_USER" test -x "$PWD" -a -r "$PWD" 2>/dev/null; then
  cd "${SHARED_DIR:-/}" 2>/dev/null || cd /
fi

sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR"
sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$CURRENT_SOCKET"

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

  # 3. agent-run
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

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "Erreur : la variable WAYLAND_DISPLAY n'est pas définie dans l'environnement actuel." >&2
  exit 1
fi
MAIN_WAYLAND_SOCKET="/run/user/$MAIN_UID/$WAYLAND_DISPLAY"
if [[ ! -S "$MAIN_WAYLAND_SOCKET" ]]; then
  echo "Erreur : Le socket Wayland n'existe pas ou n'est pas un socket valide à l'emplacement $MAIN_WAYLAND_SOCKET" >&2
  exit 1
fi

# Changer de répertoire si l'utilisateur IA n'a pas les droits de lecture/exécution sur le répertoire courant
if ! sudo -u "$AGENT_USER" test -x "$PWD" -a -r "$PWD" 2>/dev/null; then
  cd "${SHARED_DIR:-/}" 2>/dev/null || cd /
fi

sudo setfacl -m "u:$AGENT_USER:x,m::x" "/run/user/$MAIN_UID"
sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$MAIN_WAYLAND_SOCKET"

exec sudo -H -u "$AGENT_USER" env \
  XDG_RUNTIME_DIR="/run/user/$AGENT_UID" \
  WAYLAND_DISPLAY="$MAIN_WAYLAND_SOCKET" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$AGENT_UID/bus" \
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
  bash -lc 'exec "$@"' bash "$@"
EOF_RUN
  run_sudo install -m 0755 "$tmp" /usr/local/bin/agent-run

  # 4. ai
  tmp="$(_make_temp)"
  cat > "$tmp" <<'EOF_AI'
#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  exec agent-ia-enter --no-workdir
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
}

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

uninstall_terminate_agent_user() {
  run_sudo loginctl terminate-user "$AGENT_USER" || true
  run_sudo pkill -u "$AGENT_USER" || true
}

uninstall_remove_distrobox() {
  run_as_agent distrobox stop "$BOX_NAME" || true
  run_as_agent distrobox rm "$BOX_NAME" || true
}

uninstall_remove_launchers() {
  run_sudo rm -f /usr/local/bin/agent-ia-enter /usr/local/bin/agent-shell /usr/local/bin/agent-run /usr/local/bin/ai
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
  run_sudo rm -f "$CONFIG_FILE"
}

uninstall_remove_shared_dir() {
  run_sudo rm -rf --one-file-system "$SHARED_DIR"
}

uninstall_disable_linger() {
  run_sudo loginctl disable-linger "$AGENT_USER" || true
}

uninstall_remove_agent_user() {
  uninstall_terminate_agent_user
  run_sudo userdel -r "$AGENT_USER"
}

uninstall_remove_agent_runtime() {
  if [[ -n "${AGENT_RUNTIME:-}" ]]; then
    run_sudo rm -rf --one-file-system "$AGENT_RUNTIME" || true
  fi
}

uninstall_remove_subids() {
  run_sudo sed -i "/^$AGENT_USER:/d" /etc/subuid
  run_sudo sed -i "/^$AGENT_USER:/d" /etc/subgid
}

uninstall_remove_group() {
  run_sudo groupdel "$SHARED_GROUP"
}


