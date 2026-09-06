# État des lieux

Tout ce qui suit a été mesuré le 2026-09-03 sur `main` @ `0dd69e9`, pas supposé.
Les numéros de ligne valent pour ce commit.

## La marque SprintMob

Elle vit dans `/Users/youcef/Projects/sprintmob/website/`, un dépôt de blueprint
(specs markdown plus un canvas pen.dev), et elle existe en **deux générations** :

- **Gen 1**, `06-implementation/specs-nextjs.md:67-70`, du 25/08 : fond
  `#0A0A0A`, texte `#F7F8F3`, accent lime `#E0FE75`.
- **Gen 2**, `website.pen`, modifié le jour de cette rédaction : le site migre
  vers un système paper/ink chaud (`#F7F4EE` / `#14140F`), ajoute Instrument
  Serif comme face éditoriale, et relègue le noir pur dans des groupes préfixés
  `hc-*` et `aws-*`. Deux directions artistiques sont en cours d'arbitrage dans
  le canvas : « A · Dossier de qualification » contre « B · Lime drenched ».

**Le lime `#E0FE75` est la seule valeur constante entre les deux générations**,
et le remplissage le plus utilisé du document. C'est sur lui que repose le
rebranding, et c'est pourquoi une direction artistique non tranchée ne bloque
pas ce travail.

### Le groupe `hc-*`, qui est ce dont on a besoin

Gen 2 contient une échelle sombre déjà dessinée, exactement le sous-ensemble
qu'il faut à un chrome qui flotte au-dessus des autres apps :

```
hc-bg #0A0A0A   hc-elev #121212   hc-elev-2 #181818
hc-ink #F7F8F3  hc-ink-70 #F7F8F3B8  hc-ink-45 #F7F8F380  hc-ink-25 #F7F8F340
hc-line #F7F8F324   hc-line-soft #F7F8F314   hc-lime #E0FE75
```

Elle tombe juste sur les littéraux déjà écrits en dur dans le panneau de repli :
`.white` devient `hc-ink`, `.white.opacity(0.65)` devient `hc-ink-70` (0,72), et
`.white.opacity(0.08)` devient `hc-line-soft`, dont l'alpha `0x14` **vaut
exactement** 0,08. Le rebranding ne combat pas l'architecture existante, il la
nomme.

Autres tokens du canvas : rayons `sm 8 / btn 10 / md 12 / lg 16 / xl 24 /
2xl 32 / pill 999`, espacements sur une grille stricte de 4px (`space-1..28`).
L'échelle typographique du canvas (118 à 13) est dimensionnée pour le web et ne
transfère pas au chrome macOS.

### La règle de contraste, écrite par la marque

> « lime sur noir passe, lime sur blanc non : jamais de texte lime sur fond
> clair »

Vérification indépendante, luminance relative WCAG : `#E0FE75` a une luminance
de 0,880, ce qui donne **1,13:1 sur blanc** et **17,5:1 sur `#0A0A0A`**.

Le bleu pâle actuel `#B5D1FF` a déjà ce défaut, à 1,55:1 sur blanc. C'est donc
un bug préexistant à corriger, pas à reproduire : la fenêtre de réglages suit
l'apparence système et y affiche aujourd'hui de l'accent en premier plan.

Règle complémentaire, du sous-branding AWS : « Le lime `#E0FE75` reste réservé
au CTA et aux accents. Il ne sert jamais à une sévérité. » Et la sévérité n'est
jamais portée par la couleur seule, toujours doublée d'un libellé.

### La typographie, et son problème de licence

Euclid Circular B, dix `.ttf` de bureau datés 2022 dans `website/fonts/`.

Une recherche de tout fichier `licen*` ou `eula*` sous `website/` ne rend rien.
La spec dit elle-même « Euclid Circular B **si licence web disponible**, sinon
fallback ». La licence **web** n'est donc pas résolue, et une licence
d'embarquement applicatif est un palier au-dessus, facturé par application chez
Swiss Typefaces.

