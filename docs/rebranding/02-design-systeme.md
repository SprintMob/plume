# Design système

## Deux questions tranchées d'abord

### Euclid Circular B n'est pas embarquée. La police système reste.

Trois raisons, par ordre de force.

**La licence n'existe pas.** Détail dans [01](./01-etat-des-lieux.md#la-typographie-et-son-problème-de-licence).
Le repo part en open source : le binaire de la police atterrirait dans un dépôt
public et dans chaque artefact de release, ce qui est une redistribution du
fichier de police lui-même. On ne livre pas un `.ttf` commercial dans un binaire
public sur une licence non vérifiée. Ça suffit à clore la question.

**Même sous licence, ce serait la mauvaise police pour cette surface.** Euclid
Circular B est un géométrique. Un géométrique en 11pt dans une table de réglages
dense perd sur les deux choses qui comptent à cette taille : les contreformes
circulaires se bouchent, et il n'y a pas d'axe optique. SF a un chasse par
taille, une coupe optique qui bascule à 20pt, et un hinting calé sur exactement
11 et 13pt sur macOS. En changer coûte de la lisibilité aux deux seules tailles
que cette app utilise vraiment.

**Une fenêtre de réglages macOS dans une police non système se lit comme un
portage Electron.** La règle de voix de la marque est « zéro adjectif creux ».
Une police d'UI personnalisée ici est un adjectif creux.

Où Euclid reste : la page d'atterrissage, les visuels du README, les captures de
release, et l'icône si un wordmark y est voulu, parce que c'est un usage
**image** couvert par la licence de bureau, pas un embarquement de police.

Si la licence est un jour éclaircie, le mécanisme est un
`CTFontManagerRegisterFontsForURL(_:.process,_)` au lancement. Le jeu de tokens
ci-dessous a une fabrique `Style.font(_:_:)` unique pour que ce changement ne
touche qu'une fonction.

**Corollaire immédiat :** `KeyCap` utilise `design: .rounded`
(`SettingsControls.swift:125`), c'est-à-dire une **deuxième** police, SF
Rounded, dans un seul contrôle. On la supprime. L'app a alors exactement une
fonte.

### La fenêtre de réglages garde les couleurs sémantiques macOS

Argumenté contre l'alternative, qui serait de la passer au système paper/ink :

- **C'est une fenêtre de réglages.** C'est la surface qu'un utilisateur macOS
  lit comme une surface système. Ignorer son réglage d'apparence est le signal
  « pas d'ici » le plus fort qu'une app puisse envoyer, et ça casse
  silencieusement Augmenter le contraste et Réduire la transparence, que
  `.windowBackgroundColor`, `.controlBackgroundColor` et `.separatorColor`
  honorent gratuitement.
- **Le système paper est éditorial**, fait pour des titres de 118pt et
  Instrument Serif. Il n'a rien à dire à un `Picker`, un `Toggle`, un anneau de
  focus, une ligne de sidebar sélectionnée ou la vibrance d'une sidebar. S'y
  engager veut dire réimplémenter tout ça, moins bien qu'AppKit.
- **La direction artistique n'est pas tranchée.** Deux frames vivants, A contre
  B. Graver une direction non résolue dans un binaire compilé est la façon
  coûteuse de se tromper. Le sémantique survit aux deux issues, parce que la
  fenêtre de réglages n'est pas le site et n'allait jamais l'être.

La présence de marque dans cette fenêtre ne passe pas par la palette. Elle passe
par le glyphe (Dock, menu bar), par le lime en aplat à trois endroits, et par la
voix. Les trois marchent sur un fond sémantique.

Le chrome flottant est le cas inverse et prend `hc-*` en entier. Cette
distinction existe déjà dans le commentaire de `Style.swift:4-9` ; le rebranding
la garde et lui donne de vrais tokens.

## Les tokens

Remplace `Sources/parrot/UI/Style.swift` en entier. Le chemin devient
`Sources/plume/UI/Style.swift` après c1.

