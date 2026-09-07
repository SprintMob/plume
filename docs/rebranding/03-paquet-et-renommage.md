# Paquet `.app`, renommage, distribution

## Les identifiants

| Chose | Valeur |
|---|---|
| Produit | `Plume` |
| Cible SPM et CLI | `plume`, tests `plumeTests` |
| Identifiant de bundle | `com.sprintmob.plume` |
| Label launchd | `com.sprintmob.plume`, **la même chaîne** |
| Domaine des préférences | `com.sprintmob.plume`, découle du bundle |
| Support | `~/Library/Application Support/plume` |

Minuscules plutôt que `com.sprintmob.Plume` : cette chaîne sert aussi de label
launchd et de nom de fichier dans `~/Library/Preferences/`, où une casse mixte
est du bruit.

**À vérifier avant de la graver :** si SprintMob publie déjà sous un autre
préfixe reverse-DNS (`io.sprintmob`, `app.sprintmob`), le changer après une
release coûte une **deuxième migration** aux utilisateurs. La liste des App ID
de l'équipe tranche.

## Le bundle, assemblé sans Xcode

`scripts/bundle.sh` plus un gabarit `packaging/Info.plist.in`. **Pas sous
`Sources/`** : SwiftPM émet « found an unhandled resource » pour tout fichier
non-Swift dans un répertoire de cible. `packaging/` à la racine.

```
Plume.app/
  Contents/
    Info.plist
    PkgInfo                                  ("APPL????")
    MacOS/
      plume                                  le binaire SPM, strippé
    Resources/
      plume.icns
      swift-crypto_Crypto.bundle/
      swift-transformers_Hub.bundle/
    _CodeSignature/                          écrit par codesign
```

> **Corrigé à l'exécution, 2026-09-07 :** ce qui suit était mesuré sur des
> artefacts périmés de `.build`, datés du 2026-08-24.
> `swift package show-dependencies` rend trois paquets, aucun n'émet de bundle
> de ressources, et rien dans les cibles liées n'appelle `Bundle.module`.
> `bundle.sh` garde la boucle de copie pour le jour où ça change. Détail dans
> [ADR-0008](../adr/0008-ship-a-real-app-bundle.md).

**Les deux bundles de ressources SwiftPM ne sont pas optionnels.**
`swift-transformers_Hub.bundle` contient des **données d'exécution**, les
configs de tokenizer, que swift-transformers cherche via `Bundle.module`, dont
l'accesseur généré fait `fatalError` s'il ne les trouve pas. Aujourd'hui
`/usr/local/bin/parrot` part seul, sans elles : c'est un crash latent sur tout
chemin qui retombe sur les configs packagées. Les mettre dans
`Contents/Resources/` corrige ça gratuitement, parce que l'accesseur généré
regarde `Bundle.main.resourceURL` en premier. À signaler dans l'issue : c'est
une correction de bug cachée dans un changement d'empaquetage.

### Deux détails qui portent des décisions

**`swift build --show-bin-path`** au lieu du chemin en dur
`.build/arm64-apple-macosx/release/parrot` qu'utilise `release.yml`. Avec
`--arch arm64` le chemin change, et `install-local.sh:43,45,56` code **l'autre**.
Un helper supprime les deux codages en dur.

**`strip` avant `codesign`.** Aujourd'hui `release.yml` strippe un binaire nu, ce
que `strip` de cctools re-signe automatiquement en ad-hoc. Pour un bundle,
stripper **après** `codesign` invalide `_CodeSignature/CodeResources` et macOS
annonce l'app comme **endommagée**, pas comme non signée.

### `packaging/Info.plist.in`

```xml
<key>CFBundleIdentifier</key>            <string>@BUNDLE_ID@</string>
<key>CFBundleExecutable</key>            <string>@EXEC_NAME@</string>
<key>CFBundleName</key>                  <string>@APP_NAME@</string>
<key>CFBundleDisplayName</key>           <string>@APP_NAME@</string>
<key>CFBundlePackageType</key>           <string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
<key>CFBundleShortVersionString</key>    <string>@VERSION@</string>
<key>CFBundleVersion</key>               <string>@VERSION@</string>
<key>LSMinimumSystemVersion</key>        <string>14.0</string>
<key>LSUIElement</key>                   <true/>
<key>NSHighResolutionCapable</key>       <true/>
<key>NSMicrophoneUsageDescription</key>
<string>Plume records audio while you hold the dictation key, transcribes it on
this Mac, and types the result at your cursor. Nothing leaves the machine.</string>
```

