#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "\n[ERREUR] Ligne $LINENO. La désinstallation non interactive a été interrompue." >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-agent-ia-env.sh"

CONFIG_FILE="/etc/agent-ia-env.conf"
REMOVE_BOX=0
REMOVE_LAUNCHERS=0
REMOVE_WAYLAND_ACL=0
REMOVE_CONFIG=0
REMOVE_SHARED_DIR=0
DISABLE_LINGER=0
TERMINATE_AGENT_USER=0
REMOVE_AGENT_USER=0
REMOVE_AGENT_RUNTIME=0
REMOVE_SUBIDS=0
REMOVE_GROUP=0
REMOVE_ALL=0

log_step() {
  info "$1"
}

run_enabled_step() {
  local enabled="$1"
  local label="$2"
  local fn="$3"

  if [[ "$enabled" -eq 1 ]]; then
    log_step "$label"
    "$fn"
  else
    info "Étape ignorée : $label"
  fi
}

usage() {
  cat <<'EOF'
Usage: uninstall-agent-ia-env-noninteractive.sh [options]

Options:
  --agent-user NAME
  --shared-group NAME
  --shared-dir PATH
  --box-name NAME
  --remove-box
  --remove-launchers
  --remove-wayland-acl
  --remove-config
  --remove-shared-dir
  --disable-linger
  --terminate-agent-user
  --remove-agent-user
  --remove-agent-runtime
  --remove-subids
  --remove-group
  --all
  --help
EOF
}

parse_args() {
  load_config_or_defaults "$CONFIG_FILE"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent-user) AGENT_USER="$2"; shift 2 ;;
      --shared-group) SHARED_GROUP="$2"; shift 2 ;;
      --shared-dir) SHARED_DIR="$2"; shift 2 ;;
      --box-name) BOX_NAME="$2"; shift 2 ;;
      --remove-box) REMOVE_BOX=1; shift ;;
      --remove-launchers) REMOVE_LAUNCHERS=1; shift ;;
      --remove-wayland-acl) REMOVE_WAYLAND_ACL=1; shift ;;
      --remove-config) REMOVE_CONFIG=1; shift ;;
      --remove-shared-dir) REMOVE_SHARED_DIR=1; shift ;;
      --disable-linger) DISABLE_LINGER=1; shift ;;
      --terminate-agent-user) TERMINATE_AGENT_USER=1; shift ;;
      --remove-agent-user) REMOVE_AGENT_USER=1; shift ;;
      --remove-agent-runtime) REMOVE_AGENT_RUNTIME=1; shift ;;
      --remove-subids) REMOVE_SUBIDS=1; shift ;;
      --remove-group) REMOVE_GROUP=1; shift ;;
      --all) REMOVE_ALL=1; shift ;;
      --help) usage; exit 0 ;;
      *) err "Option inconnue : $1"; usage; exit 1 ;;
    esac
  done

  if [[ "$REMOVE_ALL" -eq 1 ]]; then
    REMOVE_BOX=1
    REMOVE_LAUNCHERS=1
    REMOVE_WAYLAND_ACL=1
    REMOVE_CONFIG=1
    REMOVE_SHARED_DIR=1
    DISABLE_LINGER=1
    TERMINATE_AGENT_USER=1
    REMOVE_AGENT_USER=1
    REMOVE_AGENT_RUNTIME=1
    REMOVE_SUBIDS=1
    REMOVE_GROUP=1
  fi
}

has_requested_action() {
  [[ "$REMOVE_BOX" -eq 1 ]] \
    || [[ "$REMOVE_LAUNCHERS" -eq 1 ]] \
    || [[ "$REMOVE_WAYLAND_ACL" -eq 1 ]] \
    || [[ "$REMOVE_CONFIG" -eq 1 ]] \
    || [[ "$REMOVE_SHARED_DIR" -eq 1 ]] \
    || [[ "$DISABLE_LINGER" -eq 1 ]] \
    || [[ "$TERMINATE_AGENT_USER" -eq 1 ]] \
    || [[ "$REMOVE_AGENT_USER" -eq 1 ]] \
    || [[ "$REMOVE_AGENT_RUNTIME" -eq 1 ]] \
    || [[ "$REMOVE_SUBIDS" -eq 1 ]] \
    || [[ "$REMOVE_GROUP" -eq 1 ]]
}

