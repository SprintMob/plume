# 02 — `--no-overlay` et `--mute-output` deviennent des choix retenus

Status: ready-for-human

Les deux n'existaient qu'en flag. Un interrupteur de fenêtre qui s'oublie au
redémarrage est cassé, donc `overlay` et `muteOutput` rejoignent `SettingsStore`,
avec `sessionHistory` qui n'a jamais eu de flag.

Précédence : le flag ne porte que dans un sens (il n'y a pas d'`--overlay`), sinon
le choix retenu, sinon le défaut — overlay allumé, mute éteint, historique gardé.
Lus via `object(forKey:)` et non `bool(forKey:)`, sans quoi « éteint » et « jamais
choisi » seraient indistinguables.

Les deux réglages étaient consommés à la construction : l'overlay et le contrôleur
de mute sont désormais toujours construits, et conditionnés à l'appel, pour que la
fenêtre puisse les basculer entre deux dictées.

`Doctor.checkLaunchAgentArgs` couvre les deux nouveaux flags, comme ADR-0004
l'impose.

Implémenté. Voir `spec.md`.
