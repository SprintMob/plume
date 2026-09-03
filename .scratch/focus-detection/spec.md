# Détection du champ focalisé cassée dans les navigateurs

## Symptôme

Rapporté le 2026-08-25 : même avec un champ texte sélectionné, parrot affiche
« No text field selected » et la bulle de repli au lieu d'insérer le transcript.
Observé dans le navigateur (Arc, Chrome), de façon intermittente en apparence.

## Cause racine

`FocusedTextTarget` lit `kAXFocusedUIElementAttribute` sur l'élément système.
Les applications Chromium (Chrome, Arc, Brave, Edge) et Electron (Slack, VS Code,
Notion) **laissent leur arbre d'accessibilité éteint** tant qu'aucune technologie
d'assistance ne s'annonce. Un `<input>` focalisé est donc invisible à l'API AX.
Chromium surveille `AXEnhancedUserInterface`, Electron `AXManualAccessibility` ;
parrot ne posait ni l'un ni l'autre.

L'intermittence n'en était pas une : les champs *natifs* du navigateur (barre
d'adresse) restent exposés en permanence et fonctionnaient, seuls les champs de
page web échouaient.

Vérification sans code : activer VoiceOver (⌘F5) — qui pose exactement cet
attribut — rend la dictée fonctionnelle dans une page web.

## Décision

[ADR-0005](../../docs/adr/0005-wake-chromium-accessibility.md) : parrot pose les
deux attributs sur l'app focalisée au début de chaque dictée, avec
`--no-wake-accessibility` comme échappatoire.

## Périmètre livré

- `AccessibilityOptIn` — le réveil, une fois par pid, pids oubliés à la fermeture
- `FocusedTextTarget` refondu — `FocusRules` pur et testable, `FocusProbe` pour le
  diagnostic, budget de 0,6 s et `AXUIElementSetMessagingTimeout` pour ne plus
  bloquer le main actor, `as!` non gardé remplacé
- une nouvelle tentative après réveil dans `finishRecording`, sauf champ sécurisé
- `--debug-focus`, `--no-wake-accessibility`
- copie automatique dans le presse-papier en repli (demande utilisateur du même
  jour), avec annulation de la restauration différée de `pasteInject`
- `Tests/parrotTests/FocusRulesTests.swift` — 15 tests, la première couverture de
  ce chemin (`.scratch/vague-2/spec.md:146` le notait jamais observé)

## Limite connue

Le dernier échelon de `FocusRules.isEditable` teste
`roleDescription.contains("text")` sur une chaîne **localisée**. Il passe en
français (« zone de texte ») et en allemand par coïncidence, pas en japonais.
Épinglé par un test plutôt que corrigé : les deux échelons au-dessus (rôle, et
`AXSelectedTextRange` settable) couvrent tout ce qui a été rencontré.