**Deux clés sont porteuses, et se tromper sur l'une ou l'autre est silencieux.**

**`LSUIElement`, surtout pas `LSBackgroundOnly`.** `LSBackgroundOnly = true`
interdit au process de présenter la moindre UI, donc fait échouer le
`NSApp.setActivationPolicy(.regular)` de `SettingsWindowController.swift:36`,
donc **supprime la fenêtre de réglages** qu'ADR-0007 a défendue. `LSUIElement`
est le drapeau des apps agent et est explicitement promouvable à l'exécution :
exactement la bascule `.accessory` ↔ `.regular` que le code fait déjà. Bonus, il
supprime le flash d'icône Dock au lancement.

**`NSMicrophoneUsageDescription` est obligatoire, pas cosmétique.** Une app
bundlée qui appelle `AVCaptureDevice.requestAccess(for: .audio)`
(`Setup.swift:59`) sans cette clé est **tuée** par TCC. Ça marche aujourd'hui
parce que le process demandeur est le terminal, qui l'a. C'est le changement le
plus susceptible de produire un « ça compilait, ça plante chez l'utilisateur ».

Pas de `NSAppleEventsUsageDescription` : rien ne script d'autres apps.
L'Accessibilité n'a aucune clé d'usage, elle s'accorde dans Réglages Système.

### Version

`CFBundleShortVersionString` depuis
`git describe --tags --match 'v*' --abbrev=0` sans le `v`, surchargeable par
`$PLUME_VERSION`, défaut `0.0.0` hors tag. La CI passe `${GITHUB_REF_NAME#v}`
explicitement pour qu'une release ne dépende jamais de la profondeur du fetch.

Puis on boucle côté Swift, un vrai petit gain que le bundle débloque :

```swift
static let configuration = CommandConfiguration(
    commandName: "plume",
    abstract: "Minimal macOS dictation daemon. Hold Fn, speak, release.",
    version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
    subcommands: [Run.self, Setup.self, Doctor.self, Models.self, Install.self],
    defaultSubcommand: Run.self
)
```

`plume --version` et le bundle s'accordent par construction, et ça dégrade en
`dev` hors bundle. **Il n'y a aucun `version:` aujourd'hui.**

### L'icône ne bloque pas le bundle

