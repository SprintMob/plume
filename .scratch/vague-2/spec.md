# Vague 2 — le cluster hotkey, la pile modèles, et deux features autonomes

Status: ready-for-human

Deuxième passe de merge du fork. Six PRs, environ 1 900 lignes reprises de cinq
auteurs. Contrairement à la vague 1, cette passe n'est pas atomique : elle
tranche l'arbitrage du cluster hotkey ([ADR-0003](../../docs/adr/0003-hotkey-cluster-base.md)),
change une dépendance, et amène le premier test target du dépôt.

Point de départ : `main` @ `85335fc`, c'est-à-dire la vague 1 complète.

## Ce qui a été fusionné, dans l'ordre appliqué

L'ordre suit la surface de conflit, pas l'intérêt des correctifs — le principe
d'[ADR-0002](../../docs/adr/0002-merge-upstream-prs-in-waves.md) appliqué à la
lettre, ce qui **inverse ici les vagues 2 et 3**.

| # | Apport | Auteur | Vague au tableau |
|---|--------|--------|------------------|
| 1 | #21 switch de modèle en menu bar, turbo compressé | andredezzy | 3 |
| 2 | #23 exemples de dictée par langue, langue épinglée | andredezzy | 3 |
| 3 | #10 `--hotkey`, filtre keycode | tomiiide | 2 |
| 4 | #4 neuf modificateurs, injection presse-papier, overlay | Entrepenulian | 2 |
| 5 | #5 dictée verrouillée, mute sortie, test target | augiefra | 4 |
| 6 | #16 popover de repli | justinhnaylor | 4 |

Deux raisons à cet ordre. `MenuBarController` est réécrit à +100 lignes par
#21/#23 et seulement retouché de deux lignes par #4 et #5 : poser la réécriture
d'abord coûte deux greffes triviales au lieu d'un gros rebase. Et #23 change une
dépendance — la passer en deuxième fait échouer tôt ce qui doit échouer, avant
d'avoir posé quatre autres merges.

Trois PRs n'étaient pas demandées mais sont entrées :

- **#21** n'est pas séparable de #23. `upstream/pr/23` est une pile de 13
  commits : le correctif de #12 (déjà fusionné), les 7 de #21, puis les 6 de #23.
  Les commits propres de #23 dépendent de `ModelWeights` et `ModelStore`, tous
  deux introduits par #21 — les isoler voudrait dire réécrire, pas cherry-picker.
  Fusionnée en deux temps quand même, avec un build vérifié entre les deux, pour
  que le changement de dépendance ait son propre commit vérifiable.
- **#10** est la base sur laquelle #4 est greffée, pas un doublon. Voir ADR-0003.

## Décisions

### Base du cluster hotkey : #4, greffée sur #10

Tranchée dans [ADR-0003](../../docs/adr/0003-hotkey-cluster-base.md). En résumé :
l'enum `Hotkey` de #4 est un sur-ensemble strict de #10 (neuf modificateurs
filtrés par keycode contre deux), donc #4 est la base ; mais `init(mask:keycode:debug:)`
de #10, mergée en premier, reste l'init désigné et #4 y délègue. #7 est
supersédée, #18 se réduit à son correctif B4 à isoler.

### Changement de dépendance de #23

`argmaxinc/WhisperKit` (`from: 0.9.0`) devient `argmaxinc/argmax-oss-swift`
épinglé sur `97d09fd`, et FluidAudio arrive avec #21 pour Parakeet.
`Package.resolved` perd 65 lignes.

L'épingle n'est pas cosmétique : avant `argmaxinc/argmax-oss-swift#514`, toute
transcription passant des `promptTokens` revenait vide, donc non épinglée, #23
ne fait silencieusement rien. À repasser sur une contrainte de version dès
qu'une release porte le correctif. La révision a été vérifiée résolvable et le
binaire construit et lancé contre elle avant de committer.

### Deux régressions réintroduites par un auto-merge propre

C'est le point à retenir de cette passe : **les conflits n'étaient pas là où
était le risque.**

La restructuration de `run()` par #5 déplace le corps de la boucle
d'enregistrement en bloc vers `beginRecording()` / `finishRecording()`. #5 est
antérieure au commit privacy de #9, donc git a déplacé sa version du bloc — sans
conflit — et a silencieusement défait deux correctifs de la vague 1 :

