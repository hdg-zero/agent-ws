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
  --preferred-terminal NAME
  --recreate-box
  --update             Met à jour les lanceurs, umask 0002 et la config sur une installation existante
  --launchers-only     Installe ou met à jour uniquement les lanceurs
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

# shellcheck disable=SC2034
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
      --preferred-terminal) PREFERRED_TERMINAL="$2"; shift 2 ;;
      --recreate-box) RECREATE_BOX=1; shift ;;
      --update)
        INSTALL_HOST_PACKAGES=0
        SETUP_AGENT_USER=1
        SETUP_SHARED_DIR=0
        PROTECT_MAIN_HOME=0
        ENSURE_SUBIDS=0
        PREPARE_AGENT_RUNTIME=0
        APPLY_WAYLAND_ACL=0
        CREATE_DISTROBOX=0
        INSTALL_LAUNCHERS=1
        shift
        ;;
      --launchers-only)
        INSTALL_HOST_PACKAGES=0
        SETUP_AGENT_USER=0
        SETUP_SHARED_DIR=0
        PROTECT_MAIN_HOME=0
        ENSURE_SUBIDS=0
        PREPARE_AGENT_RUNTIME=0
        APPLY_WAYLAND_ACL=0
        CREATE_DISTROBOX=0
        INSTALL_LAUNCHERS=1
        shift
        ;;
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

step_create_distrobox_noninteractive() {
  setup_create_distrobox "$RECREATE_BOX"
}

main() {
  require_not_root
  parse_args "$@"
  validate_identifier "Nom d'utilisateur IA" "$AGENT_USER"
  validate_identifier "Nom du groupe partagé" "$SHARED_GROUP"
  validate_identifier "Nom du Distrobox" "$BOX_NAME"
  validate_identifier "Alias socket Wayland" "$WAYLAND_ALIAS"
  validate_identifier "Terminal graphique préféré" "$PREFERRED_TERMINAL"
  validate_path "Dossier partagé" "$SHARED_DIR"
  validate_wayland_session

  if ! command_exists "$PREFERRED_TERMINAL"; then
    warn "Le terminal graphique '$PREFERRED_TERMINAL' n'est pas installé sur l'hôte."
  fi

  AGENT_UID="${AGENT_UID:-}"
  AGENT_RUNTIME="${AGENT_RUNTIME:-}"
  WAYLAND_SOCKET="${WAYLAND_SOCKET:-}"

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
  run_step "$CREATE_DISTROBOX" "Création du Distrobox" step_create_distrobox_noninteractive
  run_step "$INSTALL_LAUNCHERS" "Installation des lanceurs" write_launchers

  info "Configuration non interactive terminée."
}

main "$@"
