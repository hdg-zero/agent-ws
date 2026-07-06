# Installation

## Prérequis

Le script actuel cible principalement :

- Arch Linux ;
- une session Wayland, typiquement Hyprland ;
- `sudo` fonctionnel ;
- connectivité réseau ;
- les droits nécessaires pour installer des paquets et créer des comptes.

## Installation recommandée

Le parcours conseillé est l'installation manuelle. C'est la meilleure manière de comprendre :

- où se situe la vraie frontière de sécurité ;
- quels droits sont accordés ;
- quels chemins hôte sont exposés ;
- quelles hypothèses système le montage impose.

Les scripts fournis dans le dépôt sont des aides d'automatisation, pas le parcours de référence.

## Règle de sécurité préalable

N'exécute pas automatiquement des scripts shell trouvés dans des dépôts, y compris celui-ci, sans lecture préalable.

Avant d'exécuter un script :

1. lis son contenu ;
2. identifie les commandes `sudo`, `rm`, `useradd`, `usermod`, `setfacl`, `distrobox` et `podman` ;
3. vérifie les chemins modifiés ;
4. confirme que le comportement attendu correspond bien à ton poste.

## Installation manuelle

Le parcours manuel recommandé est :

1. créer un utilisateur Linux dédié ;
2. protéger le home principal avec des permissions strictes ;
3. créer un groupe et un dossier partagé ;
4. vérifier que l'utilisateur IA possède des entrées SubUID/SubGID valides ;
5. activer le linger pour obtenir `/run/user/<uid-agent>` ;
6. donner des ACL temporaires au socket Wayland ;
7. créer le Distrobox en tant qu'utilisateur IA ;
8. monter le dossier partagé et le socket Wayland ;
9. installer les outils dans le conteneur.

Tu peux ensuite utiliser les scripts seulement si tu veux reproduire ou automatiser ce comportement.

### Création manuelle validée

Après création de l'utilisateur, du groupe et du dossier partagé, le process validé utilise les entrées SubUID/SubGID de l'utilisateur IA puis active son runtime :

```bash
grep '^agent:' /etc/subuid /etc/subgid
sudo loginctl enable-linger agent
```

La création validée du Distrobox est :

```bash
AGENT_UID="$(id -u agent)"
USER_WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

sudo -H -u agent \
  env \
  XDG_RUNTIME_DIR="/run/user/$AGENT_UID" \
  WAYLAND_DISPLAY="wayland-user" \
  XDG_SESSION_TYPE=wayland \
  HOME=/home/agent \
  USER=agent \
  LOGNAME=agent \
  SHELL=/bin/bash \
  distrobox create --name agent-ia \
    --image docker.io/library/archlinux:latest \
    --volume /srv/ia-projets:/Projets:rw \
    --volume "$USER_WAYLAND_SOCKET:/run/user/$AGENT_UID/wayland-user"
```

L'entrée validée dans le conteneur est :

```bash
AGENT_UID="$(id -u agent)"

sudo -H -u agent \
  env \
  XDG_RUNTIME_DIR="/run/user/$AGENT_UID" \
  WAYLAND_DISPLAY="wayland-user" \
  XDG_SESSION_TYPE=wayland \
  HOME=/home/agent \
  USER=agent \
  LOGNAME=agent \
  SHELL=/bin/bash \
  distrobox enter agent-ia
```

## Installation assistée par script

Le dépôt fournit maintenant deux variantes :

- `scripts/setup-agent-ia-env.sh` : version interactive, adaptée à une première installation ;
- `scripts/setup-agent-ia-env-noninteractive.sh` : version non interactive, adaptée à l'automatisation.

Le dépôt fournit un script interactif :

```bash
chmod +x scripts/setup-agent-ia-env.sh
./scripts/setup-agent-ia-env.sh
```

Le script demande confirmation avant chaque étape structurante.

## Installation non interactive

La variante non interactive exécute les mêmes grandes étapes, sans questions intermédiaires.

Exemple minimal :

```bash
chmod +x scripts/setup-agent-ia-env-noninteractive.sh
./scripts/setup-agent-ia-env-noninteractive.sh
```

Exemple avec options :

```bash
./scripts/setup-agent-ia-env-noninteractive.sh \
  --agent-user agent \
  --shared-group iawork \
  --shared-dir /srv/ia-projets \
  --box-name agent-ia
```

Options utiles :

- `--preferred-terminal NAME` : spécifie le terminal préféré (par exemple `foot`, `alacritty`, `kitty`, etc.).
- `--recreate-box`
- `--skip-host-packages`
- `--skip-launchers`
- `--skip-subids`
- `--skip-agent-runtime`

### Support du mode sans tête (Headless)
Le script de configuration détecte automatiquement la présence d'une session Wayland. Si aucune session n'est détectée (par exemple lors d'une installation sur un serveur sans tête via SSH ou un outil d'automatisation/provisioning), le script n'échoue plus. Il bascule automatiquement en mode CLI pure : la création de la Distrobox s'effectue sans montage de socket graphique et les étapes d'ACL Wayland sont passées avec un simple avertissement.

