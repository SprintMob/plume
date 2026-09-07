# Migration : ce que parrot a laissé derrière

Status: ready-for-human

Troisième feature du programme de `docs/rebranding/`. Après l'empaquetage,
parce qu'elle a besoin de savoir où le paquet s'installe pour ré-enregistrer
l'agent à la fin.

## Le problème

Le renommage a orphelin six emplacements d'état utilisateur d'un coup :

| Emplacement | Poids | Ce qu'on perd sans migration |
|---|---|---|
| `~/Library/LaunchAgents/com.digimata.parrot.plist` | ~1 Ko | Deux démons se battent pour le même event tap |
| `~/Library/Application Support/parrot/` | **plusieurs Go** | Re-téléchargement complet des poids |
| `~/Library/Caches/parrot/` | ~1 Mo | Rien, c'est `last-capture.wav` |
| `~/Library/Logs/parrot.log` | variable | Un fichier orphelin en 0600 |
| `~/Library/Preferences/parrot.plist` | ~1 Ko | Raccourci, mode d'injection, micro, **et le modèle actif** |
| `/usr/local/bin/parrot` | ~40 Mo | Un binaire mort dans le `PATH` |

Les poids sont la seule raison pour laquelle ce travail existe. Tout le reste
se re-configure en une minute.

## Où elle vit : `plume install --migrate`

**Pas au premier lancement.** Le démon est sous launchd : pas de terminal,
aucun moyen de signaler un échec partiel, aucun moyen de poser une question. Il
peut en plus avoir été démarré par l'**ancien** agent pendant que ça tourne.
Déplacer plusieurs gigaoctets est exactement l'opération qui ne doit pas être
silencieuse.

**Pas dans `doctor` non plus.** Il est en lecture seule par construction : il
rend `[Check]` et n'a aucun effet de bord. On reprend le partage que le repo a
déjà, `Doctor.checkLegacyLogs` **détecte** et `install --purge-legacy-logs`
**agit**. D'où `Doctor.checkLegacyLaunchAgent` d'un côté, `--migrate` de
l'autre.

**Pas un bouton dans la fenêtre de réglages**, alors qu'elle en offre un pour
les logs legacy. Le déplacement des modèles a besoin d'un terminal où rendre
compte. On montre le check et la commande.

## La forme : tout vérifier, puis agir

Le demi-état dangereux est l'étape 1 qui sort l'ancien agent, puis l'étape 2 qui
échoue : l'utilisateur se retrouve sans démon **et** sans modèles là où le
nouveau binaire regarde. Donc `preflight()` ne fait **aucune écriture** et une
seule de ses plaintes suffit à tout abandonner :

- les deux racines de modèles ne peuvent pas coexister — fusionner est une
  question de données, pas un renommage, et on refuse ;
- elles doivent être sur le même `st_dev`, sinon ce n'est pas un `rename(2)`
  mais une copie de plusieurs Go qui peut remplir le disque. On interroge
  `stat` plutôt qu'une resource value d'URL, parce que la question est
  exactement « un syscall ou une copie » ;
- `~/Library/LaunchAgents` doit être accessible en écriture ;
- `/bin/launchctl` doit être là.

Puis les six déplacements, dans un ordre qui porte des raisons :

1. **L'agent**, en premier, parce que c'est le seul processus qui pourrait
   écrire dans ce qui suit. On retient au passage si `--log-file` était actif,
   pour ré-enregistrer comme l'utilisateur l'avait choisi.
2. **Les modèles.** Même volume vérifié, donc `rename(2)` : atomique, instantané.
3. **Le cache.** S'il ne se déplace pas, on le **supprime** : c'est un artefact
   de debug, jamais une raison de s'arrêter.
4. **Le log**, en réaffirmant le 0600. Ce fichier a été world-readable une fois,
   et c'était un bug de confidentialité livré.
5. **Les préférences.**
6. **L'ancien binaire**, détecté, jamais supprimé.
7. **Ré-enregistrement de l'agent, inconditionnel**, même si l'étape 2 a échoué.
   Un utilisateur avec un démon qui tourne et pas de poids peut re-télécharger ;
   un utilisateur sans rien ne peut rien faire.

## Les préférences ne sont pas un déplacement de fichier

`~/Library/Preferences/parrot.plist` appartient à `cfprefsd`, qui le met en
cache. Le déplacer dans son dos perd des écritures. On lit le fichier et on
écrit via `UserDefaults`.

Trois choses portent des décisions :

- **`guard defaults.object(forKey:) == nil`** rend l'étape idempotente, donc
  rend sûre une reprise après échec partiel : une clé déjà migrée n'est jamais
  écrasée par une valeur périmée. Testé dans les deux sens.
- **On lit le fichier plutôt que `UserDefaults(suiteName: "parrot")`**, ce qui
  supprime une incertitude. Et **c'est l'étape 1 qui rend cette lecture sûre** :
  l'ancien démon est sorti, donc aucun client `cfprefsd` ne détient une copie
  plus récente.
- **On ne supprime pas le domaine legacy.** Quelques centaines d'octets, et
  c'est le seul moyen de rejouer la migration si la nouvelle installation est
  jetée.

### Les clés, qui doivent dépasser les cinq de `SettingsStore`

`Migration.Keys.all` n'est pas une liste écrite à la main. Chaque store expose
`migratableKeys` et la migration les concatène, donc un store qui gagne une clé
gagne sa migration avec. Huit clés : les cinq de `SettingsStore`, les deux de
`ModelStore`, celle d'`InputDeviceStore`.

**Perdre `modelID` fait re-télécharger des gigaoctets pour une chaîne
manquante.** C'est pour ça qu'un test assert l'ensemble exact plutôt que de lui
faire confiance.

## Ce qui n'est pas migré

Le frame de fenêtre sauvegardé sous `parrot.settings` devient `plume.settings`
et **on accepte de perdre la position**. On ne dépense pas une clé de migration
pour un rectangle. C'est dans les conséquences d'ADR-0008 pour que personne
n'ouvre un ticket.

## Vérification

- `swift test` : 85 tests, 0 échec. `MigrationTests` en ajoute 16, contre un
  faux `$HOME` temporaire, grâce à `Migration.Paths` injectable.
- **Deux coutures existent uniquement pour que ces tests soient honnêtes** :
  `launchctl` et `registerAgent`. Un test qui sortirait un vrai agent de la
  session launchd qui l'exécute, ou en enregistrerait un, serait pire que pas de
  test. Les étapes 1 et 7 sont donc les seules non couvertes.
- `plume install --migrate` sur une machine propre dit « nothing to migrate » et
  sort à 0.

## Ce qu'il faut vérifier sur appareil

C'est la feature dont la vérification automatique couvre le moins.

1. **`du -sh` avant et après.** Le déplacement doit prendre des
   millisecondes. S'il prend des minutes, ce n'est pas un `rename(2)` et la
   précondition « même volume » a échoué sans le dire.
2. **Les modèles ne sont pas re-téléchargés.**
3. **L'ancien job launchd a disparu** de `launchctl list`.
4. **Les réglages retenus ont survécu**, en particulier le modèle actif.
5. **`plume doctor` passe au vert**, y compris le nouveau check
   `legacy launch agent`.
