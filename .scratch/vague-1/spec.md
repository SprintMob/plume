# Vague 1 — les 8 PRs atomiques, plus le commit privacy de #9

Status: ready-for-human

Première vague de merge du fork, telle que définie par
[ADR-0002](../../docs/adr/0002-merge-upstream-prs-in-waves.md) : tout ce qui est
atomique et sans conflit sérieux, pris avant toute décision d'architecture.
Environ 200 lignes reprises de huit auteurs, plus un cherry-pick hors ordre.

Relevé de l'amont au moment du merge : `digimata/parrot` @ `62f8d98`, 25 PRs
ouvertes, toutes `MERGEABLE`.

## Ce qui a été fusionné, dans l'ordre appliqué

L'ordre suit la surface de conflit, pas l'intérêt des correctifs.

| # | Apport | Auteur | Défaut amont |
|---|---|---|---|
| 1 | #12 modèles hors de `~/Documents` | andredezzy | B1 |
| 2 | #19 `models list` ne tronque plus les ids | andredezzy | B5 (moitié) |
| 3 | #13 exit 0 si l'accessibilité manque | andredezzy | B2 (partiel) |
| 4 | #20 exit 0 si le modèle est inconnu | andredezzy | B2 (partiel) |
| 5 | #27 injection via `cgAnnotatedSessionEventTap` | imtamiliniyan | — |
| 6 | #24 plus de double insertion | justinhnaylor | — |
| 7 | #17 réactivation du tap + checksum installeur | vipergsm | — |
| 8 | #25 `scripts/install-local.sh` | andredezzy | — |
| 9 | #9 commit 1 `6bd10d5f` (privacy) | L65FREAD | — |

#12 passe en premier parce qu'il est le socle de #21 et #23 (vague 3).
#19/#13/#20 touchent trois régions disjointes de `Parrot.swift` et ont fusionné
sans bruit. #9 est cherry-piqué hors ordre — la PR appartient à la vague 4 —
parce que c'est le seul défaut de la file qui continue de produire du dommage
tant qu'il n'est pas repris.

Un seul commit de #9 est pris. `7b3af205` (restriction du tap aux
`flagsChanged`) recoupe #17, déjà dans cette vague ; `68f166c3` (attestation des
releases) est de la vague 4, et le workflow amont publie déjà le `.sha256` dont
la vérification ajoutée par #17 a besoin.

## Décisions

### #11 (bdeol2) — fermée comme doublon, analyse conservée

#11 et #12 corrigent la même ligne de la même façon : passer un `downloadBase`
explicite hors de `~/Documents`. Les deux diagnostics sont complémentaires et
tous les deux justes :

- **#12 (andredezzy)** : iCloud réplique `Documents` et évince les poids en
  stubs dataless (`SF_DATALESS`, `st_blocks == 0` alors que `ls` annonce la
  taille pleine). CoreML `mmap()` un fichier évincé et bloque indéfiniment à la
  compilation ANE.
- **#11 (bdeol2)** : `~/Documents` est aussi protégé par TCC. Lancé depuis un
  terminal, parrot hérite de l'accès du terminal et tout marche ; lancé par
  launchd il n'en a aucun, et `warmUp()` échoue avec un
  `modelsUnavailable`/`invalidMetadataError` qui présente un répertoire
  illisible comme des métadonnées corrompues.

#12 est retenue (elle est le socle de #21/#23 et gère en plus l'ancien
répertoire). L'analyse TCC de #11 est reprise dans le message de merge de #12,
bdeol2 crédité. Rien n'a été posté en amont — on ne commente pas les PRs dans
cette passe, et on n'a de toute façon pas les droits pour fermer #11.

### Conflit #27 / #24

Les deux PRs réécrivent les mêmes lignes du `keyUp` dans `TextInjector.swift`.
#24 supprime `up?.keyboardSetUnicodeString(...)` avec l'ancien
`.cgSessionEventTap` comme contexte, qui n'existe plus après #27.

Résolu en gardant les deux intentions : le `keyUp` est posté sur le tap annoté
(#27) et ne porte aucune charge unicode (#24). Le `NOTE` de #27 sur la collision
de taps est conservé, et un commentaire d'une ligne explique l'absence de charge
sur le `keyUp` pour qu'elle ne se relise pas comme un oubli.

### Raccord `install-local.sh`

Le script de #25 se terminait par `echo "log: /tmp/parrot.err.log"`, chemin que
le commit de #9 venait de supprimer. Il lit maintenant `StandardErrorPath` dans
le plist installé : le script réinstalle le binaire, il ne régénère pas le
launch agent, donc il ne peut pas savoir laquelle des deux options l'utilisateur
a choisie. C'est le seul code écrit par le fork dans cette vague.

## Ce que la vague 1 ne règle pas

Angles morts confirmés — aucune des 25 PRs ne les couvre, et ce sont les seuls
endroits où écrire du code neuf se justifie :

1. **Migration des modèles existants.** #12 change le `downloadBase` mais ne
   déplace rien : un utilisateur existant re-télécharge 1,6 Go en silence et
   laisse l'ancien dossier dans iCloud. On sait déjà qu'un `rm -rf` se bloque
   sur les fichiers évincés et que seul un `mv` en place est instantané.
2. **Warmup non fatal (notre B2).** #13 et #20 suppriment deux causes de sortie
   1 ; aucune ne change le fait qu'un échec de warmup tue le process. Notre cas
   réel — `modelsUnavailable` au warmup — reste entier. Un retry avec backoff
   les couvrirait tous.
3. **`ThrottleInterval` dans le plist.** Absent, donc launchd relance toutes les
   10 s. C'est ce qui a transformé un bug en 9 682 relances.
4. **Rotation et plafond du log.** #9 corrige les permissions et le contenu,
   rien ne borne la taille.
5. **`parrot --version`.** N'existe pas. Personne sur 25 PRs.
6. **État réel dans `models list`.** #19 corrige la troncature ; rien ne dit si
   un modèle est complet. Nos deux modèles dataless s'affichaient comme sains —
   il faut valider la taille sur disque, pas l'existence du dossier.

## Ce qui bloque la suite

Deux arbitrages, tous deux ouverts :

- **#26 (willmather95), 4 256 lignes, 26 fichiers, en conflit avec 9 PRs.** Soit
  il devient la base du fork et tout le reste se rebase dessus, soit on en
  extrait les idées et on le ferme. ADR-0002 : à trancher **immédiatement après
  cette vague**, chaque merge posé avant rend la décision plus coûteuse, et
  c'est la seule décision irréversible du lot.
- **La base du cluster hotkey**, parmi #4 / #7 / #10 / #18. #10 est la base
  recommandée (plus petite surface) ; #18 contient notre B4 (crash au changement
  de format audio) et le forçage de langue, à isoler au minimum. Rien de la
  vague 2 ne bouge tant que ce n'est pas tranché.

## Vérification

Pas de cible de test en amont — build et fumée CLI. Swift 6.3 / Xcode 26.4,
arm64.

- `swift build -c release` : OK
- `parrot run --help` liste `--echo-transcripts`, `--dump-wav` pointe sur
  `~/Library/Caches/parrot/last-capture.wav`
- `parrot install --help` liste `--log-file` et `--purge-legacy-logs`
- `parrot models list` : ids complets
- `parrot doctor` : 4 contrôles OK, dont le nouveau `legacy logs`
- `bash -n` sur les deux scripts

Non exercés, délibérément : le daemon lui-même (demande l'Accessibilité et
1,6 Go de téléchargement) et `parrot install --purge-legacy-logs` (supprime des
fichiers hors dépôt).
