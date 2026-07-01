# Dépannage

## `chmod /run/user/1000/libpod: operation not permitted`

### Cause probable

Podman rootless a été lancé comme utilisateur IA mais avec le `XDG_RUNTIME_DIR` de l'utilisateur principal.

### Correction

Vérifie que l'utilisateur IA utilise bien :

```text
XDG_RUNTIME_DIR=/run/user/<uid-agent>
```

Le script `setup-agent-ia-env.sh` construit précisément les lanceurs autour de cette contrainte.

## `failed to connect to wayland; no compositor running?`

### Causes probables

- le socket Wayland courant n'est plus celui monté lors de la création du Distrobox ;
- les ACL sur le runtime ou le socket ne sont plus valides après reconnexion ;
- le script n'a pas été lancé depuis une vraie session Wayland ;
- le socket n'existe plus sous le nom attendu.

### Vérifications

```bash
echo "$XDG_RUNTIME_DIR"
echo "$WAYLAND_DISPLAY"
ls -l "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
```

### Correction

1. relancer `agent-ia-enter` depuis la session graphique active ;
2. relancer `scripts/setup-agent-ia-env.sh` si le socket hôte a changé ;
3. recréer le Distrobox si le bind mount pointe vers un ancien socket.

## `Authorization required, but no authorization protocol specified` puis `Error: cannot open display: :1`

### Cause probable

L'application essaie d'utiliser X11 via `DISPLAY=:1` au lieu de Wayland. C'est un cas fréquent avec des navigateurs basés sur Firefox comme `mullvad-browser`.

### Correction

Force Wayland au lancement :

```bash
MOZ_ENABLE_WAYLAND=1 mullvad-browser
```

Si nécessaire, vide aussi `DISPLAY` :

```bash
DISPLAY= MOZ_ENABLE_WAYLAND=1 mullvad-browser
```

Si cela corrige le problème, l'application partait bien sur le mauvais backend graphique.

Si un outil comme `antigravity` doit ouvrir le navigateur automatiquement, vérifie aussi que `xdg-open` pointe bien vers `mullvad-browser.desktop`. Après correction du navigateur par défaut ou du fichier desktop local, relance `antigravity` et, si besoin, le navigateur déjà ouvert.

## L'utilisateur IA lit encore `/home/<main-user>`

### Cause probable

Le home principal est trop permissif, ou des ACL le rendent encore accessible.

### Vérification

```bash
sudo -H -u agent ls /home/<main-user>
```

### Correction

```bash
chmod 700 /home/<main-user>
getfacl /home/<main-user>
```

Ensuite, retire les ACL non voulues si nécessaire.

## L'utilisateur principal ne peut pas modifier les fichiers créés par l'utilisateur IA

### Cause probable

Le groupe partagé, le `setgid` ou les ACL par défaut du dossier partagé sont incorrects.

### Vérification

```bash
ls -ld /srv/ia-projets
getfacl /srv/ia-projets
id <main-user>
id agent
```

### Correction

```bash
sudo chown root:iawork /srv/ia-projets
sudo chmod 2770 /srv/ia-projets
sudo setfacl -m g:iawork:rwx /srv/ia-projets
sudo setfacl -d -m g:iawork:rwx /srv/ia-projets
sudo setfacl -d -m m::rwx /srv/ia-projets
```

Si le groupe vient d'être ajouté à un utilisateur, une reconnexion peut être nécessaire.

## Le terminal `agent-shell` ne s'ouvre pas

### Causes probables

- `foot` n'est pas installé dans l'hôte ou dans le flux prévu ;
- la session n'est pas Wayland ;
- les ACL sur le socket courant n'ont pas pu être appliquées.

### Vérification

```bash
command -v foot
echo "$XDG_RUNTIME_DIR"
echo "$WAYLAND_DISPLAY"
```

### Correction

Relance l'installation ou adapte le lanceur si tu préfères un autre terminal.

## Le Distrobox existe déjà mais ne fonctionne plus correctement

### Correction

Supprime puis recrée le conteneur avec le script d'installation, surtout si :

- le nom du socket Wayland a changé ;
- les volumes montés ne correspondent plus ;
- les dépendances du conteneur sont trop dégradées.

## Repartir de zéro

Si les essais ont laissé trop d'état intermédiaire, le plus fiable est de supprimer entièrement l'utilisateur IA puis de recréer l'environnement.

```bash
sudo loginctl terminate-user agent 2>/dev/null || true
sudo pkill -u agent 2>/dev/null || true
sudo rm -f /usr/local/bin/agent-ia-enter /usr/local/bin/agent-shell /usr/local/bin/agent-run /usr/local/bin/ai /etc/agent-ia-env.conf
sudo loginctl disable-linger agent 2>/dev/null || true
sudo userdel -r agent
sudo rm -rf /home/agent /run/user/1001
sudo sed -i '/^agent:/d' /etc/subuid
sudo sed -i '/^agent:/d' /etc/subgid
sudo groupdel iawork 2>/dev/null || true
```

