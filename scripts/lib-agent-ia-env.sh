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

