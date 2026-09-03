# 01 — Sortir l'état vivant du MenuBarController

Status: ready-for-human

`MenuBarController` détenait `hotkey` et `injectMode`, et `Parrot.swift` lisait
`menuBar.injectMode` à chaque injection. Une deuxième surface ne peut pas écrire
ces valeurs sans en dépendre.

`DaemonState` les prend, avec l'état de dictée et l'état de switch de modèle. La
menu bar devient un lecteur : `menuWillOpen` rafraîchit ses libellés depuis l'état,
et les six setters (`setRecording`, `setTranscribing`, `setLockedRecording`,
`setModel`, `setSwitchProgress`, `setModelFailed`) disparaissent.

Refactor à comportement constant : à la fin de ce ticket la menu bar se comporte à
l'identique et rien n'a bougé à l'écran.

Implémenté. Voir `spec.md` et
[ADR-0007](../../../docs/adr/0007-a-settings-window-and-a-session-history.md).