```swift
import SwiftUI

/// SprintMob's tokens, trimmed to what a macOS menu-bar app uses.
///
/// Source of truth is `website/website.pen`. Three rules travel with them,
/// in the order they bind:
///
/// 1. Lime is a FILL. Never a foreground on a light ground. The brand states
///    it: "lime sur noir passe, lime sur blanc non : jamais de texte lime sur
///    fond clair". #E0FE75 has a relative luminance of 0.880: 1.13:1 on white,
///    17.5:1 on #0A0A0A.
/// 2. Lime never carries severity. "Le lime #E0FE75 reste réservé au CTA et
///    aux accents. Il ne sert jamais à une sévérité." That is why the doctor
///    keeps green/orange/red and why the pill's failure is coral.
/// 3. Chrome that floats over another app's window is dark in both system
///    appearances and takes the `hc-*` scale. A window of ours follows the
///    system appearance and takes the semantic colours.
enum Style {

    // MARK: - Brand

    /// #E0FE75. The one hue in the system.
    static let lime = Color(hex: 0xE0FE75)
    /// What goes on top of `lime`. Never white.
    static let onLime = Color(hex: 0x0A0A0A)

    // MARK: - Dark chrome (hc-*)

    /// The floating surfaces: the pill and the fallback panel. Dark in both
    /// appearances on purpose. They sit over another app's window, where a
    /// light panel reads as that app's own UI rather than as plume.
    enum Dark {
        static let bg       = Color(hex: 0x0A0A0A)                // hc-bg
        static let elev     = Color(hex: 0x121212)                // hc-elev
        static let elev2    = Color(hex: 0x181818)                // hc-elev-2
        static let ink      = Color(hex: 0xF7F8F3)                // hc-ink     18.6:1 on bg
        static let ink70    = Color(hex: 0xF7F8F3, alpha: 0.72)   // hc-ink-70   9.7:1
        static let ink45    = Color(hex: 0xF7F8F3, alpha: 0.50)   // hc-ink-45   5.1:1
        static let ink25    = Color(hex: 0xF7F8F3, alpha: 0.25)   // hc-ink-25
        static let line     = Color(hex: 0xF7F8F3, alpha: 0.14)   // hc-line
        static let lineSoft = Color(hex: 0xF7F8F3, alpha: 0.08)   // hc-line-soft
        /// sev-critical. The only status colour the dark chrome owns. It exists
        /// so the pill can say "that failed" without reaching for lime. 7.8:1.
        static let critical = Color(hex: 0xFF7A6B)
    }

    // MARK: - Type

    /// Four steps. 11 and 13 are `NSFont.smallSystemFontSize` and
    /// `NSFont.systemFontSize`; they sit 1.18 apart, not 1.25, and that is
    /// deliberate. An app that picks its own body size stops looking like a
    /// macOS app, and the 11/13 pair is distinguished by weight and by
    /// secondary/primary colour, not by size. Every step that actually carries
    /// hierarchy clears 1.25: 13 -> 17 is 1.31, 17 -> 22 is 1.29.
    enum Text {
        static let caption: CGFloat = 11
        static let body: CGFloat = 13
        static let title: CGFloat = 17
        static let display: CGFloat = 22
    }

    /// Glyph sizes, separate from text: an SF Symbol at 13 does not read the
    /// size a word at 13 does.
    enum Glyph {
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 22
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Numbers that change in place (percentages, sizes) get tabular figures
    /// so the row does not twitch as they tick.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    // MARK: - Space

    /// SprintMob's 4px grid, as far up as a 900pt window goes.
    enum Space {
        /// Half-step. The grid has no 2, and a title-to-rule inset needs one.
        static let half: CGFloat = 2
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        /// Below the brand's floor of 8. macOS chrome has chips a web page
        /// does not: a key cap is 19pt tall, and 8 on 19 is a pill.
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8    // radius-sm
        static let btn: CGFloat = 10  // radius-btn
        static let md: CGFloat = 12   // radius-md
        static let lg: CGFloat = 16   // radius-lg
        // radius-xl 24 / radius-2xl 32 have no use here. A 152pt panel with a
        // 24 radius reads as an iOS sheet.
    }

    // MARK: - Motion

    enum Motion {
        /// The pill arriving and leaving. Expo-out: most of the distance in the
        /// first third of the time, so it reads as "already there".
        static let entrance = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.28)
        /// One audio frame of catch-up on a waveform bar.
        static let level = Animation.easeOut(duration: 0.09)
        /// A change inside the pill that is not an entrance.
        static let swap = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)
        /// How long `hide()` waits before ordering the panel out. Must be >=
        /// `entrance`'s duration or the pill is yanked mid-animation.
        static let dismissDelay: TimeInterval = 0.28
        /// How long the failure pill stays up. Long enough to read two words
        /// after the entrance, short enough to stay out of the way.
        static let failureDwell: TimeInterval = 2.4
    }
}

extension Color {
    /// 0xRRGGBB with optional separate alpha, so the token table reads as the
    /// hex the brand file states.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
```

