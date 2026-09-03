# Une fenêtre de réglages, calquée sur Superwhisper, sans feature nouvelle

Status: ready-for-human

Deuxième code écrit par le fork, et non un merge. Rouvre deux non-goals de
`docs/architecture.md` — pas de fenêtre de réglages, pas d'historique — actés dans
[ADR-0007](../../docs/adr/0007-a-settings-window-and-a-session-history.md).

Point de départ : `main` @ `e3fcc98` plus le travail pasteboard non commité.

## La demande

Reproduire l'interface desktop de Superwhisper (sidebar + panneau de détail),
**avec ce que parrot a déjà**. L'inventaire du code donne la correspondance :

| Section Superwhisper | Ce que parrot a derrière |
|---|---|
| Home | ✅ les 5 checks de `DoctorReport`, l'état de dictée, le modèle actif |
| Modes | ❌ rien — aucun concept de profil ou de contexte |
| Vocabulary | ❌ rien — `DictationExamples` est un prompt Whisper, pas un remplacement |
| Configuration | ✅ hotkey (9 valeurs), injection (2), overlay, launch agent |
| Sound | ✅ `InputDeviceStore`, `OutputMuteController` |
| Models library | ✅ `ModelRegistry` (5 modèles) + `ModelWeights.isInstalled`, code mort |
| History | ❌ rien — aucun transcript ne survit à sa dictée |

Modes et Vocabulary sont abandonnés : une ligne de sidebar qui ne mène nulle part
est pire que pas de ligne. History est **construit**, en mémoire vive uniquement —
c'est la seule addition de comportement du lot, et l'ADR la défend.

## Ce qui a été fait

| Fichier | Apport |
|---|---|
| `UI/DaemonState.swift` | nouveau — l'état vivant et les choix retenus, lus par les deux surfaces |
| `UI/Style.swift` | nouveau — les deux couleurs, dédupliquées de l'overlay et du popover |
| `UI/Settings/` | nouveau — 8 fichiers : coquille `NSWindow`, sidebar, contrôles partagés, 5 sections |
| `Transcription/TranscriptHistory.swift` | nouveau — tampon plafonné à 200, en RAM |
| `Models/ModelCatalog.swift` | nouveau — la règle de statut des modèles, pure |
| `SettingsStore.swift` | `overlay`, `muteOutput`, `sessionHistory` |
| `UI/MenuBarController.swift` | perd 6 setters et sa copie de l'état ; gagne `Settings…` ⌘, |
| `Parrot.swift` | câblage `DaemonState`, alimentation de l'historique, overlay/mute à chaud |
| `Install.swift` | opérations du launch agent extraites en statics appelables depuis l'UI |
| `Doctor.swift` | `checkLaunchAgentArgs` couvre les deux nouveaux flags |

## Décisions

### La menu bar ne pouvait plus détenir l'état

C'est le point dur, et il est structurel. `MenuBarController` détenait `hotkey` et
`injectMode` en `private(set)`, et `Parrot.swift` lisait `menuBar.injectMode` à
chaque injection. Deux surfaces ne peuvent pas toutes deux le détenir : la fenêtre
aurait dû demander à la menu bar quel est le mode d'injection.

`DaemonState` le prend, et la menu bar devient un lecteur comme la fenêtre. Elle
n'a besoin d'aucun abonnement : `menuWillOpen` reconstruisait déjà ses listes à
chaque ouverture, et un menu fermé n'affiche rien. Les six setters disparaissent
avec la duplication dont ses propres commentaires s'excusaient.

### Deux flags deviennent des choix retenus

`--no-overlay` et `--mute-output` n'existaient qu'en ligne de commande. Un
interrupteur qui s'oublie au redémarrage est cassé, donc `overlay` et `muteOutput`
rejoignent `SettingsStore` — exactement le geste qu'ADR-0004 avait fait pour
`--hotkey` et `--inject-mode`. Les deux flags ne portent que dans un sens : il n'y
a pas d'`--overlay`, donc un flag peut éteindre la pastille pour un lancement mais
jamais la rallumer par-dessus un « off » retenu.

Conséquence imposée par ADR-0004 : `parrot install` ne les grave pas, et
`parrot doctor` avertit s'il les trouve dans un agent édité à la main.

### `.regular` tant que la fenêtre est ouverte

`.accessory` ne donne aucune barre de menus, et une fenêtre sans barre de menus n'a
ni ⌘C, ni ⌘V, ni ⌘W — touches mortes dans le champ de recherche de History. La
bascule en `.regular` à l'ouverture, retour en `.accessory` à la fermeture. Il n'y
a pas de bundle `.app`, donc pas de MainMenu.nib : le menu principal est construit
en code.

L'icône Dock qui apparaît avec est le signal honnête que parrot a quelque chose à
l'écran. Elle repart avec la fenêtre.

### L'historique tient en RAM, et c'est plus contenu que ce qui existe déjà

[ADR-0006](../../docs/adr/0006-transcript-always-on-the-pasteboard.md) met **chaque**
transcript sur le presse-papiers, où il reste indéfiniment, lisible par tout
processus de la machine, et écrit sur disque par le gestionnaire de presse-papiers
que l'utilisateur fait tourner. Face à ça, un tableau local au processus qui meurt
avec lui est le plus contenu des deux. La promesse du README — parrot n'écrit aucun
transcript sur disque — est aussi vraie après qu'avant.

### Ce qui n'a délibérément pas été fait

- **Pas de sous-commande `parrot settings`.** Un second processus ne peut pas lever
  la fenêtre du démon en cours sans un canal IPC qui n'existerait que pour ça.
- **Pas de sélecteur de thème.** La fenêtre suit l'apparence système via les
  couleurs sémantiques ; un réglage de thème serait une feature nouvelle.
- **Pas de taille réelle sur disque dans la table des modèles.**
  `ModelWeights.bytes(at:)` parcourt le répertoire — des milliers de fichiers, sur
  le thread principal, à chaque rendu pendant un téléchargement. La taille du
  registre est honnête et gratuite.
- **Pas de vumètre dans Sound.** `AudioCapture.onLevel` existe, mais l'afficher
  demanderait d'ouvrir le micro hors dictée. C'est un comportement nouveau, et le
  mauvais dans une app de dictée.
- **Pas de bouton Supprimer dans les modèles.** La purge est automatique et garde
  l'actif plus le précédent ; la note de pied de table l'explique.

## Vérification

`swift build -c release` et `swift test` passent — 66 tests, dont 20 neufs :
`TranscriptHistoryTests` (plafond, ordre, groupage par jour avec `Calendar`/`now`
injectés, filtre accent-insensible), `ModelCatalogTests` (les six statuts, dont
« actif pendant qu'un autre télécharge »), plus les extensions de
`SettingsStoreTests` et `DoctorLaunchAgentTests`. Aucune UI n'est testée,
conformément au reste du repo.

**Reste à faire par l'utilisateur : la validation sur appareil.** Rien de la
fenêtre ne peut être exercé sans un démon signé et lancé. Protocole dans
`issues/06-validation-sur-appareil.md`.
