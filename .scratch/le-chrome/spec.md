# Le chrome

Status: ready-for-human

Sixième feature du programme de `docs/rebranding/`. Consomme les tokens du
commit précédent et l'emplacement de ressources du paquet.

## La bulle

Trois défauts pilotent la refonte, et **aucun des trois n'est une question de
marque**.

### 1. Elle n'a aucun bord sur fond sombre

Une capsule `#0A0A0A` avec une ombre de fenêtre au-dessus d'un terminal noir ou
d'un IDE sombre n'a pas de bord : l'ombre est le seul séparateur, et une ombre
est invisible sur du noir.

Le correctif est un filet de 1pt en `Dark.line`. **C'est le changement le plus
important du lot.** À 14% de `hc-ink` il est invisible sur fond clair, où
l'ombre fait le travail, et il sauve entièrement la bulle sur fond sombre.
C'est aussi la signature partagée avec le panneau de repli et l'icône : ces
trois surfaces sont le même objet à trois tailles.

### 2. `hide()` était faux

Il attendait 0,18 s avant `orderOut` alors que l'animation durait 0,3 s.
**Chaque sortie était coupée à 60%.** La bulle ne s'en allait pas, elle
disparaissait. Le délai est maintenant le token que l'animation utilise, donc
les deux ne peuvent plus diverger.

### 3. L'état de transcription était un spinner système

Dans la couleur d'accent du système, donc la seule chose à l'écran qui ne soit
pas à nous, et c'est le langage visuel de « cette app est bloquée ».

Remplacé par les **mêmes cinq barres**, même pente, même lime ; seul ce qui
pilote leur hauteur change, une bosse qui traverse de gauche à droite sur 1,1 s.
Le relâchement ne remplace plus un objet par un autre : la bulle arrête
d'écouter et se met à travailler, visiblement le même objet.

## Les barres penchent, et c'est là que la marque entre

Le logo est deux barres dont une extrémité est coupée à 45,7°, **les deux
coupes dans le même sens**. Ce motif se transporte directement sur une
waveform : les barres sont cisaillées au lieu d'avoir des bouts en capsule.

Un 45° littéral sur une barre de 3pt fait 0,7pt de pente et ne se voit pas. La
pente retenue est la plus raide qu'une barre de 3pt supporte à 18pt de haut :
**0,20 de la hauteur, soit 11,3° hors de la verticale**, même sens que le logo.
L'écart au logo est écrit dans le code plutôt que découvert plus tard.

**Le piège, évité :** la hauteur est animée **directement**, jamais via
`scaleEffect(y:)`. Un cisaillement suivi d'une mise à l'échelle verticale
redresse l'angle quand la barre rétrécit ; à niveau 0,10 les 11,3° deviendraient
~50° et la barre tomberait.

**Six barres deviennent cinq.** L'enveloppe `[0.55, 0.85, 1.0, 1.0, 0.85, 0.55]`
avait **deux pics égaux et pas de centre**. Cinq barres donnent un vrai centre,
et achètent la largeur pour des barres de 3pt, qui tombent sur des pixels
entiers en 1x comme en 2x, ce que 2,5pt ne fait pas.

**Le plancher passe de 2,2 à 7pt.** Au silence, cinq points de 2,2pt se lisent
« éteint », soit l'inverse de ce à quoi la bulle sert.

Le gain `sqrt(level) * 3.4` et le jitter `0.78...1.0` ne bougent pas : ils sont
réglés.

## L'état `failed`, la seule capacité neuve du rebranding

Un échec de transcription partait sur stderr et nulle part ailleurs, ce qui
pour un démon sous launchd veut dire nulle part.

Triangle corail `Dark.critical` plus « Dictation failed » en `Dark.ink`. Pas de
lime, par la règle de marque : le lime ne porte jamais une sévérité. Le bord
reste `Dark.line` : la bulle est un HUD, pas une alerte, et inonder le contour
de rouge est une échelle d'alarme que ça ne mérite pas.

Le panneau étant `ignoresMouseEvents`, il n'y a rien à cliquer : il se retire
seul après `Motion.failureDwell`. Le jeton `hideGeneration` est ce qui permet à
une nouvelle dictée de le supplanter ; sans lui, une dictée démarrée pendant le
délai serait sortie par le timer de l'échec qu'elle remplace.

**Gaté sur `state.overlayEnabled`** comme tous les autres états : overlay
désactivé, un échec reste aussi muet qu'aujourd'hui.

## Le verrouillage se lit sur le bord