## Ce que fait le script

### 1. Installe les paquets hôte

Sous Arch, le script installe si nécessaire :

- `podman`
- `distrobox`
- `acl`
- `fuse-overlayfs`
- `slirp4netns`
- `passt`

### 2. Crée ou réutilise l'utilisateur IA

Par défaut :

- utilisateur IA : `agent`
- shell : `/bin/bash`
- mot de passe verrouillé

Le compte est pensé pour un usage via `sudo -u`, pas comme session graphique complète.

### Image par défaut

La documentation v1 validée utilise par défaut :

```text
docker.io/library/archlinux:latest
```

### 3. Vérifie SubUID/SubGID

Le script vérifie que l'utilisateur IA possède une plage dans `/etc/subuid` et `/etc/subgid`.

Si une plage manque, il en ajoute une libre avec `usermod --add-subuids` et `usermod --add-subgids`. Sans ces mappings, Podman peut créer un conteneur qui ne mappe pas l'UID 0 et Distrobox échoue à la fin de la création.

### 4. Prépare le dossier partagé

Par défaut :

```text
/srv/ia-projets
```

Avec :

- groupe partagé `iawork` ;
- droits `2770` ;
- ACL par défaut en lecture/écriture/exécution pour le groupe partagé.

### 5. Protège le home principal

Le script propose :

```bash
chmod 700 /home/<main-user>
```

C'est une étape clé. Sans cela, l'isolation du home principal est faible ou nulle.

### 6. Prépare le runtime de l'utilisateur IA

Le script active le linger :

```bash
sudo loginctl enable-linger agent
```

Puis il attend que le runtime réel existe :

```text
/run/user/<uid-agent>
```

Il ne crée plus ce dossier à la main.

### 7. Prépare l'accès Wayland

Le script :

- détecte le socket Wayland courant ;
- donne temporairement au compte IA les ACL nécessaires ;
- enregistre le chemin du socket source dans la configuration.

### 8. Crée le Distrobox

Le Distrobox est créé comme utilisateur IA, avec au minimum :

- montage de `/srv/ia-projets` vers `/Projets` ;
- montage du socket Wayland dans le runtime du compte IA ;
- variables d'environnement Wayland nécessaires.

### 9. Installe les lanceurs

Le script écrit :

- `/etc/agent-ia-env.conf`
- `/usr/local/bin/agent-ia-enter`
- `/usr/local/bin/agent-shell`
- `/usr/local/bin/agent-run`
- `/usr/local/bin/ai`

## Installation manuelle des outils dans le conteneur

L'installation d'outils de développement n'est plus automatisée par le script. C'est volontaire : cette étape n'est pas indispensable au montage de l'environnement, et elle ajoute de la fragilité inutile au processus d'installation.

Une fois dans le Distrobox, installe seulement ce dont tu as besoin.

Exemple sous Arch dans le conteneur :

```bash
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm git curl wget base-devel nodejs npm python python-pip
```

## Vérifications après installation

### Vérifier que l'utilisateur IA ne lit pas le home principal

```bash
sudo -H -u agent ls /home/<main-user>
```

Résultat attendu :

```text
Permission denied
```

### Vérifier le dossier partagé

```bash
ls -ld /srv/ia-projets
getfacl /srv/ia-projets
```

### Entrer dans l'environnement IA

```bash
agent-ia-enter
```

Puis dans le conteneur :

```bash
cd /Projets
```

## Désinstallation

Deux variantes sont disponibles :

- `scripts/uninstall-agent-ia-env.sh` : version interactive ;
- `scripts/uninstall-agent-ia-env-noninteractive.sh` : version non interactive.

Le script de retrait est :

```bash
chmod +x scripts/uninstall-agent-ia-env.sh
./scripts/uninstall-agent-ia-env.sh
```

Il permet de supprimer au choix :

- le Distrobox ;
- les lanceurs ;
- les ACL Wayland ;
- le fichier de configuration ;
- le dossier partagé ;
- les sessions/processus de l'utilisateur IA ;
- le runtime `/run/user/<uid-agent>` ;
- les entrées `/etc/subuid` et `/etc/subgid` ;
- l'utilisateur IA ;
- le groupe partagé.

Exemple non interactif :

```bash
chmod +x scripts/uninstall-agent-ia-env-noninteractive.sh
./scripts/uninstall-agent-ia-env-noninteractive.sh \
  --remove-box \
  --remove-launchers \
  --remove-config
```

Pour tout supprimer dans le périmètre géré par le script :

```bash
./scripts/uninstall-agent-ia-env-noninteractive.sh --all
```

`--all` supprime aussi l'utilisateur IA, son home, son runtime, ses entrées SubUID/SubGID, le groupe partagé et le dossier partagé.

Sans option, la version non interactive échoue volontairement avec un message d'usage au lieu de ne rien faire silencieusement.
