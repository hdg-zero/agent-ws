# Utilisation quotidienne

## Commandes principales

### Entrer dans le Distrobox

```bash
agent-ia-enter
```

Ce lanceur :

- recharge la configuration depuis `/etc/agent-ia-env.conf` ;
- vérifie que tu es bien dans une session Wayland ;
- réapplique les ACL nécessaires sur le socket courant ;
- entre dans le Distrobox en tant qu'utilisateur IA.

### Ouvrir un terminal graphique comme utilisateur IA

```bash
agent-shell
```

Le script ouvre un terminal `foot` avec l'identité du compte IA depuis la session graphique du compte principal.

### Exécuter une commande hôte comme utilisateur IA

```bash
agent-run <commande> [arguments...]
```

Le raccourci suivant est aussi installé :

```bash
ai <commande> [arguments...]
```

`agent-run` lance la commande sur l'hôte avec l'identité de `agent`, en conservant le runtime Wayland de la session principale et en forçant les backends Wayland (`MOZ_ENABLE_WAYLAND`, `GDK_BACKEND`, `QT_QPA_PLATFORM`).

Exemple :

```bash
ai foot --working-directory=/home/agent
```

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
