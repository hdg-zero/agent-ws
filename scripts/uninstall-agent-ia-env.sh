#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "\n[ERREUR] Ligne $LINENO. La désinstallation a été interrompue." >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-agent-ia-env.sh"

CONFIG_FILE="/etc/agent-ia-env.conf"

step_prepare_runtime() { uninstall_prepare_runtime; }
step_terminate_agent_user() { uninstall_terminate_agent_user; }
step_remove_distrobox() { uninstall_remove_distrobox; }
step_remove_launchers() { uninstall_remove_launchers; }
step_remove_wayland_acl() { uninstall_remove_wayland_acl; }
step_remove_config() { uninstall_remove_config; }
step_remove_shared_dir() { uninstall_remove_shared_dir; }
step_disable_linger() { uninstall_disable_linger; }
step_remove_agent_user() { uninstall_remove_agent_user; }
step_remove_agent_runtime() { uninstall_remove_agent_runtime; }
step_remove_subids() { uninstall_remove_subids; }
step_remove_group() { uninstall_remove_group; }

main() {
  require_not_root
  load_config_or_defaults "$CONFIG_FILE"

  print_agent_ws_banner
  bold "Désinstallation interactive de l'environnement IA"
  AGENT_USER="$(ask_value "Utilisateur IA" "$AGENT_USER")"
  validate_identifier "Utilisateur IA" "$AGENT_USER"
  SHARED_GROUP="$(ask_value "Groupe partagé" "$SHARED_GROUP")"
  validate_identifier "Groupe partagé" "$SHARED_GROUP"
  SHARED_DIR="$(ask_value "Dossier partagé projets" "$SHARED_DIR")"
  validate_shared_dir_for_deletion "$SHARED_DIR"
  BOX_NAME="$(ask_value "Nom du Distrobox" "$BOX_NAME")"
  validate_identifier "Nom du Distrobox" "$BOX_NAME"

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
