# 06 — Validation sur appareil

Status: ready-for-human

`swift build -c release` et `swift test` passent, mais **rien de la fenêtre ne peut
être exercé sans un démon signé et lancé**. À faire par l'utilisateur.

```sh
./scripts/install-local.sh
```

⚠️ À lancer par l'utilisateur, jamais par un agent : l'étape `codesign` demande un
accès au trousseau.

Puis, dans l'ordre — le point 1 est le risque à lever en premier :

1. **Menu bar → Settings…** La fenêtre s'ouvre et l'icône Dock apparaît. C'est la
   bascule `.accessory` → `.regular` sous launchd : le démon tourne en LaunchAgent
   avec `ProcessType: Interactive`, et le changement de politique devrait passer
   dans une session GUI — à confirmer.
2. ⌘C / ⌘V dans le champ de recherche de History.
3. ⌘W : la fenêtre se ferme, l'icône Dock disparaît.
4. Fenêtre ouverte, maintenir `fn` et dicter : le texte s'insère normalement.
5. Configuration → *Dictation overlay: None* : plus de pastille pendant la dictée.
6. `launchctl kickstart -k gui/$(id -u)/com.digimata.parrot` : le réglage a survécu.
7. Models → cliquer un modèle non installé : progression visible dans la fenêtre
   **et** dans la menu bar ; le statut passe à `Downloaded` puis `Active`.
8. Sound → changer de micro : la dictée suivante utilise le nouveau.
9. Dicter 3 fois : 3 cartes dans History ; fermer/rouvrir la fenêtre, elles sont
   toujours là ; relancer le démon, elles ont disparu.
10. Configuration → *Keep session history: off* : plus rien ne s'ajoute.
11. `parrot doctor` en terminal : inchangé.
12. Basculer l'apparence système clair ↔ sombre, fenêtre ouverte.

## Comments

- Les points 1 et 12 sont les deux seuls qui ne peuvent pas être devinés depuis le
  code. Le reste suit les tests.
