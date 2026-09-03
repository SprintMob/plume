# 01 — Réveiller l'arbre d'accessibilité Chromium/Electron

Status: ready-for-human

La sonde de focus ne voit aucun champ dans une page web parce que Chromium et
Electron n'exposent leur arbre d'accessibilité qu'à une technologie d'assistance
déclarée. Poser `AXEnhancedUserInterface` (Chromium) et `AXManualAccessibility`
(Electron) sur l'app focalisée au début de chaque dictée.

Implémenté. Voir `spec.md` et
[ADR-0005](../../../docs/adr/0005-wake-chromium-accessibility.md).

Reste à faire par l'utilisateur : la validation sur appareil — `swift build` et
`swift test` passent, mais aucun des chemins AX ne peut être exercé sans un
démon signé, l'autorisation Accessibilité, et une vraie dictée. Protocole dans
le plan, section Vérification.

## Comments

- 2026-08-25 : `--debug-focus` ajouté pour que ce diagnostic n'ait pas à être
  refait de zéro la prochaine fois. Il imprime code d'erreur AX, bundle id, rôle,
  sous-rôle, description de rôle, settabilité et l'échelon qui a tranché.