On livre c2 **sans** clé `CFBundleIconFile` : icône générique, tout le reste
marche. L'icône arrive dans sa propre feature quand l'asset 1024 existe. Voir
[02](./02-design-systeme.md#licône-dapp).

### Le lancement par LaunchServices

Un double-clic sur `Plume.app` lance le binaire **sans argument**.
`defaultSubcommand: Run.self` gère ça. Mais ArgumentParser sort en erreur sur
tout argument **inattendu**, et un `open --args` ou un `-psn_…` parasite serait
fatal. Une ligne défensive dans l'issue, un item dans la validation appareil.

## Le CLI : un shim, pas un lien symbolique

L'app va dans `/Applications/Plume.app` en distribution,
`~/Applications/Plume.app` en dev local (pas de sudo à chaque rebuild). Le CLI
est `/usr/local/bin/plume` :

```sh
#!/bin/sh
# /usr/local/bin/plume: the CLI is the app.
exec "/Applications/Plume.app/Contents/MacOS/plume" "$@"
```

L'alternative est un `ln -s`, plus simple. **Le risque est précis et sévère :**
si `Bundle.main` ne résout pas à travers le lien jusqu'au `.app`, alors
`plume doctor` lancé depuis `/usr/local/bin` prend le domaine de préférences
`plume` (nom du process) pendant que le démon dans le bundle prend
`com.sprintmob.plume`. **Deux domaines.**
`plume install --hotkey right-option` écrirait là où le démon ne lit jamais, et
la menu bar semblerait ignorer le réglage : exactement le mode de panne
qu'ADR-0004 existe pour empêcher, réintroduit silencieusement.

CoreFoundation dérive `_CFProcessPath` de `_NSGetExecutablePath` et fait un
`realpath()`, donc le lien marche *probablement*. Ce n'est pas assez sûr pour y
adosser le domaine de préférences. Le shim rend `argv[0]` non ambigu et coûte
trois lignes.

**L'expérience qui tranche**, trente secondes, à faire réellement : ajouter la
ligne `version:` ci-dessus, puis

```sh
ln -sf /Applications/Plume.app/Contents/MacOS/plume /tmp/plume-link
/tmp/plume-link --version
defaults read com.sprintmob.plume
```

Si `Bundle.main.bundleIdentifier` vaut `com.sprintmob.plume` à travers le lien,
prendre le lien et supprimer le shim de la conception.

### `Install.resolveBinaryPath()`, en remplacement de `Install.swift:283-293`

Ordre, du plus spécifique au moins :

1. **Le bundle courant.** Correct que l'app soit dans `/Applications`,
   `~/Applications` ou un `dist/` de développement, et c'est le seul candidat
   qui soit certainement le code en train d'écrire cet agent.
2. et 3. Les deux emplacements d'installation, par ordre de préférence.
4. Développement : `.build/release/plume`, non bundlé. **Avertir** : un agent
   pointant là fait tourner le démon avec le domaine de préférences du nom de
   process, donc tous les choix retenus lui sont invisibles.

**`/usr/local/bin/plume` est délibérément absent de la liste.** Pointer le
LaunchAgent sur le shim ferait superviser un `/bin/sh` par launchd au lieu du
démon, et détacherait l'attribution TCC du bundle. Le shim est pour les humains.

Nouvel invariant, à écrire dans le commentaire de `Install.swift` :
**`ProgramArguments[0]` doit être un chemin à l'intérieur d'un bundle `.app`.**
`Doctor` le fait respecter, voir plus bas.

## Le LaunchAgent : on garde le plist, on décline `SMAppService`

Le commentaire `Install.swift:10-14` dit :

> We deliberately do NOT use `SMAppService.mainApp` here — that requires a full
> `.app` bundle.

**La prémisse s'évapore.** Elle doit être **remplacée**, pas supprimée, et le
remplacement est quatre pertes concrètes :

1. **`KeepAlive: {SuccessfulExit: false}`** : `SMAppService.mainApp` n'en donne
   aucun contrôle. Le commentaire `Install.swift:99-107` documente le bug
   d'umask où `KeepAlive` a transformé un EACCES de warmup en boucle de
   relance ; cette politique est comprise et délibérée.
2. **`Umask: 0o077`** : aucun équivalent. C'était un bug livré, corrigé sur une
   vraie installation.
3. **`ProcessType: Interactive`** : c'est ce qui permet au démon de basculer en
   `.regular` dans une session GUI, donc ce qui fait marcher la fenêtre de
   réglages sous launchd. `.scratch/settings-window/issues/06-*.md` le liste
   comme le principal risque non prouvé.
4. **`StandardOutPath` / `StandardErrorPath`** : toute la feature `--log-file`
   et l'argument de confidentialité autour.

`SMAppService.mainApp` ne peut en outre passer **aucun** `ProgramArguments`,
donc `run --skip-doctor` est inexprimable. Et `SMAppService.agent(plistName:)`
garde un plist mais l'exige **immuable** dans `Contents/Library/LaunchAgents/`,
ce qui tue le choix `--log-file` par utilisateur.

Ce que `SMAppService` apporterait : une entrée dans Réglages Système → Ouverture
de session que l'utilisateur peut basculer, et pas de `launchctl` à shell-er. Ça
ne vaut pas quatre comportements que le repo a déjà bataillés et documentés.

**C'est un bon ADR :** le bundle **rouvre** l'option, et elle est **refusée pour
d'autres raisons qu'avant**.

### Le label et l'ordre du bootout

```swift
/// The bundle id, which is also the launchd label and the preferences domain.
/// One string, and `packaging/Info.plist.in` is where it lives. The literal is
/// only the fallback for an unbundled development build.
static let label = Bundle.main.bundleIdentifier ?? "com.sprintmob.plume"

/// The label used before the rename. Kept indefinitely: it is the only way
/// `doctor` can explain why two daemons are competing for the same event tap.
static let legacyLabel = "com.digimata.parrot"
```

L'ancien job doit être **bootout avant** que l'ancien binaire disparaisse, sinon
`KeepAlive` le relance contre un chemin ENOENT une dizaine de fois puis
l'étrangle, laissant du bruit dans les logs système et un `launchctl list`
confus.

```
launchctl bootout gui/$UID/com.digimata.parrot     # ignorer l'échec
rm ~/Library/LaunchAgents/com.digimata.parrot.plist
… puis écrire et bootstrap com.sprintmob.plume
```

### Ce que `Doctor` doit vérifier en plus

`checkLaunchAgentArgs` garde sa vérification de flags périmés et en gagne deux,
plus une troisième vérification à côté :

1. *(existant)* pas de `--hotkey` / `--inject-mode` / `--no-overlay` /
   `--mute-output` dans `ProgramArguments`.
2. *(nouveau)* `ProgramArguments[0]` nomme un exécutable qui existe. Aujourd'hui
   un agent périmé pointant vers un binaire supprimé est **complètement
   invisible** pour `doctor`, et cette migration supprime un binaire.
3. *(nouveau)* `ProgramArguments[0]` est dans un `.app`. Sinon le démon tourne
   avec le domaine de préférences du nom de process et ignore tous les choix
   retenus : panne totale et silencieuse de la menu bar et de la fenêtre.
4. *(nouveau, séparé)* `checkLegacyLaunchAgent()` : avertir si
   `~/Library/LaunchAgents/com.digimata.parrot.plist` existe encore.
   Remédiation : `` run `plume install --migrate` ``.

**Conséquence à ne pas oublier :** `DoctorReport.run` rend 6 ou 7 checks, plus
5. Trois chaînes disent « les cinq checks » et bougent ensemble, dans le README,
`SettingsRootView.swift:5` et la section Home.

## Signature : trois mécanismes qu'on confond tout le temps

**(a) L'exigence du noyau.** Un Mach-O arm64 doit porter *une* signature ; `ld`
en applique une ad-hoc et `strip` la régénère. Rien ne change.

**(b) Gatekeeper.** Ne s'applique **qu'au code mis en quarantaine**, et c'est le
**téléchargeur** qui la pose. `curl` n'en pose pas.

- `curl -fsSL … | sh` → **pas de quarantaine, pas de Gatekeeper, l'app s'ouvre
  sans invite, exactement comme aujourd'hui.** Le `xattr -d` de `install.sh:86`
  reste par précaution, et devient **récursif**.
- Téléchargement du zip **au navigateur** → quarantaine. Pour une app signée
  ad-hoc, le message est **« Plume est endommagé et ne peut pas être ouvert »**,
  pas le plus doux « développeur non identifié », qui est réservé aux apps
  signées Developer ID mais non notarisées. Sur macOS 15+, le clic droit → Ouvrir
  ne contourne plus : il faut passer par Réglages Système → Confidentialité et
  sécurité → Ouvrir quand même, ou `xattr -dr`.

**Donc l'énoncé honnête est étroit : le chemin navigateur empire, le chemin
`curl | sh` est inchangé.**

**(c) TCC, et c'est là que ça fait mal.** Ça n'a rien à voir avec Gatekeeper.

Les autorisations d'Accessibilité s'ancrent sur l'**exigence désignée** du code.
Aujourd'hui `/usr/local/bin/parrot` porte :

```
designated => identifier parrot and certificate leaf = H"e00d23f047c1e9…"
```

Cet ancrage sur un certificat est **tout l'intérêt** de `install-local.sh` et de
son commentaire d'en-tête : il survit aux rebuilds. Avec une signature
**ad-hoc**, l'exigence devient `identifier "com.sprintmob.plume" and cdhash
H"…"`, invalidée par **chaque release et chaque rebuild local**. Le symptôme est
vicieux : la dictée enregistre, transcrit, affiche la bulle, et **cesse
silencieusement d'écrire au curseur**, sans erreur, jusqu'à ce que l'utilisateur
réactive Plume dans Accessibilité.

**Donc : l'ad-hoc suffit pour tourner, pas pour publier.** Un certificat
Developer ID produit
`identifier … and anchor apple generic and certificate leaf[subject.OU] = "TEAMID"`,
que tous les builds futurs satisfont. **C'est ça, et non Gatekeeper, l'argument
pour acheter un Developer ID.**

Pour un bundle il faut aussi signer le **bundle**, pas seulement l'exécutable :
sans `_CodeSignature/CodeResources`, `codesign --verify` échoue et plusieurs
chemins macOS refusent l'app.

### Les deux paliers, tous deux dans le workflow dès le premier jour

**Palier 0, sans compte Apple :**

```sh
codesign --force --sign - --timestamp=none dist/Plume.app
codesign --verify --strict --verbose=2 dist/Plume.app
```

Ad-hoc explicite, pour que le sceau du bundle existe. Le README porte
l'avertissement, voir [04](./04-vitrine-et-licence.md).

**Palier 1, une fois le Developer ID et les identifiants notarytool en place :**

```sh
codesign --force --options runtime --timestamp \
  --entitlements packaging/plume.entitlements \
  --sign "Developer ID Application: SprintMob (TEAMID)" dist/Plume.app
ditto -c -k --sequesterRsrc --keepParent dist/Plume.app dist/notarize.zip
xcrun notarytool submit dist/notarize.zip --keychain-profile plume-notary --wait
xcrun stapler staple dist/Plume.app
```

`packaging/plume.entitlements` a besoin d'une clé :
`com.apple.security.device.audio-input`. Le runtime durci est requis pour la
notarisation ; le `CGEventTap` a besoin de l'autorisation TCC Accessibilité et
non d'un entitlement, donc `--options runtime` ne devrait pas le casser, et rien
n'est `dlopen` à l'exécution (les modèles CoreML sont des données), donc pas
d'exception de validation de bibliothèque.

**Écrire les deux paliers dans `release.yml` maintenant**, le palier 1
conditionné à `secrets.MACOS_CERTIFICATE_P12 != ''`, pour que l'activer plus
tard soit un ajout de secret et pas une réécriture du workflow.

### Le chemin dev local, `scripts/install-local.sh`, lancé **par l'utilisateur**

Quatre changements, par ordre d'importance :

**1. Le nom d'identité, avec un repli.** L'en-tête dit de créer un certificat
`Parrot Local Signing` ; le recréer en `Plume Local Signing` demande `openssl`
plus `security import` plus `security add-trusted-cert`, une opération de
trousseau qu'un agent ne peut pas faire. Donc : chercher `Plume Local Signing`
puis, à défaut, `Parrot Local Signing` en le signalant. Le renommage devient un
no-op pour la machine qui l'a aujourd'hui, et correct pour quiconque part de
zéro.

**2. Signer le bundle, abandonner `--identifier`.** Pour un bundle, `codesign`
prend l'identifiant depuis `CFBundleIdentifier`, ce qui est voulu et empêche
l'identifiant de diverger du plist.

**3. Garder le garde-fou `cdhash` mot pour mot.** Les lignes 45-52 sont la
meilleure chose du script : elles **prouvent** que l'autorisation d'Accessibilité
survivra au prochain build. Elles doivent survivre à la réécriture, seul le
chemin changeant.

**4. `ditto`, pas `cat`, pas `cp -R`.** Le `cat` de la ligne 56 existe parce que
`/usr/local/bin` appartient à root et que codesign écrit des fichiers temporaires
à côté de sa cible. On ne `cat` pas un répertoire, et `cp -R` peut perdre des
attributs étendus et invalider le sceau. `ditto` préserve tout.

## Migration : tout vérifier, puis agir

### Où elle vit : `plume install --migrate`

**Pas au premier lancement.** Il est sous launchd : pas de terminal, aucun moyen
de signaler un échec partiel, aucun moyen de poser une question. Déplacer
plusieurs gigaoctets est exactement l'opération qui ne doit pas être silencieuse.
Le démon peut en plus être démarré par l'**ancien** agent en cours de route.

**Pas dans `doctor`.** Il est en lecture seule par construction : il rend
`[Check]` et n'a aucun effet de bord. On garde ça et on reprend le motif que le
repo a déjà : `Doctor.checkLegacyLogs` **détecte**,
`install --purge-legacy-logs` **agit**. La migration prend la même forme, et
cette symétrie est l'argument à mettre dans l'ADR.

La fenêtre de réglages pourrait offrir un bouton comme elle le fait pour les logs
legacy. **Non** : le déplacement des modèles a besoin d'un terminal où rendre
compte. On montre le check et la commande.

### La forme : préconditions d'abord, action ensuite

Le demi-état dangereux est l'étape 1 qui sort l'ancien agent puis l'étape 2 qui
échoue : l'utilisateur se retrouve sans démon **et** sans modèles là où le
nouveau binaire regarde. Donc : **toutes les préconditions d'abord, on abandonne
tout si l'une échoue, et on ré-enregistre l'agent à la fin inconditionnellement.**

Préconditions, sans aucune écriture :

- `~/Library/Application Support/plume` ne doit pas déjà exister si `…/parrot`
  existe
- les deux doivent être **sur le même volume**, pour un `rename(2)` et non une
  copie de plusieurs Go
- `~/Library/LaunchAgents` doit être accessible en écriture
- `/bin/launchctl` doit être présent

### Les six déplacements

**1. Le LaunchAgent**, en premier parce que c'est le seul processus qui pourrait
écrire dans ce qui suit. On retient au passage si `--log-file` était actif.

**2. Les modèles**, `…/parrot` → `…/plume`. Même volume vérifié, donc
`rename(2)` : **atomique, instantané, aucune copie, aucun risque de remplir le
disque**. C'est toute la raison de migrer plutôt que re-télécharger. Si les deux
répertoires existent, on **refuse** : fusionner deux racines de modèles est une
question de données, pas un renommage.

**3. Les caches.** Ne contient que `last-capture.wav`. Si le déplacement échoue,
supprimer la source : c'est un artefact de debug, pas des données utilisateur.
Ne jamais laisser ça bloquer.

**4. Le log**, en préservant le mode 0600.

**5. Les préférences**, `parrot` → `com.sprintmob.plume`. **Pas un déplacement de
fichier :** `~/Library/Preferences/parrot.plist` appartient à `cfprefsd`, qui le
met en cache, et le déplacer dans son dos perd des écritures. On lit le plist
directement et on écrit via `UserDefaults`.

```swift
for key in MigrationKeys.all {
    guard let value = dict[key], defaults.object(forKey: key) == nil else { continue }
    defaults.set(value, forKey: key)
}
```

Trois choses portent des décisions ici :

- Le `guard defaults.object(forKey:) == nil` rend l'étape **idempotente** et rend
  sûre une reprise après échec partiel : une clé déjà migrée n'est jamais
  écrasée par une valeur périmée.
- On lit le fichier plutôt que `UserDefaults(suiteName: "parrot")`, ce qui
  supprime une incertitude. Et **c'est l'étape 1 qui rend cette lecture sûre** :
  l'ancien démon est sorti, donc aucun client `cfprefsd` ne détient une copie
  plus récente. À mettre en commentaire dans le code.
- **`MigrationKeys.all` doit dépasser les cinq clés de `SettingsStore`.** Il faut
  aussi celle de `ModelStore` et celle de `InputDeviceStore`. **Perdre
  l'identifiant du modèle actif fait re-télécharger des gigaoctets pour une
  chaîne manquante.** À définir en un seul endroit et à asserter dans un test.

Ne **pas** supprimer le domaine legacy : quelques centaines d'octets, et c'est le
seul moyen de rejouer la migration si la nouvelle installation est jetée.

**6. L'ancien `/usr/local/bin/parrot`.** Demande root, et un démon GUI ne doit
pas tenter un `sudo`. On détecte et on **affiche la commande**. Ne pas faire
échouer la migration pour ça.

**7. Ré-enregistrer l'agent**, **même si l'étape 2 a échoué**, pour laisser
l'utilisateur avec un démon qui tourne, quitte à re-télécharger, plutôt qu'avec
rien.

### Ce qui n'est pas migré

Le frame de fenêtre sauvegardé sous `parrot.settings` devient `plume.settings` et
**on accepte de perdre la position**. On ne dépense pas une clé de migration pour
un rectangle. À écrire dans les conséquences de l'ADR pour que personne n'ouvre
un ticket.

### Testabilité

`DoctorLaunchAgentTests` injecte déjà une URL et `Install.plistURL` est un
`static var` : le repo a déjà la couture. Faire prendre au migrateur ses six
chemins dans une structure injectable rend l'ensemble testable contre un
répertoire temporaire. C'est une phrase dans l'issue, et c'est la différence
entre une migration testée et une migration espérée.

## Le renommage, séquencé

SwiftPM déduit le chemin des sources du nom de la cible. Le `name:` de
`Package.swift` et le répertoire `Sources/` **doivent changer dans le même
commit** : il n'existe aucun état intermédiaire qui compile. À dire franchement
dans l'issue au lieu de faire semblant ; la garantie porte sur la **frontière**
du commit.

`git mv` pour les répertoires, pour que git enregistre les renommages et que
`git log --follow` survive sur trente fichiers.

```
1. git mv Sources/parrot Sources/plume
2. git mv Sources/plume/Parrot.swift Sources/plume/Plume.swift
3. git mv Tests/parrotTests Tests/plumeTests
4. Package.swift : name, executableTarget, testTarget + dependencies
5. Plume.swift:6-13  struct Parrot → struct Plume, commandName "parrot" → "plume"
     (@main n'a besoin de rien d'autre : `Parrot` n'apparaît comme nom de type
      qu'à un seul endroit, vérifié par grep)
6. les 8 fichiers de test : @testable import parrot → plume
7. swift build --build-tests   ← vert ici, et seulement ici
```

Puis une deuxième passe, sûre à la compilation, dans le même commit, pour la
soixantaine de chaînes et commentaires.

### Les paires atomiques

Chaque endroit où un demi-renommage **compile mais est faux** :

| Doivent bouger ensemble | Fichiers |
|---|---|
| Le label launchd | `Install.swift:97` · `install-local.sh:31` · `DoctorLaunchAgentTests.swift:23,24` · `ConfigurationSection.swift:58` |
| La chaîne de remédiation | `Doctor.swift:60` ↔ `DoctorLaunchAgentTests.swift:47`, asserté avec `XCTAssertEqual` |
| Racine des modèles + migration étape 2 | `ModelWeights.swift:10` |
| Répertoire de cache + étape 3 | `Parrot.swift:403` |
| Chemin de log + étape 4 | `Install.swift:193` |

Pour le label, **corriger la duplication tant qu'on y est** plutôt que de le
renommer à quatre endroits : `Install.label` depuis
`Bundle.main.bundleIdentifier`, et un `scripts/lib.sh` sourcé par `bundle.sh`,
`install-local.sh` et `install.sh` qui définit `BUNDLE_ID`, `LABEL`, `APP_NAME`,
`EXEC_NAME`. `packaging/Info.plist.in` devient la source unique pour le cas
déployé. C'est strictement mieux que l'existant et ça vaut sa propre issue.

Même occasion : `Doctor.checkLegacyLogs` appelle `Install.foundLegacyLogs()` au
lieu de dupliquer le littéral.

### Ce qui ne se renomme pas

Voir [01](./01-etat-des-lieux.md#ce-qui-ne-doit-surtout-pas-être-renommé) : les
chemins `/tmp/parrot.*.log`, et toute l'histoire (`.scratch/`, ADR 0001 à 0007,
`.plan/`).

`CONTEXT.md` demande un vrai travail, pas un chercher-remplacer : l'entrée
**Launch agent** nomme `com.digimata.parrot`, il faut de nouvelles entrées pour
**bundle d'app** et **shim CLI**, et les entrées **Upstream** et **Wave** ne
bougent pas parce qu'elles décrivent l'histoire.

## CI et distribution

### `release.yml`

`bundle.sh` remplace le build et le `strip` manuels, puis palier de signature,
puis :

```sh
ditto -c -k --sequesterRsrc --keepParent Plume.app plume-macos-arm64.zip
shasum -a 256 plume-macos-arm64.zip > plume-macos-arm64.zip.sha256
```

**Zip via `ditto`, pas tar.gz.** La raison décisive est tournée vers l'avant :
`xcrun notarytool submit` n'accepte que `.zip`, `.pkg` et `.dmg`. Choisir tar.gz
aujourd'hui, c'est réécrire l'étape le jour où le Developer ID arrive. Raisons
secondaires : `--sequesterRsrc` préserve les attributs étendus, `--keepParent`
garde `Plume.app` comme entrée de premier niveau au lieu d'exploser `Contents/`
dans le répertoire courant.

### La CI de tests qui n'existe pas

```yaml
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift build -c release
      - run: swift test
      - run: ./scripts/bundle.sh --output /tmp/bundlecheck
      - run: plutil -lint /tmp/bundlecheck/Plume.app/Contents/Info.plist
```

Trois lignes de YAML, et c'est ce qui rend « chaque commit compile isolément »
**vérifiable** au lieu qu'espéré. C'est aussi ce qui aurait attrapé le fichier de
tests cassé.

### `scripts/install.sh`

`REPO="sprintmob/plume"`, l'app dans `/Applications`, le shim dans
`/usr/local/bin/plume`.

Flux : Darwin et arm64 → résoudre le dernier tag → télécharger le zip et son
`.sha256` → `shasum -c` → **`ditto -x -k`** → **`xattr -dr`** →
**`codesign --verify --strict`** → `sudo ditto` vers `/Applications` → écrire le
shim → si `~/Library/Application Support/parrot` ou l'ancien plist existe,
afficher `run: plume install --migrate`.

**Deux bugs d'un caractère qui attendent :** `xattr -dr` doit être **récursif**
(aujourd'hui `-d` sur un seul fichier), et `ditto -x -k` plutôt que `unzip`,
certaines versions d'`unzip` perdant les attributs étendus.

Le `codesign --verify` mérite sa ligne : un bundle corrompu produit « Plume est
endommagé », que les utilisateurs lisent comme « malware ». L'attraper dans
l'installeur avec un vrai message vaut le coup.

**Une histoire de désinstallation**, tant qu'on y est : avec un vrai `.app`,
`plume install --uninstall` devrait aussi afficher les trois `rm` pour l'app, le
shim et le répertoire des modèles. C'est petit, et c'est le genre de chose sur
laquelle une release open source se fait juger.

## Ce qu'ADR-0008 doit tenir

Écrit avec c2, comme ADR-0004 et ADR-0007 ont atterri avec leur feature. En
anglais, argumentatif, avec une section `## Consequences`.

### L'argument

Le bundle coûte cher : il réécrit l'installation, la signature, le LaunchAgent
et la CI, pour une app qui n'a ni fenêtre principale ni icône de Dock permanente.

**L'argument n'est donc pas « il faut une icône ».** Une icône de Dock se pose à
l'exécution avec `NSApp.applicationIconImage`, sans aucun bundle.

**L'argument est TCC.** Le README documente depuis toujours que l'autorisation
Accessibilité est accordée au terminal parent, que changer de terminal la fait
perdre, et que `doctor` doit deviner quel processus parent la réclame. Un bundle
signé avec un identifiant stable met fin à ça. C'est un défaut de fonctionnement,
pas d'esthétique, et c'est ce qui paie le coût.

**Corollaire honnête à écrire :** le bundle **empire** une chose. Un `.app` non
notarisé téléchargé au navigateur est traité bien plus durement par Gatekeeper
qu'un binaire nu.

### Superseded

- `docs/architecture.md` but n°1 et §« Why Swift » : « ship a single binary […]
  there is no `.app` bundle, no menubar entry, no dock icon ». Les trois clauses
  sont fausses, et les deux dernières l'étaient déjà depuis les waves 2 et 3.
- `Install.swift:10-14` : la justification `SMAppService` perd sa prémisse, et la
  conclusion survit pour quatre raisons différentes.
- La section « TCC quirk worth knowing » du README et de `architecture.md`.

### Pas superseded, contrairement aux apparences

**ADR-0004.** Sa substance est « un `*Store` par concern dans `UserDefaults`,
précédence flag puis choix retenu puis défaut ». Le bundle n'y touche pas. Il
déplace seulement le **domaine** où ces defaults vivent. C'est une conséquence de
migration à ajouter à ADR-0004, pas un renversement.

**ADR-0007**, en partie. Sa conséquence « there is no `.app` bundle, so the main
menu is built in code » perd sa prémisse, mais **le menu construit en code
reste** : un `MainMenu.nib` demande Xcode et `ibtool`, que ce repo n'a pas et ne
veut pas. Seule la justification change, de « il n'y a pas de bundle » à « il n'y
a pas de nib, parce qu'il n'y a pas de projet Xcode ». Un changement d'une ligne
et une correction honnête.

### Conséquences à énumérer

Le domaine de préférences se déplace et demande une migration ; les autorisations
TCC passent du terminal à Plume, ce qui rend `Setup.swift:19` vrai au lieu de
faux ; la signature ad-hoc coûte l'autorisation Accessibilité à chaque mise à
jour ; le chemin navigateur est bloqué par Gatekeeper alors que `curl | sh` ne
l'est pas ; le nom d'autosave du frame de fenêtre est réinitialisé ; `doctor`
passe de cinq à six ou sept checks.