- le transcript intégral repartait sur stderr sans condition, au lieu de la
  ligne longueur-seule avec `--echo-transcripts` en opt-in ;
- `--dump-wav` repartait vers `/tmp/parrot-last.wav`, lisible par tous, au lieu
  du fichier `0600` dans `~/Library/Caches/parrot`.

Le même déplacement avait aussi perdu le `mode: injectMode` de #4. Les trois ont
été restaurés à la main. Les cinq conflits déclarés de #5, eux, étaient tous
bénins.

### Conflit #4 / #5 sur l'overlay

Les deux corrigent la même course — un `hide()` en vol qui range une pill qu'un
nouvel enregistrement vient de rouvrir — #4 avec un compteur de génération, #5
avec un `DispatchWorkItem` annulable. Gardé le compteur, pris de #5 seulement
l'état `.locked` et sa pill cadenas + waveform.

### Conflit #5 / #17 sur le tap

`reEnable()` de #17 et `handleTapInterruption()` de #5 sont deux moitiés du même
correctif. Fondues en une : `reEnable()` réactive le tap, remet `isPressed` à
faux et émet `.interrupted`. La remise à zéro compte — une désactivation avale le
relâchement qui aurait terminé l'enregistrement en cours.

### Les chaînes « fn » codées en dur

#5 nomme `fn` dans quatre chaînes visibles par l'utilisateur, écrites avant que
`--hotkey` n'existe. Toutes lisent maintenant le modificateur configuré, sinon
`--hotkey right-option` demande de taper fn pour arrêter.

## Ce que la vague 2 ne règle pas

Les six angles morts de la vague 1 restent tous ouverts — migration des modèles
existants, warmup non fatal (B2), `ThrottleInterval`, rotation du log,
`--version`, état réel dans `models list`. Aucune des six PRs n'y touche.

Deux nouveaux points, apportés par cette passe :

1. **Le hotkey n'est pas persistable hors launch agent.** `parrot install` grave
   `--hotkey` et `--inject-mode` dans le plist ; lancé à la main, tout revient au
   défaut. Il n'y a pas de fichier de config — c'est ce que #7 proposait.
2. **Le turbo compressé n'est pas une migration.** #21 l'enregistre et la purge
   ne tourne qu'après un switch réussi : qui détient déjà le turbo non compressé
   garde ses 1 620 Mo tant qu'il ne change pas de modèle.

## Ce qui bloque la suite

**#26 (willmather95), 4 256 lignes, 26 fichiers, en conflit avec 9 PRs.**
Toujours ouverte, et trois des six merges de cette passe (#4, #5, #23) sont dans
sa liste de conflits — la décision est donc plus chère qu'avant, délibérément et
en connaissance de cause. ADR-0002 continue de dire qu'elle devait être tranchée
immédiatement après la vague 1 ; ce n'est pas ce qui s'est passé.

## Vérification

Swift 6.3 / Xcode 26.4, arm64.

- `swift build -c release` : OK après chacun des six merges
- `swift test` : 5/5 sur `FnDictationGesture` — premier test target du dépôt
- `parrot run --help` : `--hotkey` (9 valeurs, validées), `--inject-mode`
  (`paste` par défaut), `--mute-output`
- `parrot install --help` : `--hotkey` et `--inject-mode` en plus de
  `--log-file` / `--purge-legacy-logs`
- `parrot run --hotkey nope` : rejeté avec la liste des valeurs valides
- `parrot models list` : ids complets, turbo compressé (632 Mo) et Parakeet
  présents, Parakeet recommandé
- `parrot doctor` : les 4 contrôles de la vague 1 passent toujours
- `--dump-wav` pointe bien sur `~/Library/Caches/parrot/last-capture.wav`
- `bash -n` sur les deux scripts

Non exercés, délibérément : tout ce qui demande le daemon vivant — la dictée
elle-même dans les trois modes d'injection, le double-tap de verrouillage, le
popover de repli, `--mute-output`, et le switch de modèle en menu bar. Ils
demandent l'Accessibilité et jusqu'à 1,6 Go de téléchargement. Aucun n'a été
observé fonctionner ; seuls le build, les tests unitaires et la surface CLI le
sont.