### Contrastes, calculés

| paire | ratio |
|---|---|
| `#E0FE75` sur blanc | **1,13:1**, interdit en premier plan |
| `#E0FE75` sur `#0A0A0A` | 17,5:1 |
| `hc-ink` sur `hc-bg` | 18,6:1 |
| `hc-ink-70` sur `hc-bg` | 9,7:1 |
| `hc-ink-45` sur `hc-bg` | 5,1:1, AA en 11pt |
| `sev-critical` sur `hc-bg` | 7,8:1 |

Conversions d'alpha : `B8` = 0,72, `80` = 0,50, `40` = 0,25, `24` = 0,14,
`14` = 0,08 exactement.

### Règle de calage, mécanique

Pour que personne n'ait à re-décider site par site :

- **Marges et écarts entre composants** se calent sur la grille de 4. Entre une
  icône et son propre label : vers le **bas**. Entre deux blocs : vers le
  **haut**.
- **Les métriques internes d'un glyphe dessiné** (largeur de barre, écart entre
  barres, proportions du mark) **ne se calent pas**. La grille gouverne la mise
  en page, pas le dessin.
- Rayons : `5→xs`, `8→sm`, `9→btn`, `10→btn`, `18→lg`, `Capsule` reste `Capsule`.

## La bulle

Trois défauts pilotent la refonte, et aucun n'est une question de marque.

1. **Elle disparaît sur du contenu sombre.** Une capsule `#101212` avec une
   ombre de fenêtre au-dessus d'un terminal noir ou d'un IDE sombre n'a pas de
   bord. L'ombre est le seul séparateur, et elle est invisible sur du noir.
2. **`hide()` est faux.** `RecordingOverlay.swift:52` attend 0,18 s avant
   `orderOut` alors que l'animation ligne 148 dure 0,3 s. **La sortie est coupée
   à 60% à chaque fois.** La bulle ne s'en va pas, elle disparaît.
3. **L'état de transcription est un spinner système.** Dans la couleur d'accent
   du système, donc la seule chose à l'écran qui ne soit pas à nous, et c'est le
   langage visuel de « cette app est bloquée ».

### Géométrie

| | aujourd'hui | nouveau |
|---|---|---|
| panneau | 112 × 44 | **176 × 48** (doit loger l'état d'échec ; transparent et click-through, donc le mou est gratuit) |
| conteneur | `Capsule().fill(#101212)` | `Capsule(style: .continuous).fill(Dark.bg)` + **filet 1pt `Dark.line`** |
| marges | h14 / v9 | h `Space.x3` / v `Space.x2` |
| barres | 6 × 2,5pt, écart 4, bouts capsule | **5 × 3pt, écart 5, cisaillées** |
| amplitude | 2,2…22pt | **7…18pt** |
| couleur | `#B5D1FF` | `Style.lime` |

**Le filet est le changement le plus important du lot.** `hc-line` à 14% de
blanc est invisible sur fond clair, où l'ombre fait le travail, et sauve
entièrement la bulle sur fond sombre. C'est aussi la signature partagée avec le
panneau de repli et l'icône.