Supprime aussi `/srv/ia-projets` seulement si tu veux effacer les projets partagés :

```bash
sudo rm -rf /srv/ia-projets
```

## Perte du cache / jetons de session sur Antigravity (reconnexion obligatoire)

### Cause probable

L'application Antigravity utilise un processus d'arrière-plan écrit en Go (`language_server`) qui tente de stocker son jeton d'authentification directement via l'API DBus Secret Service de Linux (l'alias `/org/freedesktop/secrets/aliases/default`).

Dans un environnement isolé (comme cette architecture Distrobox sous l'utilisateur `agent`), l'utilisateur `agent` n'a pas de session graphique physique et son mot de passe est verrouillé. Par conséquent, aucun trousseau de clés (`login.keyring`) n'a été créé par défaut. Le serveur de langage échoue donc à déverrouiller et à utiliser la collection par défaut (erreur `failed to unlock correct collection` dans les logs `language_server.log`), ce qui empêche la persistance de la session.

### Correction

Il faut initialiser un trousseau de clés par défaut (`login.keyring`) persistant et non verrouillé (sans mot de passe) pour l'utilisateur `agent`.

1. **Installer gnome-keyring** dans le conteneur Distrobox :
   ```bash
   sudo pacman -S --needed gnome-keyring
   ```

2. **Créer manuellement le trousseau de clés par défaut** :
   Créez le fichier `/home/agent/.local/share/keyrings/login.keyring` avec le contenu suivant pour désactiver le verrouillage :
   ```ini
   [keyring]
   display-name=login
   ctime=0
   mtime=0
   lock-on-idle=false
   lock-after=false
   ```

3. **Ajuster les permissions** :
   ```bash
   chmod 700 /home/agent/.local/share/keyrings
   chmod 600 /home/agent/.local/share/keyrings/login.keyring
   ```

4. **Redémarrer le service de trousseau de clés** ou le conteneur. Lors du prochain appel de l'application, le jeton sera persisté dans le trousseau de clés virtuel déverrouillé automatiquement.

## Antigravity ne se lance pas (la commande se termine immédiatement sans ouvrir de fenêtre)

### Cause probable

L'application Antigravity (basée sur Electron) utilise un verrou d'instance unique (*single-instance lock*). Si un processus `antigravity` résiduel ou zombie tourne déjà en arrière-plan (par exemple suite à une déconnexion graphique ou à un plantage), toute nouvelle tentative de lancement détecte le verrou, demande à l'instance existante d'apparaître, puis s'arrête immédiatement (rendant le prompt). Si l'ancienne instance est bloquée ou fantôme, aucune fenêtre ne s'ouvre.

Un message d'erreur DBus peut s'afficher dans le terminal :
```text
Failed to connect to the bus: Failed to connect to socket /run/dbus/system_bus_socket: Aucun fichier ou dossier de ce nom
```
Cet avertissement est lié à l'isolement du conteneur, il est sans gravité et n'empêche pas le bon fonctionnement de l'application.

### Correction

Tuez tous les processus d'`antigravity` résiduels de l'utilisateur pour libérer le verrou :

```bash
killall -9 antigravity
```

Relancez ensuite l'application normalement.

## Erreur d'ouverture de l'explorateur de dossiers/fichiers (Request ended / cannot open display)

### Cause probable

Dans les versions récentes d'Electron/Chromium, l'application tente d'utiliser l'API XDG Desktop Portal (`org.freedesktop.portal.FileChooser`) via D-Bus pour afficher les boîtes de dialogue de fichiers natives.

Comme le conteneur Distrobox utilise le bus D-Bus de l'utilisateur `agent`, la requête réveille le service `xdg-desktop-portal-gtk.service` de l'utilisateur. Cependant, ce service systemd démarre **sur l'hôte** (en dehors du conteneur) où le socket Wayland n'est pas accessible directement pour lui, provoquant l'erreur `cannot open display:` et annulant la requête (erreur `Request ended (non-user cancelled)`).

### Correction

Il faut forcer le démarrage du portail GTK en arrière-plan **à l'intérieur** du conteneur (où le socket Wayland est correctement monté et accessible) afin qu'il traite les requêtes D-Bus localement.

Ajoutez le bloc suivant à la fin du fichier `/home/agent/.bash_profile` dans le conteneur :

```bash
# Démarrer le portail GTK en arrière-plan dans le conteneur s'il n'est pas déjà lancé
if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && ! pgrep -u "$USER" -f "/usr/lib/xdg-desktop-portal-[g]tk" >/dev/null; then
    /usr/lib/xdg-desktop-portal-gtk -r >/dev/null 2>&1 &
fi
```

## Quand arrêter de déboguer et passer à une VM

Si tu multiplies les exceptions, montages ou contournements pour faire fonctionner des outils non fiables, l'architecture sort de son cas d'usage. À ce stade, une VM dédiée est plus adaptée.
