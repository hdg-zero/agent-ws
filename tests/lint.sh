#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Vérification de la syntaxe Bash ==="
bash -n "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/tests/*.sh
echo "✓ Syntaxe Bash valide."

if command -v shellcheck >/dev/null 2>&1; then
  echo "=== Vérification ShellCheck ==="
  shellcheck "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/tests/*.sh
  echo "✓ ShellCheck passé avec succès (0 avertissement, 0 erreur)."
else
  echo "Avertissement : shellcheck n'est pas installé sur le système."
fi
