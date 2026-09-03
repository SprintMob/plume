# Le transcript part toujours au presse-papier

Status: ready-for-human

Demande utilisateur directe : « le transcript doit partir directement dans le
presse-papier quoi qu'il arrive ». Un gestionnaire de presse-papiers est en
place, donc écraser ce qui avait été copié est explicitement acceptable.

Point de départ : `main` @ `e3fcc98`, avec le travail focus-detection et
hotkey-persistence encore non commité par-dessus.

## Symptôme

Le transcript n'atteignait le presse-papier que sur le chemin de repli. Trois
façons de perdre une dictée, toutes silencieuses :

- la sonde de focus passe jusqu'à 0,6 s dans l'API d'accessibilité, deux fois,
  sur une app qui peut ne jamais répondre — et tout ce qui suit attend ;
- une app qui ignore les frappes unicode synthétisées avale une livraison
  `type-unicode` en entier ;
- le collage est asynchrone chez le destinataire, donc une app qui lit le
  presse-papier après le délai de 0,25 s récupérait l'ancien contenu.

`inject` ne renvoie rien : aucune de ces trois issues n'était détectable.

## Ce qui a été fait

| Fichier | Apport |
|---|---|
| `Input/TextInjector.swift` | réécrit — `copyToPasteboard` avant tout, coutures `pasteboard`/`post`, suppression du snapshot/restauration |
| `Parrot.swift` | la copie remonte dans le `MainActor.run` qui précède la sonde ; texte d'aide `--inject-mode` corrigé |
| `UI/TranscriptFallbackPopover.swift` | commentaire seul — le panneau annonce, il ne copie plus |
| `Tests/parrotTests/TextInjectorTests.swift` | nouveau — 9 tests, premiers tests du type |
| `docs/adr/0006-...md` | nouveau — la décision et ce qu'elle coûte |
| `CONTEXT.md`, `docs/architecture.md`, `README.md` | le vocabulaire et les trois docs qui promettaient l'inverse |

Supprimés : `pasteSettleDelay`, `savedContents`, `restoreGeneration`,
`pasteInject`, `snapshot(_:)`, `restore(_:to:)`, `unicodeInject`. Le fichier
passe de 166 à 132 lignes malgré deux nouveautés (`KeyStroke`, `chunks(of:)`).

## Décisions

### Comportement fixe, pas de réglage

Ni toggle menu bar, ni clé `SettingsStore`, ni flag CLI, alors qu'
[ADR-0004](../../docs/adr/0004-settings-in-userdefaults.md) en donne le patron.
Un transcript que personne ne peut atteindre est un bug dans toutes les
configurations : il n'y a pas de deuxième bonne réponse à offrir.

### La copie arrive avant la sonde, pas après

C'est l'ordre qui fait la garantie, et l'ordre est une propriété du pipeline,
pas de `TextInjector`. La copie est donc posée dans le `MainActor.run` qui
existait déjà pour masquer l'overlay — zéro saut d'acteur ajouté. Le garde
`!text.isEmpty` de `copyToPasteboard` devient porteur : c'est lui qui autorise
à copier avant d'avoir vérifié que le texte n'est pas vide.

### Déduplication sans état

`inject` recopie après la copie du daemon, ce qui ferait deux entrées
identiques dans un gestionnaire de presse-papiers. `copyToPasteboard` saute
donc un presse-papier qui contient déjà exactement cette chaîne. Sans état
stocké — pas de `(dernier texte, changeCount)` — ce qui évite des tests
ordre-dépendants et rend le bouton « Copy again » du panneau utile : il
réécrit exactement quand autre chose a pris le presse-papier.

### Champ mot de passe : on copie quand même

C'était déjà le cas, mais par accident du branchement. C'est désormais une
décision, tracée dans ADR-0006 : l'injection reste refusée à chaque barreau de
la marche, le presse-papier ne l'a jamais été.

## Vérification

Swift 6.3 / Xcode 26.4, arm64. Pas de job de test en CI.

- `swift build` : OK · `swift build -c release` : OK
- `swift test` : **45/45**, dont 9 neufs
- `rg 'savedContents|restoreGeneration|pasteSettleDelay'` sur `Sources/` : rien

Les tests remplacent les deux coutures — un `NSPasteboard(name:)` privé et un
`post:` enregistreur. La seconde n'est pas du confort : qui lance `swift test`
sur ce repo a accordé l'accessibilité à son terminal, donc un `inject` non
couturé posterait un vrai ⌘V dans la fenêtre au premier plan.

## Non exercés — à faire par l'utilisateur

Les chemins AX exigent un daemon signé, l'autorisation Accessibilité et une
vraie dictée. `swift test` ne poste jamais de frappe.

1. `./scripts/install-local.sh` (l'étape `codesign` demande le trousseau)
2. TextEdit → le texte s'insère **et** reste sur le presse-papier au-delà de
   0,25 s
3. Finder au premier plan → panneau de repli, ⌘V fonctionne
4. Champ mot de passe → pas d'injection, panneau affiché, transcript copié
5. `type-unicode` (menu bar → Injection) → frappé **et** copié
6. Le gestionnaire montre **une** entrée par dictée, pas deux

## Ce que ça ne règle pas

- Les paires de substitution restent coupées à la frontière des 20 unités
  UTF-16, exactement comme avant. `chunks(of:)` renvoie `[[UniChar]]` et non
  `[String]` précisément pour préserver ce comportement plutôt que de le
  changer en silence.
- `inject` ne renvoie toujours rien. La garantie presse-papier est le filet,
  pas un accusé de réception.
