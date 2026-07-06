#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "\n[ERREUR] Ligne $LINENO. La configuration a été interrompue." >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-agent-ia-env.sh"

_AGENT_IA_WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$_AGENT_IA_WORK_DIR"' EXIT

wait_for_agent_runtime() {
  local tries=0

  run_sudo loginctl enable-linger "$AGENT_USER"

  while [[ ! -d "$AGENT_RUNTIME" ]] && (( tries < 20 )); do
    sleep 0.5
    tries=$((tries + 1))
  done

  if [[ ! -d "$AGENT_RUNTIME" ]]; then
    err "$AGENT_RUNTIME n'existe pas après enable-linger. Arrêt : le process validé a besoin de ce runtime réel."
    exit 1
  fi
}

ensure_agent_subids() {
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

step_apply_wayland_acl() {
  if [[ "${WAYLAND_AVAILABLE:-0}" -eq 1 ]]; then
    run_sudo setfacl -m "u:$AGENT_USER:x,m::x" "$XDG_RUNTIME_DIR"
    run_sudo setfacl -m "u:$AGENT_USER:rw,m::rwx" "$WAYLAND_SOCKET"
  else
    info "Étape ignorée : ACL Wayland (Pas de session Wayland active)."
  fi
}

step_prepare_agent_runtime() {
  AGENT_UID="$(id -u "$AGENT_USER")"
  AGENT_RUNTIME="/run/user/$AGENT_UID"
  wait_for_agent_runtime
}

step_create_distrobox() {
  if run_as_agent distrobox list 2>/dev/null | grep -qE "(^|[[:space:]])$BOX_NAME($|[[:space:]])"; then
    warn "Le Distrobox $BOX_NAME existe déjà."
    if ask_yes_no "Le supprimer et le recréer ?" "y"; then
      run_as_agent distrobox rm "$BOX_NAME"
    else
      return 0
    fi
  fi

  if [[ "${WAYLAND_AVAILABLE:-0}" -eq 1 ]]; then
    run_as_agent distrobox create --name "$BOX_NAME" \
      --image "$BOX_IMAGE" \
      --volume "$SHARED_DIR:/Projets:rw" \
      --volume "$WAYLAND_SOCKET:$AGENT_RUNTIME/$WAYLAND_ALIAS"
  else
    run_as_agent distrobox create --name "$BOX_NAME" \
      --image "$BOX_IMAGE" \
      --volume "$SHARED_DIR:/Projets:rw"
  fi
}

main() {
  require_not_root
  set_default_setup_values
  validate_wayland_session

  print_agent_ws_banner
  bold "Installation interactive de l'environnement IA isolé"
  echo "Ce script reproduit le process manuel validé : utilisateur agent, SubUID/SubGID valides, runtime systemd réel, puis création Distrobox."

  AGENT_USER="$(ask_value "Nom de l'utilisateur IA" "$AGENT_USER")"
  validate_identifier "Nom d'utilisateur IA" "$AGENT_USER"
  SHARED_GROUP="$(ask_value "Nom du groupe partagé" "$SHARED_GROUP")"
  validate_identifier "Nom du groupe partagé" "$SHARED_GROUP"
  SHARED_DIR="$(ask_value "Dossier partagé projets" "$SHARED_DIR")"
  validate_path "Dossier partagé" "$SHARED_DIR"
  BOX_NAME="$(ask_value "Nom du Distrobox" "$BOX_NAME")"
  validate_identifier "Nom du Distrobox" "$BOX_NAME"
  BOX_IMAGE="$(ask_value "Image OCI du Distrobox" "$BOX_IMAGE")"
  WAYLAND_ALIAS="$(ask_value "Nom du socket Wayland dans le conteneur" "$WAYLAND_ALIAS")"
  validate_identifier "Alias socket Wayland" "$WAYLAND_ALIAS"

  # Détection automatique des terminaux graphiques installés sur l'hôte
  local detected_terms=()
  for t in foot alacritty kitty gnome-terminal konsole xfce4-terminal; do
    if command_exists "$t"; then
      detected_terms+=("$t")
    fi
  done

  local default_term="foot"
  if [[ ${#detected_terms[@]} -gt 0 ]]; then
    if command_exists foot; then
      default_term="foot"
    else
      default_term="${detected_terms[0]}"
    fi
  fi

  PREFERRED_TERMINAL="$(ask_value "Terminal graphique préféré pour agent-shell" "$default_term")"
  validate_identifier "Terminal graphique préféré" "$PREFERRED_TERMINAL"

  if ! command_exists "$PREFERRED_TERMINAL"; then
    warn "Le terminal graphique '$PREFERRED_TERMINAL' n'est pas installé sur l'hôte."
  fi

  WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

  print_setup_summary
  ask_yes_no "Continuer avec cette configuration ?" "y" || exit 0

  if confirm_step "1. Paquets hôte" "Installe podman, distrobox, acl, fuse-overlayfs, slirp4netns et passt."; then
    step_install_host_packages
  fi

  if confirm_step "2. Utilisateur IA" "Crée $AGENT_USER si nécessaire et verrouille son mot de passe."; then
    step_ensure_agent_user
  fi

  if confirm_step "3. Groupe et dossier partagé" "Configure $SHARED_GROUP et $SHARED_DIR comme dans le process manuel."; then
    step_setup_shared_dir
  fi

  if confirm_step "4. Protection du home principal" "Applique chmod 700 sur /home/$MAIN_USER et vérifie que $AGENT_USER ne peut pas le lire."; then
    step_protect_main_home
  fi

  if confirm_step "5. Vérification SubUID/SubGID pour $AGENT_USER" "Vérifie que $AGENT_USER possède une plage /etc/subuid et /etc/subgid. Si elle manque, une plage libre est ajoutée."; then
    ensure_agent_subids
  fi

  if confirm_step "6. Runtime agent via linger" "Active le linger et attend le runtime réel /run/user/<uid-agent>."; then
    step_prepare_agent_runtime
  else
    AGENT_UID="$(id -u "$AGENT_USER")"
    AGENT_RUNTIME="/run/user/$AGENT_UID"
  fi

  if [[ "${WAYLAND_AVAILABLE:-0}" -eq 1 ]]; then
    if confirm_step "7. ACL Wayland" "Donne à $AGENT_USER l'accès au runtime et au socket Wayland courant."; then
      step_apply_wayland_acl
    fi
  else
    info "Étape ignorée : ACL Wayland (Pas de session Wayland active)."
  fi

  write_config_file

  if confirm_step "8. Création du Distrobox" "Crée $BOX_NAME comme $AGENT_USER avec $SHARED_DIR monté dans /Projets et $WAYLAND_SOCKET monté dans $AGENT_RUNTIME/$WAYLAND_ALIAS."; then
    step_create_distrobox
  fi

  if confirm_step "9. Lanceurs" "Installe agent-ia-enter, agent-shell, agent-run et ai."; then
    write_launchers
  fi

  bold "Installation terminée"
  cat <<EOF_DONE

Commandes utiles :

  agent-ia-enter
  agent-shell
  agent-run <commande>
  ai <commande>

Dans le Distrobox :

  cd /Projets
EOF_DONE
}

main "$@"
