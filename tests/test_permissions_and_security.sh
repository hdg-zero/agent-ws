#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../scripts/lib-agent-ia-env.sh"

FAILED=0

assert_fail() {
  local desc="$1"
  shift
  # Exécution dans un sous-shell car les fonctions d'erreur appellent exit 1
  if ( "$@" ) >/dev/null 2>&1; then
    echo "❌ Échec attendu mais commande réussie : $desc" >&2
    FAILED=$((FAILED + 1))
  else
    echo "✓ Rejet correct : $desc"
  fi
}

assert_success() {
  local desc="$1"
  shift
  if ( "$@" ); then
    echo "✓ Succès : $desc"
  else
    echo "❌ Échec inattendu : $desc" >&2
    FAILED=$((FAILED + 1))
  fi
}

echo "=== 1. Test de validation des chemins (validate_path) ==="
assert_success "Chemin absolu valide" validate_path "Test" "/srv/ia-projets"
assert_success "Chemin avec sous-dossiers" validate_path "Test" "/tmp/agent-ws/workspace-01"
assert_fail "Chemin relatif simple" validate_path "Test" "relative/path"
assert_fail "Chemin avec traversée .." validate_path "Test" "/var/../etc"
assert_fail "Chemin avec traversée .. imbriquée" validate_path "Test" "/home/agent/../../etc"
assert_fail "Chemin avec caractères spéciaux" validate_path "Test" "/srv/ia-projets;rm -rf /"

echo "=== 2. Test de sécurité sur la suppression (validate_shared_dir_for_deletion) ==="
export MAIN_USER="mainuser"
export AGENT_USER="agent"

assert_fail "Suppression de la racine /" validate_shared_dir_for_deletion "/"
assert_fail "Suppression de /etc" validate_shared_dir_for_deletion "/etc"
assert_fail "Suppression de /home" validate_shared_dir_for_deletion "/home"
assert_fail "Suppression de /home/mainuser" validate_shared_dir_for_deletion "/home/mainuser"
assert_fail "Suppression de /home/agent" validate_shared_dir_for_deletion "/home/agent"
assert_fail "Bypass traversal vers /etc via /var/../etc" validate_shared_dir_for_deletion "/var/../etc"
assert_fail "Bypass traversal vers / via /home/../" validate_shared_dir_for_deletion "/home/../"
assert_success "Dossier projet légitime /srv/ia-projets" validate_shared_dir_for_deletion "/srv/ia-projets"
assert_success "Dossier temporaire légitime /srv/test-projects" validate_shared_dir_for_deletion "/srv/test-projects"

echo "=== 3. Test POSIX ACL & Umask 0002 ==="
TEST_DIR="$(mktemp -d)"
# Configuration d'une ACL par défaut sur TEST_DIR
setfacl -d -m "g::rwx,m::rwx" "$TEST_DIR"
(
  # Simulation avec umask 0002
  umask 0002
  TEST_FILE="$TEST_DIR/test_created_by_agent.txt"
  # Mode 0666 & ~0002 = 0664 (standard d'ouverture dans les éditeurs / outils)
  python3 -c "import os; fd = os.open('$TEST_FILE', os.O_CREAT|os.O_WRONLY, 0o666 & ~0o002); os.close(fd)"
  
  # Vérifier que le masque ACL est rw- et non r--
  ACL_OUT="$(getfacl "$TEST_FILE" 2>/dev/null)"
  if echo "$ACL_OUT" | grep -q "mask::rw-"; then
    echo "✓ Umask 0002 préserve le masque d'ACL en rw- (droits d'écriture conservés pour le groupe)"
  else
    echo "❌ Le masque d'ACL n'est pas rw- : $ACL_OUT" >&2
    exit 1
  fi
) || FAILED=$((FAILED + 1))
rm -rf "$TEST_DIR"

echo "=== 4. Test de présence du mécanisme de restauration du runtime dans les lanceurs ==="
# shellcheck disable=SC2016
assert_success "Restauration du runtime dans setup_prepare_agent_runtime" grep -F -q 'user@$AGENT_UID.service' "$SCRIPT_DIR/../scripts/lib-agent-ia-env.sh"
# shellcheck disable=SC2016
OCCURRENCES="$(grep -F -c 'user@$AGENT_UID.service' "$SCRIPT_DIR/../scripts/lib-agent-ia-env.sh" || true)"
if [[ "$OCCURRENCES" -ge 5 ]]; then
  echo "✓ Les 5 points de contrôle du runtime sont configurés ($OCCURRENCES détectés)"
else
  echo "❌ Points de contrôle du runtime manquants ($OCCURRENCES détectés, attendu au moins 5)" >&2
  FAILED=$((FAILED + 1))
fi

if [[ $FAILED -eq 0 ]]; then
  echo "======================================="
  echo "🎉 Tous les tests unitaires ont réussi !"
  echo "======================================="
  exit 0
else
  echo "======================================="
  echo "💥 $FAILED test(s) ont échoué."
  echo "======================================="
  exit 1
fi