**Barres de 6 à 5**, parce que l'enveloppe actuelle `[0.55, 0.85, 1.0, 1.0,
0.85, 0.55]` a **deux pics égaux et pas de centre**. Cinq barres donnent un vrai
centre : `[0.52, 0.80, 1.0, 0.80, 0.52]`. Ça achète aussi la largeur pour des
barres de 3pt, qui tombent sur des pixels entiers en 1x comme en 2x, ce que
2,5pt ne fait pas.

**Plancher de 2,2 à 7pt** : au silence, six points de 2,2pt se lisent
« éteint », soit l'inverse de ce à quoi la bulle sert.

Le gain (`sqrt(level) * 3.4`, clampé) et le jitter (`0.78...1.0`) ne bougent
pas : ils sont réglés et il n'y a aucune raison d'y toucher.

### Les barres penchent

C'est là que la marque entre dans la géométrie plutôt que dans la couleur. Le
logo est deux barres dont une extrémité est coupée à 45,7°, **les deux coupes
dans le même sens**. Ce motif se transporte directement sur une waveform : les
barres sont cisaillées au lieu d'avoir des bouts en capsule.

Un 45° littéral sur une barre de 3pt fait 0,7pt de pente et ne se voit pas. La
pente retenue est donc la plus raide qu'une barre de 3pt supporte à 18pt de
haut : **0,20 de la hauteur, soit 11,3° hors de la verticale**, même sens que le
logo. L'écart au logo est écrit dans le code.

```swift
/// One waveform bar. A rectangle sheared so its top edge leads its bottom
/// edge, in the direction the logo cuts the ends of its two bars.
///
/// The logo's own cut is 45.7°, which on a 3pt-wide bar is 0.7pt of lean and
/// invisible. 0.20 of the height (11.3° off vertical) is the steepest lean a
/// 3pt bar survives at this size. Same direction, readable angle.
private struct ShearedBar: Shape {
    static let shear: CGFloat = 0.20

