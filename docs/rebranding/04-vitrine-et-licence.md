# Vitrine, attribution, licence

## La page d'atterrissage

`aws.sprintmob.com` donne le précédent : projet séparé, CNAME indépendant, aucune
interaction avec `www` qui est encore sur Framer. `plume.sprintmob.com` suit le
même schéma, donc aucun risque de bascule ni de conflit de certificat.

Note à trancher côté DNS : le profil GitHub de l'org annonce `www.sprintmob.fr`
tandis que le blueprint du site vise `sprintmob.com`. Le domaine retenu ici est
`.com`, aligné sur le blueprint et sur le sous-site AWS. L'incohérence du profil
est hors périmètre de ce projet mais visible.

Le contenu tient en une page, et son travail est de faire tourner une seule
commande :

```sh
curl -fsSL https://plume.sprintmob.com/install.sh | sh
```

C'est le vrai levier de marque : l'URL que les gens copient et collent dit
« sprintmob ». Aujourd'hui `scripts/install.sh:3` pointe encore vers
`digimata.github.io`, un site appartenant à l'upstream.

Ce que la page porte, dans l'ordre : la commande, une capture animée de la bulle
en action, les trois ou quatre phrases qui disent ce que fait l'outil, la mention
« on-device, aucun transcript sur disque » qui est le vrai argument, et une ligne
« par SprintMob » qui renvoie au site.

Pas de section features en grille de cartes, pas de témoignage. Ce n'est pas une
page de vente, c'est une page d'installation.

### Alternative si le DNS traîne

`https://raw.githubusercontent.com/sprintmob/plume/main/scripts/install.sh` ne
demande aucun setup et c'est honnêtement ce que font la plupart des projets. Ça
perd le porteur de marque, donc à ne prendre que comme étape intermédiaire.

## Le README

Le README actuel est bon mais il s'adresse à quelqu'un qui a déjà décidé. En open
source c'est la vitrine. L'ordre change :

1. Le nom, le glyphe, la commande d'installation, la démo animée.
2. La lignée et l'attribution.
3. La référence CLI et le reste, plus bas.

La règle de voix s'applique au README comme aux chaînes de l'app : phrases
courtes, pas de tiret cadratin, les chiffres avant les promesses. Le chiffre
disponible ici est la latence, moins de 500 ms après le relâchement de la touche.
C'est lui qui remplace les adjectifs.

### L'avertissement Gatekeeper, honnête

À écrire tel quel, parce que la moitié de ce que les gens croient sur le sujet
est faux :

> **Plume is not notarized.** SprintMob does not yet have an Apple Developer ID,
> so the app carries an ad-hoc signature. Two consequences, and neither is
> hidden:
>
> 1. **If you download the zip in a browser**, macOS quarantines it and refuses
>    to open it. The message is "Plume is damaged and can't be opened," which is
>    what macOS says about any app it cannot verify. The `curl … | sh` installer
>    above does not go through a browser, so nothing is quarantined and this does
>    not happen. If you did download it by hand:
>    `xattr -dr com.apple.quarantine /Applications/Plume.app`.
> 2. **Every update costs you the Accessibility grant.** An ad-hoc signature is
>    anchored to the exact bytes of the build, so macOS treats each release as a
>    different application. After updating, Plume will still record and
>    transcribe, and will silently stop typing at the cursor until you re-enable
>    it under System Settings → Privacy & Security → Accessibility.
>    `plume doctor` will tell you that is what happened.
>
> Both go away the day we ship a Developer ID-signed, notarized build.

## La licence

MIT, et la mention d'Andrew Jones **reste**. MIT exige que la notice de copyright
et la notice de permission soient conservées dans toutes les copies. On ajoute
une ligne, on ne remplace pas, on ne relicencie pas.

```
MIT License

Copyright (c) 2026 Andrew Jones
Copyright (c) 2026 SprintMob

Permission is hereby granted, free of charge, to any person obtaining a copy
… [corps MIT inchangé] …
```

Deux lignes de copyright au-dessus d'un seul corps MIT est la forme standard et
non controversée.

## `NOTICE`

Non exigé par MIT, mais c'est là que va la lignée, pour que `LICENSE` reste un
document légal plutôt qu'une histoire.

```
Plume
Copyright (c) 2026 SprintMob

This product includes software originally developed as `parrot` by Andrew Jones
(https://github.com/digimata/parrot), licensed under the MIT License. See LICENSE.

Substantial parts of this codebase originate in pull requests opened against
digimata/parrot and merged here without their authors' involvement:

  andredezzy      #12 #13 #14 #19 #20 #21 #23 #25
  vipergsm        #17 #18
  justinhnaylor   #16 #24
  Entrepenulian   #4
  augiefra       #5
  tomiiide        #10
  imtamiliniyan   #27
  L65FREAD        #9
  bdeol2          #11 (closed as a duplicate of #12; its TCC analysis was used)

What each contributed, and why it was chosen over the alternatives, is recorded
in docs/adr/0002-merge-upstream-prs-in-waves.md and the .scratch/vague-*/ specs.
```