prepare_runtime() { uninstall_prepare_runtime; }
remove_box() { uninstall_remove_distrobox; }
remove_launchers() { uninstall_remove_launchers; }
remove_wayland_acl() { uninstall_remove_wayland_acl; }
remove_config() { uninstall_remove_config; }
remove_shared_dir() { uninstall_remove_shared_dir; }
disable_linger() { uninstall_disable_linger; }
terminate_agent_user() { uninstall_terminate_agent_user; }
remove_agent_user() { uninstall_remove_agent_user; }
remove_agent_runtime() { uninstall_remove_agent_runtime; }
remove_subids() { uninstall_remove_subids; }
remove_group() { uninstall_remove_group; }

main() {
  require_not_root
  parse_args "$@"
  validate_identifier "Utilisateur IA" "$AGENT_USER"
  validate_identifier "Groupe partagé" "$SHARED_GROUP"
  validate_shared_dir_for_deletion "$SHARED_DIR"
  validate_identifier "Nom du Distrobox" "$BOX_NAME"

  print_agent_ws_banner
  if ! has_requested_action; then
    err "Aucune action demandée. Utilise des options explicites ou --all."
    usage
    exit 1
  fi

  info "Démarrage de la désinstallation non interactive."
  log_step "Paramètres : agent_user=$AGENT_USER, shared_group=$SHARED_GROUP, shared_dir=$SHARED_DIR, box_name=$BOX_NAME"
  prepare_runtime
  if [[ -n "${AGENT_RUNTIME:-}" ]]; then
    log_step "Runtime utilisateur IA détecté : $AGENT_RUNTIME"
  fi

  if [[ "$REMOVE_BOX" -eq 1 ]]; then
    if [[ -n "${AGENT_USER:-}" ]] && id "$AGENT_USER" >/dev/null 2>&1; then
      run_enabled_step 1 "Suppression du Distrobox" remove_box
    else
      info "Étape ignorée : Suppression du Distrobox (utilisateur IA introuvable)"
    fi
  else
    info "Étape ignorée : Suppression du Distrobox"
  fi

  run_enabled_step "$REMOVE_LAUNCHERS" "Suppression des lanceurs" remove_launchers
  run_enabled_step "$REMOVE_WAYLAND_ACL" "Suppression des ACL Wayland" remove_wayland_acl
  run_enabled_step "$REMOVE_CONFIG" "Suppression du fichier de configuration" remove_config
  run_enabled_step "$REMOVE_SHARED_DIR" "Suppression du dossier partagé" remove_shared_dir

  if [[ "$TERMINATE_AGENT_USER" -eq 1 ]]; then
    if [[ -n "${AGENT_USER:-}" ]] && id "$AGENT_USER" >/dev/null 2>&1; then
      run_enabled_step 1 "Arrêt des sessions et processus de l'utilisateur IA" terminate_agent_user
    else
      info "Étape ignorée : Arrêt de l'utilisateur IA (introuvable)"
    fi
  else
    info "Étape ignorée : Arrêt de l'utilisateur IA"
  fi

  if [[ "$DISABLE_LINGER" -eq 1 ]]; then
    if [[ -n "${AGENT_USER:-}" ]]; then
      run_enabled_step 1 "Désactivation du linger systemd" disable_linger
    else
      info "Étape ignorée : Désactivation du linger systemd (utilisateur IA non défini)"
    fi
  else
    info "Étape ignorée : Désactivation du linger systemd"
  fi

  if [[ "$REMOVE_AGENT_USER" -eq 1 ]]; then
    if [[ -n "${AGENT_USER:-}" ]] && id "$AGENT_USER" >/dev/null 2>&1; then
      run_enabled_step 1 "Suppression de l'utilisateur IA" remove_agent_user
    else
      info "Étape ignorée : Suppression de l'utilisateur IA (introuvable)"
    fi
  else
    info "Étape ignorée : Suppression de l'utilisateur IA"
  fi

  run_enabled_step "$REMOVE_AGENT_RUNTIME" "Suppression du runtime /run/user de l'utilisateur IA" remove_agent_runtime
  run_enabled_step "$REMOVE_SUBIDS" "Suppression des entrées SubUID/SubGID" remove_subids

  if [[ "$REMOVE_GROUP" -eq 1 ]]; then
    if getent group "$SHARED_GROUP" >/dev/null 2>&1; then
      run_enabled_step 1 "Suppression du groupe partagé" remove_group
    else
      info "Étape ignorée : Suppression du groupe partagé (introuvable)"
    fi
  else
    info "Étape ignorée : Suppression du groupe partagé"
  fi

  info "Désinstallation non interactive terminée."
}

main "$@"