    func path(in rect: CGRect) -> Path {
        let d = rect.height * Self.shear / 2
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + d, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + d, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - d, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX - d, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
```

La forme peint ±1,8pt hors de son cadre de 3pt. C'est voulu : les barres sont à
8pt d'entraxe, le dégagement horizontal minimal entre voisines est de 5pt à
n'importe quel y, et le débord extérieur mange 1,8 des 12pt de marge.

**Piège évité : la hauteur est animée directement, pas via `scaleEffect(y:)`.**
Un cisaillement suivi d'une mise à l'échelle verticale redresse l'angle quand la
barre rétrécit ; à niveau 0,10 les 11,3° deviendraient ~50° et la barre
tomberait. Animer le cadre garde l'angle constant. Cinq formes à ~20 Hz ne
coûtent rien.

### Les cinq états

```swift
enum State: Equatable {
    case hidden
    case recording
    case locked
    case transcribing
    case failed
}
```

**recording** : 62 × 34. Cinq barres lime penchées.

**locked** : 80 × 34. Le glyphe de cadenas en `Dark.ink70`, **pas en lime** :
les barres sont déjà lime, et un second élément lime à une autre taille dilue le
premier. Le signal primaire est **le bord de la capsule qui passe en lime à
45%**. Le changement de largeur de 18pt s'anime, et c'est lui-même le retour qui
dit que le double-tap a été pris.

**transcribing** : 62 × 34. Mêmes cinq barres, même pente, même lime ; seul ce
qui pilote leur hauteur change, une bosse qui traverse de gauche à droite sur
une période de 1,1 s. Le relâchement ne remplace plus un objet par un autre : la
bulle arrête d'écouter et se met à travailler, visiblement le même objet. Ça
remplace le `ProgressView` système entièrement.

**failed** : ~128 × 34, l'état neuf. Triangle corail `Dark.critical` en
`Glyph.sm` plus **« Dictation failed »** en `Text.caption .medium` sur
`Dark.ink`. Pas de lime, par la règle 2. Le bord reste `Dark.line` : la bulle
est un HUD, pas une alerte, et inonder le contour de rouge est une échelle
d'alarme que ça ne mérite pas.

Le panneau étant `ignoresMouseEvents = true`, il n'y a rien à cliquer et le
message doit être complet tel quel. Il se retire seul après
`Motion.failureDwell`, et une nouvelle dictée le supplante par le jeton de
génération existant :

```swift
    /// Show the failure pill, then take it away on its own. The panel is
    /// click-through: there is nothing to dismiss it with, so it dismisses
    /// itself, and a new recording started inside the dwell supersedes it
    /// through the same generation token `hide()` uses.
    func showFailure() {
        show(.failed)
        hideGeneration &+= 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Style.Motion.failureDwell) {
            [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            self.hide()
        }
    }
```

`Parrot.swift:318-323` devient `overlay.showFailure()` au lieu de
`overlay.hide()`, en gardant la ligne stderr. **À gater sur
`state.overlayEnabled` comme le reste** : overlay désactivé, un échec doit
rester muet, exactement comme aujourd'hui.

### Motion

- L'entrée passe de `0 → 1` centré à **`0,86 → 1` ancré en bas** avec un fondu.
  Une mise à l'échelle depuis zéro est un « pop » qui se lit comme joueur et
  étale l'ombre de la fenêtre ; 0,86 avec fondu se lit « c'était déjà là ».
  L'ancrage en bas correspond à où la bulle vit réellement, à 32pt du bord.
- `hide()` passe de 0,18 à `Motion.dismissDelay` (0,28), égal à la durée de
  l'animation. C'est une correction de bug, pas un choix de style.

## Le glyphe de menu bar

### Le mark ne survit pas à 16pt

Il n'y a pas de fins interstices entre quatre triangles : il n'y a **qu'un seul
écart horizontal** entre les deux barres, qui vaut 8,014 / 136,222 = **5,88% de
la hauteur totale**. Ajusté à 16pt de large au vrai ratio, la hauteur tombe à
8,87pt et l'écart à **0,52pt**. Sous-pixel. Les deux barres fusionnent en une
dalle grise et le mark n'existe plus.

### La réponse est une taille de corps redessinée

Pas un autre glyphe. On garde les deux barres et les deux coupes, qui sont toute
l'identité, et on ne change que les deux ratios qui cassent : on comprime la
longueur dans une boîte plus carrée, et on ouvre l'écart. C'est ce que fait une
fonderie pour une coupe petit corps.

Grille 16 × 16, y vers le bas, glyphe sur x 1..15 et y 3..13 :

- **barre haute** `(5,7) → (9,3) → (15,3) → (15,7)`
- **barre basse** `(1,9) → (11,9) → (7,13) → (1,13)`
- barres de 4px de haut, écart de 2px, glyphe 14 × 10.

| ratio | logo | coupe 16pt | pourquoi |
|---|---|---|---|
| angle de coupe | 45,7° | 45,0° | grille entière |
| longueur / hauteur | 2,66 | 2,50 | tenir dans une boîte de 14 |
| décalage / longueur | 0,440 | 0,40 | grille entière |
| **écart / hauteur de barre** | **0,125** | **0,50** | 0,52px → 2px. Le seul changement qui compte |
| ratio | 1,804 | 1,40 | conséquence |

En 1x : deux barres de 4px, 2px d'écart, chaque arête sur un pixel entier sauf
les deux diagonales à 45°, qui sont le meilleur cas pour l'antialiasing. En 2x :
8px et 4px. Le glyphe est à 80% d'encre sur sa hauteur, donc **plus léger** que
le logo à 94%, ce qui est correct à côté de symboles SF tracés en 1,5pt.

```swift
    // Inlined SprintMob mark, redrawn for 16pt. Same two bars, same 45° shears,
    // same direction: only the gap between them is opened, from the logo's 12.5%
    // of a bar's height to 50%. At 16pt the logo's own gap is half a pixel and
    // the two bars fuse into a grey slab. Every edge but the two diagonals lands
    // on a whole pixel at 1x.
    //
    // Keeping it in source means the executable has no separate resource bundle
    // to install alongside it.
    // Source of truth: website/logos/sprintmob-logo-white.svg
    private static let markSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" \
    viewBox="0 0 16 16" fill="black">\
    <path d="M5 7L9 3H15V7H5Z"/>\
    <path d="M1 9H11L7 13H1V9Z"/>\
    </svg>
    """
```

`fill="black"` parce que `isTemplate = true` ne garde que l'alpha ; AppKit
recolore. Renommer `birdSVG` → `markSVG` et `birdImage()` → `markImage()`.

### Deux points à vérifier sur appareil

**Le décodage.** `configureButton` fait `button.image = markImage()` sans titre
ni tooltip de repli. Si `NSImage(data:)` ne décode pas le SVG inliné, l'item de
menu bar est **vide et silencieux**. Si ça échoue, tracer en `NSBezierPath`, ce
qui donne en prime le calage sur la grille de pixels que la rastérisation SVG ne
garantit pas.

**Le poids optique.** Un glyphe de 14 × 10 dans un emplacement de 16pt peut se
lire léger à côté de ses voisins. Le correctif serait `image.size = 18 × 18` avec
le même chemin, qui donne 15,75 × 11,25 et sort de la grille : à ne prendre que
si une vraie capture le réclame.

### Pas de teinte d'état sur le glyphe

`NSStatusBarButton.contentTintColor` teinte bien une image template, donc le
passer en lime pendant l'enregistrement est tentant. Non : la menu bar suit
l'apparence système, et le lime sur une menu bar claire est à 1,13:1, invisible.
C'est un cas où la règle de contraste tue une bonne idée. La bulle porte déjà
l'état.

## L'icône d'app

Plate. Pas de dégradé, pas de biseau, pas de verre.

- **Toile** 1024 × 1024, transparente.
- **Fond** squircle à x=100, y=100, 824 × 824, rayon 185,4 (proportions du
  gabarit macOS Big Sur+ : 824 × 0,225), rempli **`#0A0A0A`**.
- **Filet** trait de 4px en `#F7F8F3` à 14% (`hc-line`), inséré de 2px. Même
  signature que la bulle et le panneau. C'est ce qui empêche une tuile presque
  noire de se lire comme un trou dans le Dock, sans recourir à un dégradé.
- **Mark** aux **vraies proportions du logo** (à 1024 l'écart vaut 16,6px, ce
  qui est large), rempli **`#E0FE75`**, à 62% de la largeur du squircle, centré.

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect x="100" y="100" width="824" height="824" rx="185.4" ry="185.4" fill="#0A0A0A"/>
  <rect x="102" y="102" width="820" height="820" rx="183.4" ry="183.4"
        fill="none" stroke="#F7F8F3" stroke-opacity="0.14" stroke-width="4"/>
  <path fill="#E0FE75" d="M256.5 520.3H611.5L474.9 653.6H256.5V520.3Z"/>
  <path fill="#E0FE75" d="M412.5 503.7L549.1 370.4H767.5V503.7H412.5Z"/>
</svg>
```

**Fond noir avec mark lime, et non l'inverse.** Les deux sont légaux, le lime
étant un aplat dans les deux cas. Le noir gagne parce qu'il correspond au seul
autre endroit où l'utilisateur voit la marque, la bulle, et parce que la posture
du produit est un démon silencieux tant qu'on n'appuie pas. Une tuile lime
saturée qui crie depuis le Dock dirait le contraire. La variante inverse existe
quand même, pour le README et les visuels sociaux, où crier est correct.

Pas de wordmark : à 32pt c'est une bavure.

**Le piège habituel.** À 64px l'écart du mark vrai vaut 1,04px, donc réduire la
source 1024 produit la même dalle grise que la menu bar évite. Donc :

- **≥ 128px** : rendu depuis `plume-icon.svg`, vraies proportions.
- **≤ 64px** : rendu depuis `plume-icon-small.svg`, la géométrie à écart ouvert
  du glyphe menu bar, mise à l'échelle.

C'est le détail qui se rate et qui fait qu'une icône est nette dans le Finder et
bouillie dans le Dock en petite taille.

### Où vivent les sources

```
Design/icon/
  plume-icon.svg          # source 1024
  plume-icon-small.svg    # coupe à écart ouvert, pilote les tailles <= 64
  plume-icon-lime.svg     # inverse, README et marketing
  plume.icns              # commité
scripts/make-icns.sh      # rsvg-convert + iconutil
```

`Design/` est à côté de `Sources/`, **pas dedans** : ce sont des entrées de
build, pas des ressources d'exécution, et les mettre sous la cible traînerait un
bundle de ressources dans un binaire qui n'en a délibérément jamais eu.

**Le `.icns` est commité.** Le repo part en open source : un contributeur sur un
checkout propre ne doit pas avoir besoin de `librsvg` pour obtenir une app avec
une icône. Le script existe pour régénérer quand la source change, pas à chaque
build.

`iconutil` et `sips` sont présents sur la machine. Note : macOS 26 a un format
`.icon` en couches (Icon Composer), sur lequel ce design se mapperait proprement
(couche fond plate, couche mark vectorielle). Non vérifié, et `.icns` reste
valide et reste le seul chemin scriptable sans projet Xcode.

## La fenêtre, et ce que le lime y fait

**Trois aplats, zéro premier plan.**

1. **Les puces de sidebar.** `Section.tint` rend `.orange` pour Home et
   `.purple` pour History, arbitraires. Les deux passent en `Style.lime`, et le
   glyphe de `SidebarIcon` passe de `.white` à `Style.onLime`. On **garde** la
   distinction teinté / non teinté : le commentaire existant a raison, elle
   signifie « les lignes teintées montrent quelque chose, les autres changent
   quelque chose », et les puces colorées sont l'idiome natif de Réglages depuis
   Ventura. Deux teintes arbitraires meurent, la distinction survit, et le lime
   devient identique en clair et en sombre.
2. **Le marqueur « recommandé »** (`ModelsSection.swift:94`), aujourd'hui une
   `star.fill` lime en premier plan, donc **invisible en apparence claire à
   1,13:1**. L'étoile devient le mot : `Text("Recommended")` en
   `Text.caption .semibold`, en `Style.onLime`, sur une `Capsule().fill(lime)`.
   Lisible dans les deux apparences, et ça dit ce que ça veut dire.
3. C'est tout.

Les trois autres usages de l'accent passent au sémantique :

| site | aujourd'hui | nouveau | pourquoi |
|---|---|---|---|
| `ModelsSection.swift:133` | « Active » en accent | `.primary` + `.semibold` | C'est un **statut**, et le lime ne porte pas de statut. La graisse le porte |
| `HistorySection.swift:108` | `lock.fill` en accent | `.secondary` | Un glyphe de réassurance, pas un accent |
| `HistorySection.swift:161` | « Copied » en accent | `.secondary` | Retour transitoire, parti en une seconde |

Les boutons restent teintés par le système. `.borderedProminent` avec
`.tint(lime)` laisserait SwiftUI choisir la couleur du label, qui serait blanc
sur lime à 1,13:1. Aucun bouton de cette fenêtre ne justifie de passer outre :
« Check again » n'est pas un call to action.

### Le vert/orange/rouge du docteur reste

Et c'est la marque qui le décide : le lime étant explicitement interdit de
sévérité, la sévérité a besoin de ses propres couleurs, et vert/ambre/rouge est
la convention universelle. Deux raisons de plus que ce n'est pas un compromis :

- `.green` / `.orange` / `.red` en SwiftUI sont les couleurs **dynamiques** du
  système. Elles s'adaptent déjà à l'apparence et au réglage Augmenter le
  contraste. Substituer les `sev-*` de SprintMob graverait des valeurs calées
  pour un fond `#0A0A0A` dans une fenêtre qui peut être blanche, et
  `sev-medium` `#8FA6C4` est un bleu-gris qui ne se lit « avertissement » pour
  personne.
- `CheckRow` associe déjà un symbole SF distinct à chaque couleur
  (`checkmark.circle.fill` / `exclamationmark.triangle.fill` /
  `xmark.circle.fill`), donc l'information n'est pas portée par la couleur
  seule. C'est l'argument d'accessibilité pour **garder** les teintes plutôt que
  les remplacer.

La règle à écrire dans le code : **la couleur de sévérité suit le modèle
d'apparence de la surface.** Sémantique dans la fenêtre qui suit l'apparence,
`Dark.critical` sur la bulle toujours sombre.

### Pas de chrome de marque dans la sidebar

Un mark et un wordmark en haut d'une sidebar macOS est une habitude web.
L'icône du Dock est déjà visible dès que cette fenêtre est ouverte, la politique
`.regular` le garantit.

## Le panneau de repli

Conteneur : `RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)`
rempli `Dark.bg`, **plus le même filet 1pt `Dark.line` que la bulle**. La
cohérence entre les deux surfaces flottantes est le but : ce sont le même objet
à deux tailles.

Boîte de transcript : fond `Dark.elev2` (`#181818`) avec une bordure
`Dark.lineSoft`, en remplacement de `Color.white.opacity(0.08)`. `#181818` sur
`#0A0A0A` est un palier visible, et le modèle d'élévation de la marque sépare
l'aplat du filet : `lineSoft` est un token de filet qui servait d'aplat.

Bouton : `Capsule().fill(lime)` avec le label en `onLime`. C'est la construction
de CTA du site, inchangée.

**Un seul élément lime par surface.** Le glyphe `text.cursor` d'en-tête passe de
l'accent à `Dark.ink45` (5,1:1, confortablement lisible). Le panneau fait
420 × 152 ; un glyphe lime en haut à gauche plus une pastille lime en bas à
droite dessine une diagonale qui tire l'œil hors du transcript, qui est le
contenu. Le lime apparaît une fois, sur le bouton, et le bouton devient
impossible à rater.

Hauteur 148 → 152, la marge verticale passant de 14 à 16. Ce nombre est estimé
depuis la pile ; à vérifier contre la mise en page construite, puisque le
panneau est de taille fixe et qu'un rognage est pire qu'un peu de mou.

### Un bug adjacent, à corriger dans la même passe

`positionAtBottomCenter` utilise `NSScreen.main`, alors que la bulle utilise
délibérément l'écran sous le pointeur, avec un commentaire expliquant que
`NSScreen.main` n'est pas fiable pour un agent d'arrière-plan. **Le panneau peut
donc apparaître sur un autre écran que la bulle qui vient de s'afficher.** On
réutilise la logique de la bulle.

## La copie

**Il y a cinq tirets cadratins dans les chaînes visibles aujourd'hui.** Tous les
cinq disparaissent.

Deux corrections dépassent le style et sont des bugs :

- Une remédiation du docteur dit « run parrot and hold **Fn** once », alors que
  la fonction **reçoit déjà** la touche choisie en paramètre. C'est faux pour
  quiconque a changé de raccourci.
- Deux remédiations disent d'activer la permission « for your terminal ». Avec
  un bundle `.app` c'est devenu faux, et dans le bon sens : c'est plume qu'on
  active. `Setup.swift:19` dit la même chose et devient vrai au lieu de faux.

Le panneau de repli énonce un problème en titre et enterre le résultat dans une
note de bas :

| aujourd'hui | nouveau |
|---|---|
| « No text field selected » | « No text field was focused » |
| « Copied — press ⌘V where you want it. » | « The text is on the clipboard. Press ⌘V where you want it. » |

Une seule chaîne neuve, celle de la bulle : **« Dictation failed »**.

Les chaînes qui restent telles quelles sont nombreuses et c'est normal : « Hold
to dictate, release to insert. », « Always on », les deux aides d'injection,
« Same as System », les cinq en-têtes de colonne des modèles. Elles sont déjà
exactement dans la voix. Les flèches `→` restent aussi : c'est un chemin de
navigation littéral, pas un tiret.

## Séquencement interne

1. `Style.swift` réécrit. Rien ne compile tant que les 9 sites
   `Style.accent` / `Style.background` ne sont pas mis à jour, donc 1 et 2 sont
   un seul commit.
2. Les 9 sites : 4 passent au sémantique, 2 deviennent des pastilles lime, 3
   passent aux `Dark.*`.
3. Balayage des ~45 littéraux de police et ~60 de marge. Mécanique, aucun choix
   restant.
4. `RecordingOverlay.swift` : la bulle, l'état `failed`, la correction de
   `hide()`, plus `Parrot.swift:318-323`.
5. `TranscriptFallbackPopover.swift` : restyle et correction `NSScreen.main`.
6. `MenuBarController.swift` : `markSVG`.
7. `Design/icon/` + `scripts/make-icns.sh` + `Info.plist`.
8. Balayage de la copie. Indépendant de 1 à 7, peut passer en premier si un
   gain visible rapide est voulu.

Les étapes 1 à 3 et 8 n'ont aucun risque comportemental. L'étape 4 est la seule
qui demande un vrai regard sur un Mac, et spécifiquement au-dessus d'un terminal
noir (le filet) et en 1x sur un écran non-Retina (les barres de 3pt, le glyphe
16pt).