Le signal primaire du double-tap est **le bord de la capsule qui passe en lime
à 45%**, pas un second élément lime à l'intérieur. Les barres sont déjà lime, et
un deuxième lime à une autre taille dilue le premier ; le cadenas reste en
`Dark.ink70`. Le changement de largeur qui s'anime est lui-même le retour qui
dit que le double-tap a été pris.

## Le glyphe de menu bar

Le mark ne survit pas à 16pt, et la raison est un seul nombre. Il n'y a pas de
fins interstices entre quatre triangles : il n'y a **qu'un écart horizontal**
entre deux barres, qui vaut 8,014 / 136,222 = 5,88% de la hauteur. Ajusté à
16pt de large au vrai ratio, il tombe à **0,52pt**. Sous-pixel. Les deux barres
fusionnent en une dalle grise.

La réponse n'est pas un autre glyphe : c'est une **taille de corps redessinée**.
On garde les deux barres et les deux coupes, qui sont toute l'identité, et on ne
change que les deux ratios qui cassent. L'écart passe de 12,5% à **50%** de la
hauteur d'une barre. C'est ce que fait une fonderie pour un petit corps.

Le décodage du SVG inliné par `NSImage` a été vérifié : il rend un
`_NSSVGImageRep` valide. Reste à confirmer le poids optique sur appareil.

## L'icône

Plate. Squircle `#0A0A0A` aux proportions du gabarit macOS, le même filet
`hc-line`, mark lime à 62% de la largeur.

**Fond noir avec mark lime, et non l'inverse.** Les deux sont légaux, le lime
étant un aplat dans les deux cas. Le noir gagne parce qu'il correspond au seul
autre endroit où l'utilisateur voit la marque, la bulle, et parce que la posture
du produit est un démon silencieux tant qu'on n'appuie pas. La variante inverse
existe pour le README, où crier est correct.

**Deux sources, et c'est le détail qui se rate.** À 64px l'écart du mark vrai
vaut 1,04px, donc réduire la source 1024 produit la même dalle grise que le
glyphe menu bar évite. Donc : ≥ 128px depuis `plume-icon.svg`, ≤ 64px depuis
`plume-icon-small.svg`. Vérifié en rendant les deux à 64px côte à côte : la
différence est exactement celle que le plan prédisait.

`Design/` est **à côté** de `Sources/`, pas dedans : ce sont des entrées de
build, et les mettre sous la cible traînerait un bundle de ressources dans un
binaire qui n'en a jamais eu.

**Le `.icns` est commité.** Le repo part en open source : un contributeur sur un
checkout propre ne doit pas avoir besoin de `librsvg` pour obtenir une app avec
une icône. `scripts/make-icns.sh` existe pour régénérer quand la source change,
et il utilise `rsvg-convert` s'il est là, sinon `scripts/render-svg.swift`, un
rendu AppKit qui ne demande rien de plus qu'Xcode.

## Vérification

- `swift test` : 94 tests, 0 échec. Le repo ne teste aucune UI et ce commit ne
  change pas cette règle.
- `./scripts/bundle.sh` : le paquet embarque `plume.icns` et
  `CFBundleIconFile`, `codesign --verify --strict` et `plutil -lint` passent.
- **La géométrie de la bulle a été rendue hors application**, dans un harnais
  jetable reproduisant les mêmes nombres, aux quatre niveaux et dans l'état
  verrouillé. Le cisaillement est cohérent, le centre est un vrai centre, le
  plancher se lit « allumé », et le filet est visible sur un fond moyen.
- Les deux coupes de l'icône ont été rendues à 64px et comparées.

## Ce qu'il faut vérifier sur appareil

Rien de tout ça ne s'exerce sans démon lancé, et c'est le commit qui en demande
le plus.

1. **L'item de menu bar apparaît vraiment.** C'est le point le plus fragile :
   sans titre ni tooltip de repli, un glyphe qui ne se décode pas donne un item
   **vide et silencieux**. En clair et en sombre, en 1x et en 2x, et vérifier
   que l'écart inter-barres ne s'est pas refermé.
2. **La bulle dans ses cinq états**, dont l'état d'échec qui est neuf,
   **au-dessus d'une fenêtre claire et d'une fenêtre sombre**. Le second cas est
   celui que le filet existe pour régler. Plus par-dessus une app en plein
   écran, puisque c'est ce que le niveau `.screenSaver` sert à couvrir.
3. **La sortie de la bulle**, qui devrait maintenant se terminer au lieu d'être
   coupée à 60%.
4. **Le panneau de repli** sur un poste multi-écran, pour le bug `NSScreen.main`
   corrigé ici : il pouvait s'afficher sur un autre écran que la bulle qui
   venait de s'afficher.
5. **L'icône dans le Dock et dans le Finder**, aux petites tailles.