### Le compte est 8 auteurs, pas 25

**25 PR ouvertes upstream, 16 mergées, par 8 auteurs distincts**, plus `bdeol2`
dont la PR a été fermée en doublon mais dont l'analyse a servi. Créditer
« 25 auteurs » dans un NOTICE serait généreux et **faux**.

Le partage honnête : le NOTICE crédite les 8 dont le code est dans l'arbre, le
README dit « 25 PR ouvertes, 16 mergées ». Si vous voulez créditer les 25 auteurs
de PR en geste de bonne volonté, ça va dans une ligne « Thanks » du README,
clairement séparée de ce que le NOTICE affirme sur la provenance.

## La section lignée du README

À placer au-dessus de `## Stack`.

```markdown
## Lineage

Plume is a fork of [`digimata/parrot`](https://github.com/digimata/parrot) by
Andrew Jones, MIT-licensed. Upstream stopped taking commits in May 2026 with 25
open, unreviewed pull requests; this fork merged 16 of them across five waves
before writing a line of its own. See
[ADR-0001](docs/adr/0001-fork-rather-than-contribute-upstream.md) and
[ADR-0002](docs/adr/0002-merge-upstream-prs-in-waves.md).

Most of what Plume does was written by people who never got a review: andredezzy,
vipergsm, justinhnaylor, Entrepenulian, augiefra, tomiiide, imtamiliniyan and
L65FREAD. [NOTICE](NOTICE) says who wrote what. SprintMob publishes it; SprintMob
did not write most of it.
```

La dernière phrase est celle qui rend toute la section crédible. À garder.

### Pourquoi le crédit doit être visible sans être cherché

La décision prise est : **crédit dans le repo, aucun message envoyé aux auteurs.**
ADR-0001 faisait de ces auteurs un levier assumé pour attirer des contributeurs.
Puisque le message est écarté, le repo est le **seul** canal, donc le crédit doit
être lisible sans être cherché : les noms dans le README, pas seulement enterrés
dans l'historique git.

## L'obligation tierce, aujourd'hui non honorée

`swift-argument-parser` est en **Apache-2.0** avec l'exception de bibliothèque
d'exécution. L'article 4 d'Apache-2.0 exige que la licence et toute NOTICE
voyagent avec les distributions « in Source or Object form ». Dès qu'on livre un
**binaire** lié statiquement, l'obligation s'attache au binaire, et le
`parrot-macos-arm64.tar.gz` d'aujourd'hui ne la porte pas.

Le bundle `.app` donne l'endroit naturel pour corriger :

```
Plume.app/Contents/Resources/ACKNOWLEDGEMENTS.txt
```

généré par `bundle.sh`, plus un `THIRD-PARTY.md` à la racine du repo.

**Bloquant, et à résoudre avant publication :** les licences de
`argmaxinc/argmax-oss-swift` (WhisperKit) et `FluidInference/FluidAudio` n'ont
jamais été vérifiées. WhisperKit est normalement en MIT ; FluidAudio est à
vérifier. C'est une obligation non remplie aujourd'hui, indépendamment du
rebranding.

## Le dépôt public

`origin` est `youssdevx/parrot`, un compte personnel. `upstream` est
`digimata/parrot`. `github.com/sprintmob` existe, affiché « SprintMob », avec
**zéro dépôt public** : `plume` y serait le premier, ce qui est en soi un geste
de marque.

**Fork GitHub ou dépôt neuf ?** Un fork affiche la bannière « forked from
digimata/parrot », bonne pour l'histoire d'attribution. Mais les forks arrivent
avec Issues et Actions désactivés par défaut, et chaque PR vise l'upstream par
défaut, ce qui est une gêne permanente pour un projet qui prendra des
contributions.

**Recommandation : un dépôt simple**, plus le NOTICE et la section lignée
explicites, qui en disent de toute façon plus que la bannière. Décision
utilisateur.

## Fichiers de communauté

Le repo n'a que `.github/workflows/release.yml`. Pas de templates d'issue, pas de
CODEOWNERS, pas de CONTRIBUTING. Pour une publication :

- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- Templates d'issue
- `SECURITY.md`

Et une chose que ce projet a de particulier à y écrire : le repo est un fork dont
l'essentiel du code vient de PR non revues chez l'upstream. Un CONTRIBUTING qui
le dit, et qui explique la convention `.scratch/` plus ADR, part avec une
honnêteté que la plupart des forks n'ont pas.
