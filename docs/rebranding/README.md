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

## Par où commencer

### Étape zéro, bloquante

`Tests/parrotTests/FnDictationGestureTests.swift` est modifié et non commité :
116 lignes de tests pour une feature Escape-cancel jamais implémentée.
**`swift build --build-tests` échoue aujourd'hui**, donc rien n'est vérifiable
tant que ce fichier est là.

Ce sont de bons tests, écrits en TDD. On les sort en enregistrant leur intention
dans `.scratch/annulation-echap/spec.md` plutôt qu'en les jetant. Détail dans
[01](./01-etat-des-lieux.md#le-blocage-préalable).

### L'ordre du travail

La convention du repo est un répertoire `.scratch/<slug>/` par feature, un
commit par feature, chacun vérifié seul.

| # | Slug | Contenu | Pourquoi à cette place |
|---|---|---|---|
| c0 | `annulation-echap` | Sortir les tests Escape-cancel, enregistrer leur intention | Rien n'est vérifiable avant |
| c1 | `renommage-plume` | Renommage mécanique : répertoires, `@main`, `Package.swift`, ~60 chaînes, docs tournés vers l'avant | Tout le reste écrit du code dans ces fichiers |
| c2 | `paquet-app` | `bundle.sh`, `Info.plist.in`, résolution du binaire, shim CLI, `Doctor`. Plus **ADR-0008** | |
| c3 | `migration-parrot-plume` | Les six déplacements, les préférences, la détection par `doctor` | Après c2 : elle a besoin de savoir où le paquet s'installe |
| c4 | `signature-et-distribution` | `install-local.sh`, `release.yml`, `install.sh`, **et la CI de tests qui manque** | |
| c5 | `les-tokens` | `Style` remplacé, **sans changement visuel volontaire** | Un commit de pure substitution se relit |
| c6 | `le-chrome` | Bulle, états erreur et annulation, panneau de repli, glyphe, icône | Consomme c5 et l'emplacement de ressources de c2 |
| c7 | `la-fenetre` | Fenêtre de réglages sur les tokens, sidebar, copie | |
| c8 | `marque-sprintmob` | LICENSE, NOTICE, lignée du README, glossaire, notices tierces, page | En dernier : elle montre le résultat, donc elle a besoin de captures qui existent |

**c1 et c2 restent séparés** alors qu'ils pourraient fusionner : c1 est 53
fichiers de changement mécanique qui doit se relire en diagonale, c2 est six
fichiers de vraies décisions. Mélangés, ni l'un ni l'autre n'est relisable.
C'est l'argument qu'ADR-0002 fait déjà sur l'ordre des waves.

**c5 avant c6** pour la même raison : une substitution de tokens sans intention
visuelle se révise, un redesign mêlé à une substitution ne se révise pas.

Note sur c1 : il n'existe **aucun état intermédiaire qui compile** à
l'intérieur, puisque SwiftPM déduit le chemin des sources du nom de la cible.
La garantie porte sur la frontière du commit, et l'issue doit le dire au lieu de
faire semblant.

## Ce que ce dossier n'est pas

Ce n'est pas une spec au sens du repo. Les specs vivent dans `.scratch/<slug>/`
et se rédigent au moment d'exécuter chaque feature, avec leurs issues numérotées.
Ce dossier est le niveau au-dessus : le programme, les décisions et leurs
arguments, pour que les huit specs puissent être écrites sans re-instruire le
sujet.

ADR-0008 n'est pas écrit non plus. Il se rédige avec c2, comme ADR-0004 et
ADR-0007 ont été écrits avec leur feature. Son cadrage est dans
[03](./03-paquet-et-renommage.md#ce-quadr-0008-doit-tenir).
