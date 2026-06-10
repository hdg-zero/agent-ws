#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "\n[ERREUR] Ligne $LINENO. La désinstallation a été interrompue." >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-agent-ia-env.sh"

CONFIG_FILE="/etc/agent-ia-env.conf"

step_prepare_runtime() {
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

step_terminate_agent_user() {
  run_sudo loginctl terminate-user "$AGENT_USER" || true
  run_sudo pkill -u "$AGENT_USER" || true
}

step_remove_distrobox() {
  run_as_agent distrobox stop "$BOX_NAME" || true
  run_as_agent distrobox rm "$BOX_NAME" || true
}

step_remove_launchers() {
  run_sudo rm -f /usr/local/bin/agent-ia-enter /usr/local/bin/agent-shell /usr/local/bin/agent-run /usr/local/bin/ai
}

step_remove_wayland_acl() {
  local current_socket source_socket
  current_socket=""
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
    current_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  fi
  source_socket="${WAYLAND_SOURCE_SOCKET:-$current_socket}"
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

step_remove_config() {
  run_sudo rm -f "$CONFIG_FILE"
}

step_remove_shared_dir() {
  run_sudo rm -rf --one-file-system "$SHARED_DIR"
}

step_disable_linger() {
  run_sudo loginctl disable-linger "$AGENT_USER" || true
}

step_remove_agent_user() {
  step_terminate_agent_user
  run_sudo userdel -r "$AGENT_USER"
}

step_remove_agent_runtime() {
  if [[ -n "${AGENT_RUNTIME:-}" ]]; then
    run_sudo rm -rf --one-file-system "$AGENT_RUNTIME" || true
  fi
}

step_remove_subids() {
  run_sudo sed -i "/^$AGENT_USER:/d" /etc/subuid
  run_sudo sed -i "/^$AGENT_USER:/d" /etc/subgid
}

step_remove_group() {
  run_sudo groupdel "$SHARED_GROUP"
}

main() {
  require_not_root
  load_config_or_defaults "$CONFIG_FILE"

  print_agent_ws_banner
  bold "Désinstallation interactive de l'environnement IA"
  AGENT_USER="$(ask_value "Utilisateur IA" "$AGENT_USER")"
  SHARED_GROUP="$(ask_value "Groupe partagé" "$SHARED_GROUP")"
  SHARED_DIR="$(ask_value "Dossier partagé projets" "$SHARED_DIR")"
  BOX_NAME="$(ask_value "Nom du Distrobox" "$BOX_NAME")"

  step_prepare_runtime

  cat <<EOF

Configuration ciblée :
  Utilisateur IA  : $AGENT_USER
  Groupe partagé  : $SHARED_GROUP
  Dossier partagé : $SHARED_DIR
  Distrobox       : $BOX_NAME
  Config          : $CONFIG_FILE
EOF

  ask_yes_no "Continuer la désinstallation ?" "n" || exit 0

  if id "$AGENT_USER" >/dev/null 2>&1; then
    if ask_yes_no "Arrêter et supprimer le Distrobox $BOX_NAME de $AGENT_USER ?" "y"; then
      step_remove_distrobox
    fi
  fi

  if ask_yes_no "Supprimer les lanceurs /usr/local/bin/agent-ia-enter, /usr/local/bin/agent-shell, /usr/local/bin/agent-run et /usr/local/bin/ai ?" "y"; then
    step_remove_launchers
  fi

  if [[ -n "${WAYLAND_SOURCE_SOCKET:-}" || ( -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" ) ]]; then
    if ask_yes_no "Retirer les ACL Wayland courantes pour $AGENT_USER si elles existent ?" "y"; then
      step_remove_wayland_acl
    fi
  fi

  if [[ -f "$CONFIG_FILE" ]]; then
    if ask_yes_no "Supprimer $CONFIG_FILE ?" "y"; then
      step_remove_config
    fi
  fi

  if [[ -d "$SHARED_DIR" ]]; then
    warn "Le dossier partagé peut contenir des projets importants."
    if ask_yes_no "Supprimer définitivement $SHARED_DIR et tout son contenu ?" "n"; then
      read -r -p "Pour confirmer, tape exactement le chemin à supprimer : " confirm_path
      if [[ "$confirm_path" == "$SHARED_DIR" ]]; then
        step_remove_shared_dir
      else
        warn "Chemin non confirmé. Suppression du dossier partagé ignorée."
      fi
    fi
  fi

  if id "$AGENT_USER" >/dev/null 2>&1; then
    if ask_yes_no "Arrêter les sessions et processus de $AGENT_USER ?" "y"; then
      step_terminate_agent_user
    fi

    if ask_yes_no "Désactiver le linger systemd pour $AGENT_USER ?" "y"; then
      step_disable_linger
    fi

    if ask_yes_no "Supprimer l'utilisateur $AGENT_USER et son home /home/$AGENT_USER ?" "n"; then
      warn "Cette action supprime /home/$AGENT_USER, y compris caches, configs, tokens et outils installés."
      if ask_yes_no "Confirmer userdel -r $AGENT_USER ?" "n"; then
        step_remove_agent_user
        step_remove_agent_runtime
        if ask_yes_no "Supprimer les entrées $AGENT_USER dans /etc/subuid et /etc/subgid ?" "y"; then
          step_remove_subids
        fi
      fi
    fi
  fi

  if getent group "$SHARED_GROUP" >/dev/null 2>&1; then
    warn "Groupe $SHARED_GROUP, membres actuels : $(getent group "$SHARED_GROUP" | awk -F: '{print $4}')"
    if ask_yes_no "Supprimer le groupe $SHARED_GROUP ?" "n"; then
      step_remove_group
    fi
  fi

  bold "Désinstallation terminée"
  cat <<EOF

À vérifier manuellement si besoin :

  getent passwd $AGENT_USER
  getent group $SHARED_GROUP
  ls -ld $SHARED_DIR
  ls -l /usr/local/bin/agent-ia-enter /usr/local/bin/agent-shell /usr/local/bin/agent-run /usr/local/bin/ai

Les paquets hôte podman, distrobox et acl ne sont pas désinstallés automatiquement, car ils peuvent être utilisés par autre chose.
EOF
}

main "$@"
