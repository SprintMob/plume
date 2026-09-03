# 04 — Les cinq sections

Status: ready-for-human

`SettingsRootView` (sidebar + routage) et `SettingsControls` (page, groupe, ligne,
key cap) donnent la forme ; cinq fichiers la remplissent.

- **Home** — l'état, le modèle, le hold-to-talk en key caps, et les cinq
  `DoctorReport.Check` avec leur remédiation. Les checks tournent hors du thread
  principal : deux d'entre eux lancent `ps` et `defaults`. Le seul bouton de
  remédiation que parrot peut exécuter lui-même est la purge des logs legacy.
- **Configuration** — overlay `Classic`/`None`, les 9 modificateurs, launch at
  login, injection, garder l'historique. Le double-tap de verrouillage est affiché
  **en lecture seule** : le geste existe, le réglage non.
- **Sound** — micro et audio système pendant la dictée. Deux lignes, et c'est tout
  ce qu'il y a.
- **Models** — les 5 modèles en table, avec le statut calculé par `ModelCatalog`.
  Réveille `ModelWeights.isInstalled`, qui n'avait aucun appelant. Les exemples de
  dictée sont en pied de section, avec la réserve « Whisper seulement ».
- **History** — recherche, cartes groupées par jour, clic pour copier, bandeau
  « en mémoire uniquement » en tête.

La menu bar renomme « Push-to-talk key » en « Hold-to-talk key » : le glossaire
proscrit la première orthographe depuis que `CONTEXT.md` existe.

Implémenté. Voir `spec.md`.
