# Agent-WS

```text

███████████▀████████████████████████████████████████████
██▀▄─██─▄▄▄▄█▄─▄▄─█▄─▀█▄─▄█─▄─▄─█▀▀▀▀▀██▄─█▀▀▀█─▄█─▄▄▄▄█
██─▀─██─██▄─██─▄█▀██─█▄▀─████─███████████─█─█─█─██▄▄▄▄─█
▀▄▄▀▄▄▀▄▄▄▄▄▀▄▄▄▄▄▀▄▄▄▀▀▄▄▀▀▄▄▄▀▀▀▀▀▀▀▀▀▀▄▄▄▀▄▄▄▀▀▄▄▄▄▄▀

```

Architecture IA isolée avec Distrobox, Podman et utilisateur dédié.
Documentation principale en français. English documentation is available below and in [`docs/en/`](docs/en/README.md).

## Vue d'ensemble

Ce dépôt documente une architecture Linux pratique pour exécuter des outils IA graphiques ou CLI dans un environnement séparé, sans exposer directement le home de l'utilisateur principal.

L'idée centrale est simple :

- l'utilisateur principal garde sa session graphique et son home privé ;
- un utilisateur Linux dédié exécute les outils IA ;
- Distrobox fournit l'environnement de travail jetable ;
- un dossier partagé explicite sert d'espace de projets ;
- l'accès Wayland est accordé de manière ciblée pour les applications GUI.

Cette approche améliore nettement l'isolation pour un usage de développement assisté par IA. Elle ne remplace pas une VM face à du code réellement hostile.

Le conteneur Distrobox est créé vide. Aucun outil de développement n'est installé automatiquement ; l'utilisateur installe manuellement ce dont il a besoin.

L'image par défaut suit la documentation v1 validée : `docker.io/library/archlinux:latest`.

## Ce que contient le dépôt

- [`scripts/setup-agent-ia-env.sh`](scripts/setup-agent-ia-env.sh) : installation interactive de l'environnement.
- [`scripts/setup-agent-ia-env-noninteractive.sh`](scripts/setup-agent-ia-env-noninteractive.sh) : installation non interactive pilotable par options.
- [`scripts/uninstall-agent-ia-env.sh`](scripts/uninstall-agent-ia-env.sh) : désinstallation interactive.
- [`scripts/uninstall-agent-ia-env-noninteractive.sh`](scripts/uninstall-agent-ia-env-noninteractive.sh) : désinstallation non interactive.
- [`docs/fr/`](docs/fr/README.md) : documentation complète en français.
- [`docs/en/`](docs/en/README.md) : documentation complète en anglais.

## Résultat visé

Après installation, on obtient :

- un utilisateur IA dédié, par défaut `agent` ;
- un groupe partagé, par défaut `iawork` ;
- un dossier de projets partagé, par défaut `/srv/ia-projets` ;
- un Distrobox lancé par l'utilisateur IA, par défaut `agent-ia` ;
- un lanceur `agent-ia-enter` pour entrer dans le conteneur ;
- un lanceur `agent-shell` pour ouvrir un terminal graphique en tant que compte IA ;
- un lanceur `agent-run` pour exécuter une commande hôte comme compte IA ;
- un raccourci `ai` équivalent à `agent-run` ;
- une séparation raisonnablement forte entre `/home/<utilisateur-principal>` et l'environnement IA.

## Parcours recommandé

Le parcours conseillé est le parcours manuel documenté dans [`docs/fr/installation.md`](docs/fr/installation.md).

Les scripts du dépôt doivent être considérés comme des aides d'automatisation pour une architecture que tu comprends déjà, pas comme le point d'entrée par défaut.

Règle de base :

- ne pas exécuter aveuglément des scripts trouvés sur des dépôts ;
- lire, comprendre et auditer les commandes avant exécution ;
- privilégier d'abord l'installation manuelle pour valider le modèle, les permissions et le périmètre exposé.

## Démarrage assisté

Si tu choisis malgré tout le mode assisté, depuis la session Wayland de l'utilisateur principal :

```bash
chmod +x scripts/setup-agent-ia-env.sh
./scripts/setup-agent-ia-env.sh
```

Ou en mode non interactif :

```bash
./scripts/setup-agent-ia-env-noninteractive.sh
```

Ensuite :

```bash
agent-ia-enter
cd /Projets
```

## Parcours de lecture recommandé

1. [`docs/fr/architecture.md`](docs/fr/architecture.md)
2. [`docs/fr/installation.md`](docs/fr/installation.md)
3. [`docs/fr/utilisation.md`](docs/fr/utilisation.md)
4. [`docs/fr/depannage.md`](docs/fr/depannage.md)

## Limites et posture de sécurité

Cette architecture protège bien contre :

- l'exposition accidentelle du home principal ;
- la pollution de l'environnement utilisateur principal ;
- le mélange non contrôlé entre projets IA et fichiers personnels.

Elle ne protège pas complètement contre :

- une compromission profonde de l'hôte ;
- un contournement équivalent à une vraie isolation VM/hyperviseur ;
- l'exécution sûre de malware ou de code hautement hostile.

Si le niveau de menace est élevé, utilise une VM dédiée ou une machine séparée.

## Documentation en français

- [Index](docs/fr/README.md)
- [Architecture](docs/fr/architecture.md)
- [Installation](docs/fr/installation.md)
- [Utilisation quotidienne](docs/fr/utilisation.md)
- [Dépannage](docs/fr/depannage.md)

## English summary

This repository documents a practical Linux setup for running AI GUI or CLI tools in a separate environment without exposing the main user's home directory directly.

The security boundary is the dedicated host user, not Distrobox itself. Distrobox is used for convenience, reproducibility, GUI integration, and a disposable development environment. A shared project directory is intentionally exposed, while the main home directory should stay private with standard Unix permissions.

The recommended path is the manual one documented in `docs/fr/installation.md` and mirrored in the English docs. Do not blindly run shell scripts found in repositories. Read and audit them first.

Recommended reading:

1. [English docs index](docs/en/README.md)
2. [Architecture](docs/en/architecture.md)
3. [Installation](docs/en/installation.md)
4. [Usage](docs/en/usage.md)
5. [Troubleshooting](docs/en/troubleshooting.md)

## References

- Distrobox: https://distrobox.it/
- Distrobox create documentation: https://github.com/89luca89/distrobox/blob/main/docs/usage/distrobox-create.md
- Podman rootless: https://docs.podman.io/
