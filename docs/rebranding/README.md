# parrot → plume : rebranding SprintMob et passage en open source

**Statut : rebranding implémenté sur `rebranding-plume`, publication en attente.**
Ce dossier conserve les décisions et les critères de vérification. Les étapes de
code sont achevées ; la validation sur compte standard, la démonstration et la
mise en ligne restent à confirmer avant l'annonce.

Rédigé le 2026-09-03, à partir de `main` @ `0dd69e9`.

## Pourquoi

`parrot` est un fork privé de [`digimata/parrot`](https://github.com/digimata/parrot),
un démon de dictée macOS : on tient une touche, on parle, le texte arrive au
curseur. Le fork a mergé 16 PR upstream puis ajouté quatre features maison
(focus detection, hotkey persistence, pasteboard guarantee, settings window).
Il fonctionne et il est installé.

L'objectif est de le publier en open source **sous la marque SprintMob**, pour
que l'outil porte la marque. Un CTO qui installe un outil de dictée quotidien
voit le nom, l'icône et la bulle des dizaines de fois par jour.

Quatre chantiers, dans cet ordre de dépendance :

1. **Un nom.** `parrot` appartient à l'upstream. Retenu : **`plume`**.
2. **Une identité visuelle.** Aujourd'hui l'app peint son chrome en bleu pâle
   `#B5D1FF` sur `#101212`, deux couleurs qui ne viennent de nulle part.
3. **Un vrai bundle `.app`.** Sans bundle, macOS n'a aucun endroit où lire une
   icône, et l'autorisation Accessibilité s'ancre sur le terminal parent plutôt
   que sur l'app.
4. **Une vitrine.** Repo présentable, plus une page hébergeant `install.sh`.

## Décisions prises

| Sujet | Décision | Où c'est argumenté |
|---|---|---|
| Nom | `plume` | ci-dessous |
| Portée UI | Chrome flottant **et** fenêtre de réglages, avec un vrai jeu de tokens | [02](./02-design-systeme.md) |
| Packaging | Vrai bundle `.app` | [03](./03-paquet-et-renommage.md) |
| Vitrine | Repo **et** page d'atterrissage | [04](./04-vitrine-et-licence.md) |
| Domaine | `plume.sprintmob.com` | [04](./04-vitrine-et-licence.md) |
| Upstream | Crédit dans le repo, pas de message aux auteurs | [04](./04-vitrine-et-licence.md) |
| Police | Euclid Circular B **non embarquée**, police système gardée | [02](./02-design-systeme.md) |
| Fenêtre de réglages | Couleurs sémantiques macOS gardées | [02](./02-design-systeme.md) |

### Pourquoi `plume`

Français, court, tapable. La plume qui écrit, pas l'oiseau qui répète : le nom
hérite honnêtement du perroquet sans lui voler le sien. Glyphe évident.

Vérifications faites : libre sur le `PATH` (contrairement à `dash` et `echo`,
qui collisionnent avec des binaires système), aucune formule Homebrew `plume`
(404 sur formulae.brew.sh), et aucune collision dans l'outillage de dictée
(contrairement à `mynah`, qui est déjà une org ASR sur GitHub).

## Le dossier

| Fichier | Contenu |
|---|---|
| [01-etat-des-lieux.md](./01-etat-des-lieux.md) | Ce qui existe, mesuré : la marque, le code, l'inventaire du renommage, les dettes préexistantes |
| [02-design-systeme.md](./02-design-systeme.md) | Les tokens, la bulle, le glyphe, l'icône, la fenêtre, la copie |
| [03-paquet-et-renommage.md](./03-paquet-et-renommage.md) | Le bundle sans Xcode, le shim CLI, le LaunchAgent, la signature, la migration, la séquence de renommage |
| [04-vitrine-et-licence.md](./04-vitrine-et-licence.md) | La page, le README, l'attribution, les obligations tierces |
| [05-checklist-et-verification.md](./05-checklist-et-verification.md) | La checklist actionnable, les questions ouvertes, ce qui n'est pas fait, le protocole de vérification |

## Avancement au 2026-09-24

Les étapes c0 à c8 sont implémentées sur `rebranding-plume`. Le bundle,
l'installeur utilisateur, la migration explicite, les tokens, le chrome, la
fenêtre de réglages, l'attribution et la page sont dans la branche. Les 94 tests,
le build release, l'assemblage, `plutil`, `codesign`, `check-rename.sh` et la
validation des workflows passent localement.

Restent avant l'ouverture du dépôt :

1. Une capture réelle de dictée pour remplacer les placeholders du README et
   de la page, et la revue visuelle des états en apparence claire et sombre.
2. L'installation d'une préversion depuis GitHub sur un compte macOS standard,
   avec Microphone, Accessibilité, LaunchAgent, double-clic et migration vérifiés.
3. La réception effective des messages par `security@sprintmob.com` et
   `conduct@sprintmob.com`. Les alias doivent encore être créés.
4. Ensuite seulement : dépôt public `sprintmob/plume`, Pages et DNS, puis
   release stable et nouvel essai depuis l'URL publique.

Les autres fichiers de ce dossier conservent le raisonnement initial et peuvent
décrire des étapes au futur. Les commandes et chemins actuels sont dans le
[README](../../README.md), [l'ADR-0008](../adr/0008-ship-a-real-app-bundle.md)
et les scripts.
