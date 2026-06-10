# Architecture

## Principe

L'utilisateur principal conserve sa session graphique et son home privé. Un second utilisateur Linux, dédié aux outils IA, lance Podman rootless et le conteneur Distrobox. Les projets sont échangés via un dossier partagé explicite.

Exemple de rôles :

- utilisateur principal : `archuser`
- utilisateur IA : `agent`
- groupe partagé : `iawork`
- dossier partagé : `/srv/ia-projets`
- Distrobox : `agent-ia`

## Pourquoi ne pas compter uniquement sur Distrobox

Distrobox est excellent pour :

- la reproductibilité ;
- le confort de développement ;
- l'intégration GUI ;
- l'isolement des dépendances.

En revanche, ce n'est pas une sandbox de sécurité forte. Son but est d'intégrer le conteneur à l'hôte, pas d'établir une séparation équivalente à une VM. La vraie frontière doit donc être le compte Linux dédié.

## Vue logique

```text
┌─────────────────────────────────────────────────────────────┐
│ Hôte Linux                                                  │
│                                                             │
│  Utilisateur principal                                      │
│  ├─ session Hyprland / Wayland                              │
│  ├─ /home/<main-user>                                       │
│  └─ socket Wayland /run/user/<uid-main>/wayland-X           │
│                                                             │
│  Utilisateur IA                                             │
│  ├─ /home/<agent-user>                                      │
│  ├─ Podman rootless via /run/user/<uid-agent>               │
│  └─ Distrobox                                               │
│                                                             │
│  Dossier partagé                                            │
│  └─ /srv/ia-projets                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Flux fichiers

Le dossier partagé est l'espace volontairement exposé :

```text
main user  ── rwx ──┐
                    ▼
              /srv/ia-projets
                    ▲
agent user ── rwx ──┘
```

Le home principal ne doit pas être exposé :

```text
agent user ─X─> /home/<main-user>
```

La protection minimale recommandée est :

```bash
chmod 700 /home/<main-user>
```

## Flux graphique Wayland

Les applications graphiques s'exécutent dans le Distrobox, mais s'affichent dans la session Wayland de l'utilisateur principal.

```text
Application GUI dans le Distrobox
        │
        │ WAYLAND_DISPLAY=<alias>
        ▼
/run/user/<uid-agent>/<alias>
        │
        │ bind mount vers le vrai socket
        ▼
/run/user/<uid-main>/wayland-X
        │
        ▼
Session Wayland / Hyprland du compte principal
```

L'accès est accordé avec des ACL sur :

- le répertoire runtime de l'utilisateur principal ;
- le socket Wayland courant ;
- le runtime de l'utilisateur IA.

## Rôle des composants

### Utilisateur principal

Il garde :

- le home personnel ;
- la session graphique ;
- les secrets et fichiers sensibles ;
- l'administration via `sudo`.

### Utilisateur IA

Il porte :

- les caches et tokens IA ;
- les conteneurs Podman rootless ;
- le Distrobox ;
- les dépendances et outils de développement.

### Groupe partagé

Le groupe partagé permet aux deux utilisateurs d'écrire dans le même espace projet. Le script configure :

```bash
chown root:iawork /srv/ia-projets
chmod 2770 /srv/ia-projets
setfacl -m g:iawork:rwx /srv/ia-projets
setfacl -d -m g:iawork:rwx /srv/ia-projets
```

Le bit `setgid` garantit l'héritage du groupe sur les nouveaux fichiers.

### Podman rootless

Podman doit être lancé avec le bon runtime utilisateur :

```text
XDG_RUNTIME_DIR=/run/user/<uid-agent>
```

Si Podman réutilise le runtime du compte principal, tu peux voir des erreurs du type :

```text
chmod /run/user/1000/libpod: operation not permitted
```

## Hypothèses de sécurité réalistes

Cette architecture améliore fortement l'isolation pour un usage de développement assisté par IA, mais elle reste en dessous d'une VM.

Elle protège bien contre :

- la lecture accidentelle du home principal ;
- la pollution du poste principal par les dépendances ;
- l'exposition trop large des projets.

Elle protège mal contre :

- du code activement malveillant ;
- une compromission profonde de l'hôte ;
- un besoin d'isolation forte au niveau système.

## Quand choisir autre chose

Utilise une VM ou une machine séparée si :

- tu exécutes du code non fiable ;
- tu manipules des secrets très sensibles ;
- tu as besoin d'une isolation défensive forte plutôt que d'une isolation pratique.
