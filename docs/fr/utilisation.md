# Utilisation quotidienne

## Commandes principales

### Entrer dans le Distrobox

```bash
agent-ia-enter
```

Ce lanceur :

- recharge la configuration depuis `/etc/agent-ia-env.conf` ;
- détecte automatiquement si Wayland est disponible (session graphique) ou bascule en mode CLI/headless ;
- réapplique les ACL nécessaires sur le socket courant en session Wayland ;
- applique l'umask `0002` pour garantir les droits d'écriture de groupe sur les nouveaux fichiers ;
- entre dans le Distrobox en tant qu'utilisateur IA.

### Ouvrir un terminal graphique comme utilisateur IA

```bash
agent-shell
```

Le script ouvre le terminal graphique préféré (configuré ou détecté automatiquement, par exemple `foot`, `alacritty`, `kitty`, etc.) sous l'identité du compte IA depuis la session graphique du compte principal.

### Exécuter une commande hôte comme utilisateur IA

```bash
agent-run <commande> [arguments...]
```

`agent-run` lance la commande sur l'hôte avec l'identité de `agent` (avec umask `0002`). En session Wayland, il transmet le socket Wayland principal et force les backends Wayland (`ELECTRON_OZONE_PLATFORM_HINT`, `MOZ_ENABLE_WAYLAND`, `GDK_BACKEND`, `QT_QPA_PLATFORM`). En mode console ou sans tête, il s'exécute directement en mode CLI. Il utilise `/run/user/<uid-agent>` comme `XDG_RUNTIME_DIR` pour que les sockets IPC soient créés côté `agent`.

Exemple :

```bash
agent-run foot --working-directory=/home/agent
```

### Exécuter rapidement dans le conteneur Distrobox (`ai`)

Le raccourci `ai` pilote l'environnement Distrobox directement :

```bash
# Ouvrir un shell interactif dans le conteneur
ai

# Exécuter une commande dans le conteneur
ai <commande> [arguments...]

# Lancer une commande graphique ou longue en arrière-plan (détachée)
ai --bg <commande> [arguments...]

# Restaurer les droits d'écriture partagés
ai --fix-perms
```

### Restaurer les droits d'écriture du dossier partagé

```bash
agent-fix-perms
```

Si des programmes ou des outils tiers créent des fichiers avec un masque restrictif, cette commande réapplique instantanément le bit `setgid` (`2770`), les droits `g+rwX` et les ACLs par défaut sur `/srv/ia-projets`.

### Arrêter le conteneur et la session IA

```bash
agent-stop
```

Ce lanceur arrête proprement l'environnement IA en plusieurs étapes :

1. arrête le conteneur Distrobox (`distrobox stop -Y <box-name>`) ;
2. termine les processus résiduels de l'utilisateur IA (`pkill -u <agent-user>`) ;
3. clôture la session utilisateur systemd (`loginctl terminate-user <agent-user>`).

Options disponibles :

- `agent-stop --box-only` : arrête uniquement le conteneur Distrobox sans fermer la session utilisateur hôte ;
- `agent-stop --session-only` : ferme uniquement la session systemd et les processus résiduels sans appeler l'arrêt explicite de Distrobox ;
- `agent-stop --fix-perms` : répare les permissions d'écriture du dossier partagé avant arrêt ;
- `agent-stop --help` : affiche l'aide.

## Répertoire de travail recommandé

Dans le conteneur, travaille dans :

```bash
cd /Projets
```

Ce chemin correspond au dossier hôte partagé, typiquement :

```text
/srv/ia-projets
```

## Bonnes pratiques

### Travailler dans Git

Avant de laisser un agent modifier un projet :

```bash
git status
git add -A
git commit -m "checkpoint avant session IA"
```

Après la session :

```bash
git diff
git status
```

### Limiter les secrets

Évite de stocker dans `/srv/ia-projets` :

- clés SSH ;
- tokens longue durée ;
- fichiers `.env` sensibles ;
- `kubeconfig` ;
- secrets cloud.

Privilégie des tokens dédiés, révocables et à périmètre réduit.

### Considérer `/home/agent` comme exposé à l'IA

Ce home n'est pas le tien, c'est celui de l'environnement IA. Garde-y uniquement :

- les outils ;
- les caches ;
- les identifiants nécessaires et limités ;
- les fichiers temporaires de travail.

### Recréer le Distrobox si nécessaire

Si l'environnement devient instable ou trop pollué :

1. sauvegarde les projets utiles dans `/srv/ia-projets` ;
2. supprime le Distrobox ;
3. relance le script d'installation ;
4. recrée le conteneur.

## Ce que l'architecture te permet de faire

- lancer des GUI Linux depuis le conteneur ;
- installer des SDK sans salir le poste principal ;
- garder un périmètre de fichiers explicite ;
- jeter et reconstruire l'environnement IA.

## Ce qu'elle ne garantit pas

- une isolation forte contre un logiciel malveillant ;
- une protection équivalente à un hyperviseur ;
- une sécurité parfaite si tu montes trop de répertoires hôte dans le conteneur.