Conséquence directe pour ce projet : le repo part en open source, donc le
binaire de la police atterrirait dans un dépôt public et dans chaque artefact de
release. C'est une redistribution. La décision est dans
[02](./02-design-systeme.md#deux-questions-tranchées-dabord).

### Le logo

`website/logos/sprintmob-logo-black.svg` et `-white.svg`. Le nommage est par
**fond**, pas par couleur de marque : `-black` est un aplat noir avec la marque
en blanc, `-white` un aplat `#F0EEE6` avec la marque en noir. Aucun des deux
n'a de fond transparent.

La marque n'est pas quatre triangles, contrairement à ce qu'une lecture rapide
suggère. Chaque `<path>` contient deux sous-chemins qui **partagent une arête**,
donc rendent une seule forme. Ce sont **deux barres** :

- barre basse `(219, 167.507) → (389.754, 167.507) → (324.080, 231.611) → (219, 231.611)`
- barre haute `(294.059, 159.493) → (359.733, 95.389) → (464.813, 95.389) → (464.813, 159.493)`

Chacune est un rectangle de 170,754 × 64,104 dont une extrémité est coupée à
**45,7°**, les deux coupes dans le même sens, décalées de +75,059 en x, séparées
par un écart de 8,014. Boîte englobante 245,813 × 136,222, ratio **1,804:1**.

Ce motif, des diagonales parallèles de même sens, est toute l'identité, et c'est
lui qui se transporte dans le design (voir [02](./02-design-systeme.md)).

### La voix

`01-strategie/positionnement.md:69-77` : vouvoiement direct, phrases courtes,
une idée par phrase, zéro adjectif creux, les chiffres avant les promesses,
**pas de tiret cadratin**, pas de jargon.

Le vouvoiement ne transfère pas en anglais. Ce qui transfère : l'adresse
directe, les phrases courtes, une idée par phrase, les faits avant les
promesses, aucun tiret cadratin, aucune familiarité (« Oops! », « Uh oh »).

## Le code

Exécutable SwiftPM pur. **Aucune image dans le repo**, aucun `Info.plist`, aucun
`.xcassets`, aucun `.icns`, aucun projet Xcode. Vérifié par un `find` sur tous
les formats d'image et de projet : zéro résultat.

`Sources/parrot/UI/Style.swift` fait 16 lignes et contient deux couleurs, rien
d'autre. Les ~50 tailles de police, les 8 rayons distincts et tous les
espacements sont des littéraux dispersés sur les sites d'appel. Le commentaire
du fichier documente déjà la distinction qui structure tout le design : le
chrome flottant est sombre dans les deux apparences, la fenêtre est sémantique.

Quatre surfaces seulement, ce qui rend le chantier fini :

| Surface | Fichier | État |
|---|---|---|
| Bulle de dictée | `UI/RecordingOverlay.swift` (193 l.) | `NSPanel` 112×44, capsule, 6 barres, 4 états, **pas d'état d'erreur** |
| Panneau de repli | `UI/TranscriptFallbackPopover.swift` (144 l.) | `NSPanel` 420×148 malgré son nom, rayon 18 |
| Icône menu bar | `UI/MenuBarController.swift:280-302` | SVG Lucide d'un **oiseau**, inliné en dur, rendu en 16×16 |
| Fenêtre de réglages | `UI/Settings/` (8 fichiers) | 900×620, couleurs sémantiques macOS, suit clair/sombre |

Zéro `NSAlert`, zéro `NSPopover`, zéro notification : toutes les erreurs partent
sur stderr.

## Le renommage

53 fichiers contiennent la chaîne. Les points durs, tous vérifiés :

- Le label launchd `com.digimata.parrot` est défini **deux fois** :
  `Install.swift:97` et `scripts/install-local.sh:31`.
- `install-local.sh:43` signe avec `--identifier parrot`. C'est cet identifiant
  que TCC utilise pour ancrer l'autorisation Accessibilité.
- `SettingsStore.swift:20` utilise `UserDefaults.standard` **sans suite** : le
  domaine suit le nom du process. Le renommage **et** la mise en bundle le
  déplacent tous les deux.
- `DoctorLaunchAgentTests.swift:47` assert une chaîne de remédiation mot pour
  mot, et `:23-24` codent le label en dur.
- État utilisateur qu'un renommage orpheline :
  `~/Library/Application Support/parrot/models/` (**plusieurs Go de poids de
  modèles**), `~/Library/Caches/parrot/`, `~/Library/Logs/parrot.log`, le job
  launchd installé, et le frame de fenêtre sauvegardé sous `parrot.settings`.

### Ce qui ne doit surtout pas être renommé

**`/tmp/parrot.out.log` et `/tmp/parrot.err.log`**, dupliqués à `Doctor.swift:75`
et `Install.swift:210`. Ces fichiers ont été écrits par l'ancien parrot, et le
bug est corrigé. Les renommer en `plume` supprimerait silencieusement la
remédiation de confidentialité pour exactement les utilisateurs qui migrent,
c'est-à-dire ceux pour qui elle existe. C'est l'erreur la plus probable d'un
chercher-remplacer mécanique.

**L'histoire non plus.** `.scratch/**` (14 fichiers), `docs/adr/0001` à `0007`
et `.plan/plan.md` racontent ce qui a été fait quand le projet s'appelait
parrot. Les réécrire rendrait malhonnête la lignée que le NOTICE établit. Seuls
les documents tournés vers l'avant sont réécrits : `README.md`, `CONTEXT.md`,
`AGENTS.md`, `docs/architecture.md`.

## Le blocage préalable

`Tests/parrotTests/FnDictationGestureTests.swift` est un fichier **suivi** avec
116 lignes ajoutées non commitées. Les lignes 1 à 61 sont les tests commités ;
le reste teste une feature Escape-cancel qui n'existe pas. Ils attendent
`FnDictationGesture.Input.cancelled` et `Action.discardRecording`, absents de
`Sources/parrot/Input/FnDictationGesture.swift`. `hasActiveRecording`, lui,
existe : ces deux cas d'énumération sont les seules erreurs de compilation.

**`swift build --build-tests` échoue donc aujourd'hui.**

Ce sont de bons tests. Le commentaire sur la minuterie en attente qui annulerait
le timer de la dictée *suivante* est du vrai travail de conception. On les sort
en enregistrant leur intention dans `.scratch/annulation-echap/spec.md`, en
français, en citant les corps de test, avec `Status: needs-triage`.

Conséquence pour le design : cette feature avait déjà, plus tôt le même jour, une
méthode `flash` et un état d'annulation sur la bulle, revertés avec le reste. La
bulle refaite doit donc prévoir **deux** états courts non pilotés par la touche,
l'erreur et l'annulation. Tous deux ont la même contrainte : n'étant pas terminés
par un relâchement de touche, ils ont besoin de leur propre minuterie, avec la
même garde `hideGeneration` que `hide()` utilise déjà.

## Où publier

- `github.com/sprintmob` **existe déjà**, affiché « SprintMob », **zéro dépôt
  public**, contact `youcef@sprintmob.fr`. `plume` y serait le premier dépôt
  public de l'org, ce qui est en soi un geste de marque.
- Le remote actuel est `youssdevx/parrot`, un compte personnel. `upstream` est
  `digimata/parrot`.
- **Aucune formule Homebrew `plume`** n'existe.
- `scripts/install.sh:3` pointe encore vers `digimata.github.io`, un site
  GitHub Pages appartenant à l'upstream.

## La licence

MIT, `Copyright (c) 2026 Andrew Jones`. MIT impose de conserver cette mention :
on **ajoute** une ligne SprintMob, on ne remplace pas.

Le compte exact, vérifié dans le dossier : **25 PR ouvertes upstream, 16
mergées, par 8 auteurs distincts** (`andredezzy` en a 8 à lui seul), plus
`bdeol2` dont la PR a été fermée en doublon mais dont l'analyse TCC a servi.
Créditer « 25 auteurs » serait généreux et faux.

## Quatre dettes préexistantes, sans rapport avec le rebranding

Aucune n'est causée par ce projet. Trois sont réparées gratuitement en passant,
la quatrième bloque la publication.

1. **Aucune CI ne lance `swift test`.** Il n'y a que `release.yml`. C'est
   pourquoi un arbre de tests rouge a survécu sans que rien ne le signale.
2. **Deux bundles de ressources SwiftPM ne sont pas livrés.** `.build/release/`
   produit `swift-crypto_Crypto.bundle` et `swift-transformers_Hub.bundle`, ce
   dernier contenant les configs de tokenizer que swift-transformers cherche via
   `Bundle.module`, dont l'accesseur généré fait `fatalError` s'il ne les trouve
   pas. Le binaire installé aujourd'hui part seul : c'est un crash latent. Le
   bundle `.app` le répare sans effort.
3. **L'obligation Apache-2.0 de `swift-argument-parser` n'est pas honorée.** Sa
   licence doit voyager avec le binaire distribué.
   `Contents/Resources/ACKNOWLEDGEMENTS.txt` est l'endroit naturel.
4. **Les licences de `argmax-oss-swift` (WhisperKit) et `FluidAudio` n'ont
   jamais été vérifiées.** À résoudre **avant** publication, indépendamment de
   tout le reste.
