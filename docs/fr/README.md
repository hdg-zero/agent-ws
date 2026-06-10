# Documentation

Le français est la langue de référence de cette documentation.

## Sommaire

- [Architecture](architecture.md)
- [Installation](installation.md)
- [Utilisation quotidienne](utilisation.md)
- [Dépannage](depannage.md)

## Objectif

Cette documentation décrit comment isoler un environnement IA sur un poste Linux en combinant :

- un utilisateur hôte dédié pour l'IA ;
- Podman rootless ;
- Distrobox ;
- un dossier partagé explicite ;
- un accès Wayland contrôlé pour les applications graphiques.

## Position recommandée

Le parcours recommandé est le parcours manuel. Les scripts fournis dans ce dépôt sont optionnels et servent à automatiser une procédure que tu dois déjà comprendre.

Ne pars pas du principe qu'un script trouvé sur un dépôt doit être exécuté tel quel. Lis-le, audite-le, vérifie son périmètre et exécute-le seulement si tu acceptes précisément ce qu'il va modifier.

## Pour qui

Cette architecture est adaptée si tu veux :

- lancer un agent IA ou un IDE graphique avec accès réseau ;
- éviter d'exposer directement ton vrai home personnel ;
- garder un environnement jetable côté outils et dépendances ;
- conserver un espace de projets clairement défini et récupérable.

## Ce que tu trouveras ici

- `architecture.md` : modèle mental, flux et hypothèses de sécurité ;
- `installation.md` : installation via script et résumé manuel ;
- `utilisation.md` : usage quotidien, commandes utiles et bonnes pratiques ;
- `depannage.md` : erreurs fréquentes et corrections.

## Hypothèse principale

La séparation de sécurité repose d'abord sur l'utilisateur Linux dédié et les permissions Unix. Distrobox n'est pas considéré comme une barrière de sécurité stricte.
