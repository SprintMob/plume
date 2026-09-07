# Un vrai paquet `.app`

Status: ready-for-human

Point de départ : `main` @ le commit de renommage. Deuxième des huit features
du programme de `docs/rebranding/`. Contrairement à la précédente, celle-ci ne
contient presque que des décisions, ce qui est la raison pour laquelle elle en
est séparée : 53 fichiers de substitution mécanique et six fichiers de
décisions ne se relisent pas de la même façon.

L'argument complet est dans [ADR-0008](../../docs/adr/0008-ship-a-real-app-bundle.md).
En une phrase : **c'est TCC, pas l'icône.** Une icône de Dock se pose à
l'exécution sans aucun paquet. Ce qui demande un paquet, c'est que macOS ait une
identité sur laquelle ancrer l'autorisation d'Accessibilité, au lieu de
l'accrocher au terminal parent.

## Ce qui a été ajouté

| Fichier | Rôle |
|---|---|
| `packaging/Info.plist.in` | Le gabarit. Source unique du `CFBundleIdentifier`, donc du label launchd, donc du domaine de préférences |
| `scripts/lib.sh` | `APP_NAME`, `EXEC_NAME`, `BUNDLE_ID`, `LABEL`, `LEGACY_LABEL`, la version, l'écriture du shim |
| `scripts/bundle.sh` | Assemble `Plume.app` sans Xcode, signe, vérifie |
| `docs/adr/0008-ship-a-real-app-bundle.md` | L'argument, ses conséquences, ce qu'il renverse |

`packaging/` est à la racine et pas sous `Sources/` : SwiftPM émet
« found an unhandled resource » pour tout fichier non-Swift dans un répertoire
de cible.

## Trois choses qui se ratent en silence

**`LSUIElement`, jamais `LSBackgroundOnly`.** `LSBackgroundOnly` interdit au
process de présenter la moindre UI, donc ferait échouer le
`setActivationPolicy(.regular)` de `SettingsWindowController`, donc supprimerait
la fenêtre de réglages qu'ADR-0007 a défendue. `LSUIElement` est le drapeau des
apps agent et est explicitement promouvable à l'exécution, ce qui est exactement
la bascule que le code fait déjà.

**`NSMicrophoneUsageDescription` est obligatoire.** Une app bundlée qui appelle
`AVCaptureDevice.requestAccess(for: .audio)` sans cette clé est **tuée** par TCC.
Ça marchait jusqu'ici parce que le process demandeur était le terminal, qui l'a.
C'est le changement le plus susceptible de produire un « ça compilait, ça plante
chez l'utilisateur ».

**`strip` avant `codesign`, jamais après.** Stripper après signature invalide
`_CodeSignature/CodeResources`, et macOS annonce alors l'app comme
**endommagée**, ce que les utilisateurs lisent comme « malware ». Le workflow
strippait un binaire nu, où l'ordre n'avait pas d'importance.

## Une correction de bug cachée dans un changement d'empaquetage

Les deux bundles de ressources SwiftPM, `swift-crypto_Crypto.bundle` et
`swift-transformers_Hub.bundle`, sont copiés dans `Contents/Resources/`.
Ce n'est pas cosmétique : `swift-transformers` cherche ses configs de tokenizer
via `Bundle.module`, dont l'accesseur généré fait `fatalError` s'il ne les
trouve pas, et regarde `Bundle.main.resourceURL` en premier. Le
`/usr/local/bin/plume` nu partait sans elles depuis toujours. C'est un crash
latent supprimé gratuitement.

## Le shim, et l'expérience qui l'a tranché

Le plan laissait ouverte la question « lien symbolique ou shim ». Mesuré le
2026-09-06, sur le paquet réellement construit :

```
$ ln -s …/Plume.app/Contents/MacOS/plume /tmp/plume-link
$ /tmp/plume-link --version
dev
$ /tmp/plume-shim --version
0.0.5
```

`--version` lit `CFBundleShortVersionString` dans `Bundle.main`. À travers le
lien il rend `dev`, donc `Bundle.main` n'a pas résolu jusqu'au paquet, donc
`bundleIdentifier` y est `nil`. Un `plume doctor` lancé à travers un lien
prendrait donc le domaine de préférences du nom de process pendant que le démon
prend `com.sprintmob.plume`. **Deux domaines**, et
`plume install --hotkey right-option` écrirait là où le démon ne lit jamais.

La question est tranchée par la mesure, dans le sens que le plan redoutait : le
lien est faux, pas seulement risqué.

