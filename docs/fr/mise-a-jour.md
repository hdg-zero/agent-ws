# Mise à jour d'un environnement existant

Si tu disposes déjà d'une installation fonctionnelle de `agent-ws`, ce guide décrit comment mettre à jour ton environnement pour bénéficier des correctifs récents (gestion automatique de l'umask `0002`, nouveau lanceur `agent-fix-perms`, séparation propre `ai` / `agent-run`, support headless et durcissement de sécurité).

---

## Méthode 1 : Mise à jour automatique (recommandée)

Le script non interactif fournit une option dédiée `--update` qui met à jour la configuration, les profils et les lanceurs sans toucher à tes données ni recréer le conteneur :

```bash
git pull
./scripts/setup-agent-ia-env-noninteractive.sh --update
```

### Ce que fait cette commande :
1. **Préserve tes choix existants** : elle recharge les variables depuis `/etc/agent-ia-env.conf` (nom d'utilisateur, nom du conteneur, dossier partagé).
2. **Configure l'umask `0002`** : elle ajoute `umask 0002` dans `/home/agent/.bashrc` et `.profile`, assurant que tous les nouveaux fichiers créés par l'IA ou ses outils restent modifiables par ton utilisateur principal.
3. **Configure Git pour le groupe** : elle définit `git config --global core.sharedRepository group` pour l'utilisateur `agent`.
4. **Installe et actualise les lanceurs** : elle met à jour `/usr/local/bin/` avec les versions sécurisées (`agent-ia-enter`, `agent-shell`, `agent-run`, `ai`, `agent-stop`) et installe le nouveau lanceur `agent-fix-perms`.

Une fois la mise à jour terminée, applique les permissions réparées sur tes projets existants :

```bash
agent-fix-perms
```

---

## Méthode 2 : Mise à jour manuelle pas à pas

Si tu préfères appliquer les modifications manuellement sans script :

### 1. Activer l'umask 0002 pour l'utilisateur IA
```bash
sudo -u agent bash -c 'echo "umask 0002" >> ~/.bashrc'
sudo -u agent bash -c 'echo "umask 0002" >> ~/.profile'
sudo -u agent git config --global core.sharedRepository group
```

### 2. Réparer les permissions des fichiers existants
Pour corriger les fichiers déjà créés qui ont un masque d'ACL restrictif (`#effective:r--`) :
```bash
sudo chown -R root:iawork /srv/ia-projets
sudo chmod 2770 /srv/ia-projets
sudo find /srv/ia-projets -type d -exec chmod 2770 {} +
sudo chmod -R g+rwX /srv/ia-projets
sudo setfacl -R -m g:iawork:rwx,m::rwx /srv/ia-projets
sudo setfacl -R -d -m g:iawork:rwx,m::rwx /srv/ia-projets
```

### 3. Mettre à jour les lanceurs uniquement
Pour actualiser uniquement les scripts de `/usr/local/bin/` :
```bash
./scripts/setup-agent-ia-env-noninteractive.sh --launchers-only
```

---

## Optionnel : Migrer vers l'alias Wayland `wayland-agent`

Si ton installation précédente a été créée avec l'ancien alias `wayland-hdg` :
- Ton environnement continue de fonctionner sans aucune intervention car la valeur est lue dans `/etc/agent-ia-env.conf`.
- Si tu souhaites éliminer cette ancienne référence :
  1. Édite `/etc/agent-ia-env.conf` et modifie la ligne :
     ```ini
     WAYLAND_ALIAS="wayland-agent"
     ```
  2. Recrée le conteneur Distrobox pour appliquer le nouveau point de montage de socket :
     ```bash
     ./scripts/setup-agent-ia-env-noninteractive.sh --recreate-box
     ```
