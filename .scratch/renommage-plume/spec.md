# Renommage mécanique : parrot devient plume

Status: ready-for-human

Point de départ : `main` @ `da6a266`, c'est-à-dire après la sortie des tests
Escape-cancel, sans laquelle rien n'était vérifiable.

Première des huit features du programme décrit dans `docs/rebranding/`. Elle ne
contient **aucune décision** : toutes ont été prises et argumentées là-bas. Elle
existe séparément de l'empaquetage parce que 53 fichiers de substitution
mécanique et six fichiers de vraies décisions ne se relisent pas de la même
façon. Mélangés, ni l'un ni l'autre n'est relisable.

## Ce qui a bougé

| Chose | Avant | Après |
|---|---|---|
| Répertoire des sources | `Sources/parrot/` | `Sources/plume/` |
| Point d'entrée | `Parrot.swift`, `struct Parrot` | `Plume.swift`, `struct Plume` |
| Répertoire des tests | `Tests/parrotTests/` | `Tests/plumeTests/` |
| Cible SPM, `commandName` | `parrot` | `plume` |
| Racine des modèles | `~/Library/Application Support/parrot` | `…/plume` |
| Cache | `~/Library/Caches/parrot` | `…/plume` |
| Log | `~/Library/Logs/parrot.log` | `…/plume.log` |
| Frame de fenêtre | `parrot.settings` | `plume.settings` |
| Binaire installé | `/usr/local/bin/parrot` | `/usr/local/bin/plume` |
| Dépôt de l'installeur | `digimata/parrot` | `sprintmob/plume` |
| URL de l'installeur | `digimata.github.io/parrot` | `plume.sprintmob.com` |

`git mv` pour les trois répertoires, pour que `git log --follow` survive sur
trente fichiers.

**Il n'existe aucun état intermédiaire qui compile à l'intérieur de ce commit.**
SwiftPM déduit le chemin des sources du nom de la cible, donc `Package.swift` et
`Sources/` doivent bouger ensemble. La garantie porte sur la frontière du
commit, pas sur son intérieur, et le dire vaut mieux que faire semblant.

## Ce qui n'a délibérément pas bougé

**`/tmp/parrot.out.log` et `/tmp/parrot.err.log`.** Ces fichiers ont été écrits
par l'ancien parrot et le bug qui les produisait est corrigé. Les renommer
supprimerait silencieusement la remédiation de confidentialité pour exactement
les gens qui migrent, c'est-à-dire ceux pour qui elle existe. C'est l'erreur la
plus probable d'un chercher-remplacer mécanique, donc elle est commentée aux
deux endroits qui portent les chemins.

**Le label launchd `com.digimata.parrot`.** Il devient `com.sprintmob.plume`
avec le bundle, pas avant : c'est le `CFBundleIdentifier` qui le fournira, et
le déplacer maintenant demanderait de le graver en dur deux fois pour le
dégraver au commit suivant.

**Toute l'histoire.** `.scratch/`, `docs/adr/0001` à `0007`, `.plan/`, la
lignée de `CONTEXT.md`, le remote `upstream`. Ces documents décrivent ce qui
s'est passé, et ce qui s'est passé s'appelait parrot.

## Deux corrections prises au passage

Elles sont là parce que le renommage les rendait fausses, pas par confort.

- **`Doctor.checkLegacyLogs` dupliquait le littéral des chemins /tmp.** Il
  appelle maintenant `Install.foundLegacyLogs()`. Deux copies d'un chemin
  qu'on a justement décidé de ne pas renommer sont deux occasions de se
  tromper.
- **Deux messages disaient « an earlier plume version »** après substitution,
  ce qui est faux : ces logs viennent de parrot. Ils disent maintenant « back
  when this was parrot ».

Et une régression évitée : `scripts/install-local.sh` cherchait une identité de
signature `Plume Local Signing` qui n'existe dans aucun trousseau. Il essaie
maintenant le nouveau nom, retombe sur `Parrot Local Signing` en le signalant,
et n'échoue que si aucun des deux n'est là. Recréer le certificat est une
opération de trousseau qu'un agent ne peut pas faire.

## Vérification

- `swift build --build-tests` : vert.
- `swift test` : 66 tests, 0 échec. `DoctorLaunchAgentTests` assert le label
  launchd et une chaîne de remédiation mot pour mot, donc il aurait crié si un
  seul des deux côtés avait bougé seul.
- `grep -ril parrot` sur `Sources/`, `Tests/`, `scripts/`, `.github/` ne rend
  plus que les sept lignes voulues : les quatre chemins `/tmp`, les trois
  usages du label legacy.

## Ce qui reste faux après ce commit

Assumé, corrigé plus loin dans le programme :

- Les réglages retenus, les modèles téléchargés et le job launchd de
  l'utilisateur pointent encore sur `parrot`. La migration est sa propre
  feature, après l'empaquetage, parce qu'elle a besoin de savoir où le paquet
  s'installe.
- `docs/architecture.md` promet toujours « a single binary, no .app bundle ».
  ADR-0008 le renverse avec le paquet.
- Le README et `CONTEXT.md` sont renommés, pas réécrits.
