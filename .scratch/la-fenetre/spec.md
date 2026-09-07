# La fenêtre, et la copie

Status: ready-for-human

Septième feature du programme de `docs/rebranding/`.

## Ce que la fenêtre ne fait pas

**Elle garde les couleurs sémantiques macOS.** Argumenté contre l'alternative,
qui serait de la passer au système paper/ink de la marque :

- C'est une fenêtre de réglages, c'est-à-dire la surface qu'un utilisateur
  macOS lit comme une surface système. Ignorer son réglage d'apparence est le
  signal « pas d'ici » le plus fort qu'une app puisse envoyer, et ça casse
  silencieusement Augmenter le contraste et Réduire la transparence, que
  `.windowBackgroundColor`, `.controlBackgroundColor` et `.separatorColor`
  honorent gratuitement.
- Le système paper est éditorial, fait pour des titres de 118pt et Instrument
  Serif. Il n'a rien à dire à un `Picker`, un `Toggle`, un anneau de focus ou
  la vibrance d'une sidebar. S'y engager veut dire réimplémenter tout ça, moins
  bien qu'AppKit.
- La direction artistique de la marque n'est **pas tranchée** : deux frames
  vivants s'arbitrent dans le canvas. Graver une direction non résolue dans un
  binaire compilé est la façon coûteuse de se tromper. Le sémantique survit aux
  deux issues.

**Le vert/orange/rouge du docteur reste**, et c'est la marque qui le décide :
le lime étant explicitement interdit de sévérité, la sévérité a besoin de ses
propres couleurs. Deux raisons de plus que ce n'est pas un compromis. Les
`.green` / `.orange` / `.red` de SwiftUI sont les couleurs **dynamiques** du
système, déjà adaptées à l'apparence et au réglage Augmenter le contraste ;
substituer des valeurs calées pour un fond `#0A0A0A` dans une fenêtre qui peut
être blanche serait un recul. Et `CheckRow` associe déjà un symbole SF distinct
à chaque couleur, donc l'information n'est pas portée par la couleur seule.
C'est l'argument d'accessibilité pour **garder** les teintes.

**Pas de chrome de marque dans la sidebar.** Un mark et un wordmark en haut
d'une sidebar macOS est une habitude web. L'icône du Dock est déjà visible dès
que cette fenêtre est ouverte.

## Ce que le lime y fait : deux aplats, zéro premier plan

1. **Les puces de sidebar.** `.orange` pour Home et `.purple` pour History
   venaient de nulle part. Les deux passent en lime, et le glyphe passe de
   `.white` à `Style.onLime`, parce que blanc sur lime est à 1,13:1. On **garde**
   la distinction teinté / non teinté : elle signifie « les lignes teintées
   montrent quelque chose, les autres changent quelque chose », et les puces
   colorées sont l'idiome natif de Réglages depuis Ventura. Deux teintes
   arbitraires meurent, la distinction survit, et le lime devient identique en
   clair et en sombre.
2. **Le marqueur « recommandé »**, aujourd'hui une `star.fill` lime en premier
   plan, donc **invisible en apparence claire**. L'étoile devient le mot, sur
   une capsule lime : le lime employé de la seule façon qui marche, en aplat, et
   ça dit ce que ça voulait dire.
3. C'est tout.

Les trois autres usages de l'accent passent au sémantique, chacun pour sa
raison : « Active » est un **statut**, et le lime ne porte pas de statut, donc
c'est la graisse qui le porte ; le `lock.fill` de l'historique est un glyphe de
réassurance ; « Copied » est un retour transitoire parti en une seconde.

Les boutons restent teintés par le système. `.borderedProminent` avec
`.tint(lime)` laisserait SwiftUI choisir la couleur du label, qui serait blanc
sur lime à 1,13:1. Aucun bouton de cette fenêtre ne justifie de passer outre :
« Check again » n'est pas un call to action.

## Le balayage des littéraux

**Il ne reste aucun `.system(size:)` dans l'app** en dehors de la fabrique
`Style.font`. C'est ce qui rend l'embarquement éventuel d'Euclid Circular B un
changement d'une fonction.

Les tailles qui ne tombaient pas sur l'échelle ont été tranchées une par une,
et ce sont de vrais choix visuels, pas des substitutions :

| avant | après | pourquoi |
|---|---|---|
| 15 (valeurs du résumé Home) | `Text.title` 17 | La typo la plus proéminente de la fenêtre ; 15 n'est sur aucune échelle |
| 12 (texte secondaire) | `Text.caption` 11 | SF a un hinting calé sur exactement 11 et 13pt sur macOS |
| 12 (glyphes) | `Glyph.md` 12 | Identique, la valeur était déjà juste |
| 10 (glyphes) | `Glyph.sm` 10 | Identique |
| 9 (étoile) | supprimé | Remplacée par la capsule |

Idem pour les rayons, par la règle de calage : `5→xs`, `8→sm`, `9→btn`,
`10→btn`. Il ne reste aucun `cornerRadius:` numérique. Les espacements se calent
sur la grille de 4 ; les **largeurs de colonne** ne bougent pas, ce sont des
dimensions de mise en page, pas des marges.

## La copie

Le plan comptait cinq tirets cadratins dans les chaînes visibles. Il y en avait
**vingt** en comptant la sortie CLI et stderr, qui sont de la copie aussi. Tous
sont partis.

Et trois corrections qui dépassent le style :

- **Une remédiation du docteur disait « hold Fn »** à tout le monde, y compris à
  ceux qui ont changé de raccourci, c'est-à-dire exactement les gens le moins en
  mesure de deviner ce qu'elle voulait dire. La touche était déjà résolue un
  appel plus haut ; `checkMicrophone` la reçoit maintenant.
- **Le détail du mode paste mentait** : « puts back what was there ». ADR-0006 a
  supprimé la restauration du presse-papier il y a deux commits d'histoire. Il
  dit maintenant ce que le code fait.
- **Le nom du produit se capitalise** dans le titre de fenêtre et le menu
  d'application, où macOS attend le nom de l'app. La commande reste `plume`.

## Vérification

- `swift test` : 94 tests, 0 échec.
- Aucun `.system(size:)` et aucun `cornerRadius:` numérique hors des tokens.
- `./scripts/check-rename.sh` : vert.

## Ce qu'il faut vérifier sur appareil

C'est là que le lime se casse la figure si la règle de fond clair n'a pas été
respectée.

1. **Les cinq sections en apparence claire et en apparence sombre.**
2. **Les puces de sidebar** : glyphe sombre sur lime, lisible dans les deux.
3. **La capsule « Recommended »** dans la table des modèles, en clair surtout,
   puisque c'est le cas où l'étoile n'existait pas.
4. **Les tailles normalisées** : les valeurs du résumé Home passées de 15 à 17
   sont tronquées au milieu si le nom du modèle est long, et la table des
   modèles est passée de 12 à 11.
5. **Le docteur** avec un vrai avertissement, pour que le vert/ambre/rouge et
   ses symboles se voient.