Le LaunchAgent ne pointe ni sur l'un ni sur l'autre. `ProgramArguments[0]` doit
être un chemin **à l'intérieur** du paquet : pointer launchd sur le shim ferait
superviser un `/bin/sh` et détacherait l'attribution TCC. Le shim est pour les
humains, et `Doctor.checkLaunchAgentArgs` fait respecter l'invariant depuis
l'autre bout.

## Ce qui a changé côté Swift

- **`Install.label`** vient de `Bundle.main.bundleIdentifier`, littéral en
  repli pour un build de développement non bundlé. `Install.legacyLabel` garde
  `com.digimata.parrot` indéfiniment.
- **`Install.resolveBinaryPath()`** cherche, du plus spécifique au moins : le
  paquet courant, `/Applications/Plume.app`, `~/Applications/Plume.app`, puis
  `.build/release/plume` **en avertissant**, parce qu'un agent pointant là fait
  tourner le démon avec le domaine de préférences du nom de process.
  `/usr/local/bin/plume` est délibérément absent.
- **`Doctor.checkLaunchAgentArgs`** gagne deux vérifications sur
  `ProgramArguments[0]`, rendues **avant** l'avertissement de flags périmés :
  l'exécutable existe, et il est dans un `.app`. Un agent périmé pointant vers
  un binaire supprimé était jusqu'ici **complètement invisible**, et passer au
  paquet est exactement le genre de changement qui supprime ce binaire.
- **`plume --version`** existe, lue dans le plist. Il n'y en avait aucune.
- **`Plume.main()`** filtre les `-psn_…`. Un double-clic passe par
  LaunchServices, qui peut en ajouter un, et ArgumentParser sort en erreur sur
  tout argument inattendu, donc l'app échouerait à se lancer sans rien dire.
- **La copie des permissions devient vraie.** `Setup` disait que les
  autorisations s'attachent au terminal ; le paquet rend ça faux, dans le bon
  sens. `checkAccessibility` nomme Plume quand il est bundlé et retombe sur le
  nom du parent sinon, ce qui reste exact pour un build de développement.

## Vérification

- `swift test` : 69 tests, 0 échec. Trois neufs sur les deux checks ajoutés,
  et `DoctorLaunchAgentTests` a gagné un vrai faux `Plume.app` dans son
  répertoire temporaire, sans quoi ses tests de flags tombaient sur les
  nouvelles vérifications placées devant eux.
- `./scripts/bundle.sh --output /tmp/bundlecheck` : construit, signe en ad-hoc,
  `codesign --verify --strict` passe, `plutil -lint` passe.
- **Question ouverte tranchée :** les deux bundles de ressources SwiftPM ne
  gênent pas `codesign --strict`. Aucune ligne à ajouter.
- `Plume.app/Contents/MacOS/plume --version` rend `0.0.5`, la même valeur que
  `CFBundleShortVersionString`.

## Ce qui reste à faire, ailleurs

- L'icône. `c2` part **sans** clé `CFBundleIconFile` : icône générique, tout le
  reste marche. L'icône arrive avec le chrome, quand l'asset existe.
- La migration des six emplacements d'état utilisateur, et le check
  `checkLegacyLaunchAgent` dont la remédiation est `plume install --migrate` :
  la commande n'existe pas encore, donc le check non plus. Feature suivante.
- `release.yml`, `install.sh` et la CI de tests : feature d'après.
- L'obligation Apache-2.0 de `swift-argument-parser`, dont l'endroit naturel est
  `Contents/Resources/ACKNOWLEDGEMENTS.txt`, généré par `bundle.sh`.

## Ce qu'il faut vérifier sur appareil

Rien de tout ça ne s'exerce sans un démon signé et lancé.

1. **Le micro**, en révoquant d'abord l'autorisation. Une app sans
   `NSMicrophoneUsageDescription` est tuée par TCC, et le plist en a une.
2. **L'ancrage de l'Accessibilité sur l'app.** `codesign -d -r-` doit montrer
   `identifier` **et** `certificate leaf` après `install-local.sh`. Rebuild deux
   fois et confirmer que l'autorisation survit. Si elle ne survit pas, la
   signature s'est ancrée sur le `cdhash` et le garde-fou du script a été perdu.
3. **Le double-clic sur `Plume.app`.**
4. **La fenêtre de réglages sous launchd**, qui est ce que `ProcessType:
   Interactive` et `LSUIElement` protègent ensemble.
