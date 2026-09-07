# Les tokens

Status: ready-for-human

Cinquième feature du programme de `docs/rebranding/`, et la première qui touche
au visuel. Elle est séparée de la refonte du chrome pour une raison de
relecture : **une substitution de tokens sans intention visuelle se révise, un
redesign mêlé à une substitution ne se révise pas.**

## Ce que remplace `Style.swift`

Avant : 16 lignes, deux couleurs, et ~50 tailles de police, 8 rayons distincts
et tous les espacements dispersés en littéraux sur les sites d'appel.

Après : la palette `hc-*` de SprintMob reprise **un pour un**, plus quatre
tailles de texte, quatre de glyphe, une grille d'espacement de 4, cinq rayons et
cinq courbes de mouvement.

Le commentaire du fichier existant avait déjà raison sur ce qui structure tout :
le chrome flottant est sombre dans les deux apparences, la fenêtre est
sémantique. Le rebranding ne combat pas cette architecture, il la nomme.

L'échelle sombre de la marque tombe d'ailleurs juste sur les littéraux déjà
écrits en dur : `.white` devient `Dark.ink`, `.white.opacity(0.65)` devient
`Dark.ink70` (0,72), et `.white.opacity(0.08)` devient `Dark.lineSoft`, dont
l'alpha `0x14` **vaut exactement** 0,08. C'est asserté dans un test.

## La règle qui contraint tout le reste

> « lime sur noir passe, lime sur blanc non : jamais de texte lime sur fond
> clair »

Vérifié plutôt que cru. Luminance relative WCAG, calculée depuis les tokens :

| paire | mesuré | plan |
|---|---|---|
| `lime` sur blanc | **1,13:1** | 1,13 |
| `lime` sur `hc-bg` | 17,5:1 | 17,5 |
| `hc-ink` sur `hc-bg` | 18,5:1 | 18,6 |
| `hc-ink-70` sur `hc-bg` | 9,7:1 | 9,7 |
| `hc-ink-45` sur `hc-bg` | 5,1:1 | 5,1 |
| `critical` sur `hc-bg` | 7,8:1 | 7,8 |

1,13:1, ce n'est pas « peu contrasté », c'est **invisible**. Le bleu pâle
`#B5D1FF` avait déjà ce défaut à 1,55:1 : c'est un bug préexistant à corriger,
pas à reproduire.

`StyleContrastTests` rend la règle exécutable, en la calculant depuis les
tokens et non en recopiant les chiffres du document, donc changer un hexa doit
affronter ces neuf cas. Trois d'entre eux assertent qu'un token est **sous** le
seuil de texte : `ink25`, `line` et `lineSoft` sont de la décoration, et
personne ne doit les promouvoir en libellé sans que ça casse.

## Une fonte, et une seule

`KeyCap` utilisait `design: .rounded`, c'est-à-dire **SF Rounded, une deuxième
police, dans un seul contrôle**. Supprimé. L'app a maintenant exactement une
fonte, et elle passe par une fabrique unique, `Style.font(_:_:)`.

Cette fabrique existe pour une raison précise : Euclid Circular B, la police de
la marque, n'est **pas embarquée**, faute de licence de redistribution établie
et parce que le repo part en open source. Si la licence est un jour éclaircie,
le mécanisme est un `CTFontManagerRegisterFontsForURL` au lancement, et cette
fonction est la seule chose qui change.

## Ce qui n'est pas dans ce commit

Volontairement, pour que celui-ci reste relisable en diagonale :

- **La géométrie de la bulle**, ses barres cisaillées, son état d'échec et la
  correction de `hide()`. Commit suivant.
- **Le filet 1pt** des deux surfaces flottantes, et la correction
  `NSScreen.main` du panneau de repli. Commit suivant.
- **La pastille « Recommended »** qui remplace une étoile lime invisible en
  apparence claire, les puces de sidebar, et les 38 littéraux de police restants
  de la fenêtre. Ce sont des changements de composant, pas de token, et la
  fenêtre a son propre commit.
- **La copie.** Un seul texte a bougé ici, et par accident du refactor : aucun.

Les tailles de police qui ne tombent pas sur l'échelle (9, 10, 12, 15) sont
restées telles quelles. Les normaliser est un choix visuel, pas une
substitution, et il se prend là où la fenêtre se regarde.

## Vérification

- `swift test` : 94 tests, 0 échec, dont 9 neufs sur le contraste.
- `swift build -c release` : vert.
- Aucun changement de comportement : ce commit ne touche à aucun chemin de
  code, seulement à des valeurs de présentation.

## Ce qu'il faut regarder sur appareil

La bulle et le panneau sont maintenant en `#0A0A0A` au lieu de `#101212`, et
lime au lieu de bleu. Rien de tout ça ne se vérifie sans un démon lancé, et
c'est le commit suivant qui règle le vrai problème de ces surfaces, qui est
qu'elles n'ont aucun bord sur fond sombre.
