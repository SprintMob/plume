# Vague 3 — le nœud audio : B4 fermé, le micro se choisit

Status: ready-for-human

Troisième passe de merge du fork. Deux merges, environ 440 lignes reprises de
deux auteurs. Elle ferme B4 — le dernier des cinq défauts du diagnostic du
20 août qui n'avait rien reçu — et ouvre la zone la plus disputée de ce qui
reste : `AudioCapture.swift`, que 5 des 9 PRs encore ouvertes touchaient.

Point de départ : `main` @ `4c2b1c1`, c'est-à-dire la vague 2 complète.

## Ce qui a été fusionné, dans l'ordre appliqué

| # | Apport | Auteur | Vague au tableau |
|---|--------|--------|------------------|
| 1 | #18 (commit 1 seul) correctif B4 : survivre au changement de format audio | vipergsm | 2 |
| 2 | #14 choix du périphérique d'entrée, capture par AUHAL | andredezzy | 3 |

L'ordre est délibéré, et pas seulement parce que le correctif B4 était gratuit
(zéro conflit — aucun des 14 merges précédents n'avait touché
`AudioCapture.swift`, byte-identique à la base amont). Le poser d'abord
**crée** un conflit dans le merge de #14, qui sinon auto-mergeait proprement le
fichier ; la leçon de la vague 2 dit précisément que le risque vit dans les
auto-merges propres, donc forcer git à s'arrêter là où deux réécritures se
croisent est une feature, pas un coût.

Comme #9 en vague 1, #18 n'entre que par son premier commit : son second (la
moitié `--hotkey` / `--language`) est supersédé par #10, #4 et #23 depuis
[ADR-0003](../../docs/adr/0003-hotkey-cluster-base.md). Rien d'autre de #18 ne
doit atterrir — la PR peut être considérée comme traitée.

## Décisions

### B4 est fermé deux fois, la version structurelle gagne

Deux correctifs du même crash sont entrés à une heure d'écart. Celui de #18 :
`installTap(format: nil)` plus un convertisseur paresseux construit sur le
premier buffer réel, mis en cache par format d'entrée. Celui de #14, trois
commits plus loin dans sa propre branche : plus d'`AVAudioEngine` du tout —
capture par une unité AUHAL autonome, reconstruite à chaque enregistrement,
liée au périphérique à son propre taux et rééchantillonnée localement.

Dans l'arbre final, AUHAL gagne : sans `installTap` ni lecture de format avant
démarrage, l'exception Objective-C imprenable de B4 est inatteignable par
construction, pas évitée défensivement. Le correctif de vipergsm reste dans
l'historique, crédité, mécanisme intact sous `464dd20` — c'est ce qu'ADR-0003
demandait d'isoler, et c'est fait.

### La greffe `requestAccess()`

Ce que #14 n'a pas et que #18 apportait : demander l'accès micro dans le chemin
de capture. `parrot run` ne l'a jamais demandé — seuls `setup` et `doctor` le
font — et un daemon non autorisé échouait sur un OSStatus nu. Le garde de #18
(`requestAccess()` + `microphoneNotAuthorized`) est greffé en tête du
`start(device:)` AUHAL. Réserve inchangée : la danse sémaphore existe
maintenant en double avec `Setup.waitForMicrophone()`, à factoriser une fois.

### Le piège de l'auto-merge, deuxième rencontre

#14 patche la closure inline d'événements que #5 a restructurée en
`beginRecording()` / `finishRecording()`. Cette fois git a signalé le conflit
(la restructuration de #5 avait changé les deux côtés), et le côté #14 du hunk
était le monde d'avant-#5 au complet : transcript intégral sur stderr sans
condition, `--dump-wav` vers `/tmp`, injection sans `mode:` ni test de focus.
Jeté en bloc — les trois intentions de la PR tiennent en trois lignes greffées
sur la forme actuelle (`InputDeviceStore()` construit, passé à
`MenuBarController`, résolu dans `capture.start(device:)`), et le diff net de
`Parrot.swift` fait +3/−2.

La revue post-merge du diff complet, zones auto-mergées comprises, a été faite
au lieu d'être promise : echo conditionné à `--echo-transcripts`, wav dans
`~/Library/Caches/parrot`, `inject(text, mode:)` et `FocusedTextTarget`
intacts, aucun résidu de `engineStartFailed` / `converterCreationFailed`,
`Doctor.swift` et `Setup.swift` intouchés.

### Le premier commit de #14 se déclare lui-même invérifié

`6001376` ouvre son message par « UNVERIFIED -- not reproduced locally, do not
upstream as-is ». Il est supersédé trois commits plus loin dans la même branche
par la réécriture AUHAL. La convention de merge du fork (vrais merges, pas de
squash) le garde dans l'historique ; le message de merge le dit pour que
personne ne le prenne pour la version qui compte.

### Menu bar : union sans arbitrage

#14 était resté sur `init(modelID: String)` d'avant-#21. L'init devient
`init(model:hotkeyLabel:devices:)`, le sous-menu Input s'ajoute à côté de
Model, et `menuWillOpen` reconstruit les deux listes — les deux PRs avaient
indépendamment fait passer la classe en `NSMenuDelegate`, ce que la vague 2
avait déjà posé.

## Ce que la vague 3 ne règle pas

Les huit angles morts connus restent tous ouverts — les six du 20 août plus les
deux de la vague 2 (persistance du hotkey, migration du turbo compressé).
Aucun des deux merges n'y touche.

Deux limites propres à cette passe :

1. **Le périphérique est résolu au `start()`, pas suivi en vol.** Des AirPods
   qui se connectent en cours d'enregistrement ne tuent plus le daemon — c'est
   tout l'objet de B4 — mais l'enregistrement en cours reste lié au micro
   résolu au départ ; le suivant suit le nouveau défaut système.
2. **`requestAccess()` en double** avec `Setup.waitForMicrophone()`, dit plus
   haut.

**#22 (remonter un micro baissé) est débloquée** : elle dépendait de #14. C'est
le prochain morceau audio naturel, avec #6 (dictionnaire de corrections) qui
reste le meilleur rapport valeur/risque des restantes.

## Ce qui bloque la suite

**#26, toujours.** La décision était déjà en retard d'une vague ; elle est
maintenant plus chère encore, délibérément et en connaissance de cause : #14
réécrit `AudioCapture.swift`, le cœur de sa refonte, tout en absorbant une
quatrième de ses idées (reconstruire le graphe de capture à chaque
enregistrement, après le repli presse-papier et le refus des champs sécurisés
par #16 et l'injection ciblée en partie par #4). Le plateau penche vers une
fermeture en supersédée — mais ça reste un arbitrage à trancher, pas un fait
accompli.

## Vérification

Swift 6.3 / Xcode 26.4, arm64.

- `swift build` : OK après chacun des deux merges ; `swift build -c release` :
  OK en fin de passe
- `swift test` : 5/5 sur `FnDictationGesture` après chaque merge
- Auteurs préservés : les deux merges sont de vrais merges à deux parents ;
  `git log` montre vipergsm et André "Dezzy" Victor sur les commits repris
- Les greps de la revue post-merge listés plus haut

Non exercés, délibérément : tout ce qui demande le daemon vivant — la dictée
elle-même, le sous-menu Input et le changement de micro, le scénario AirPods de
B4, la demande d'accès micro au premier `start()`. Ils demandent l'Accessibilité
et une session GUI. Seuls le build, les tests unitaires et la revue statique du
diff le sont.
