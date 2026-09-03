# Le hotkey et le mode d'injection se retiennent, et se changent en menu bar

Status: ready-for-human

Premier code écrit par le fork, et non un merge. Ferme les deux angles morts que la
vague 2 avait ouverts, et finit ce qu'[ADR-0003](../../docs/adr/0003-hotkey-cluster-base.md)
avait laissé de #7. Environ 300 lignes, dont 150 de tests.

Point de départ : `main` @ `e3fcc98`, c'est-à-dire la vague 3 complète.

## Pourquoi ce n'est pas un merge

#7 (adpadillar) est supersédée telle qu'écrite — son enum `Hotkey` et son
`--hotkey` sont arrivés par #4 greffée sur #10 en vague 2, et son auteur la signale
lui-même comme du code généré non relu. ADR-0003 avait gardé le reste vivant :

> ses idées de persistance et de menu bar valent d'être réécrites sur cette base
> plutôt que fusionnées.

Deux vagues plus tard c'était toujours l'angle mort n°1 de la vague 2. C'est donc
une réécriture sur la base actuelle. [ADR-0001](../../docs/adr/0001-fork-rather-than-contribute-upstream.md)
réserve le code neuf exactement à ce cas.

## Ce qui a été fait

| Fichier | Apport |
|---|---|
| `Sources/parrot/SettingsStore.swift` | nouveau — `hotkey` et `injectMode` en `UserDefaults` |
| `Input/HotkeyMonitor.swift` | `mask`/`keycode` mutables, `setHotkey(_:)` |
| `UI/MenuBarController.swift` | sous-menus **Push-to-talk key** et **Injection** |
| `Parrot.swift` | résolution par le store, câblage `onHotkey` |
| `Install.swift` | ne grave plus les deux flags dans le plist |
| `Doctor.swift` | contrôle fn conditionnel, contrôle du launch agent |

Le store ne réinvente rien : il copie `ModelStore` (#21) et `InputDeviceStore`
(#14), mêmes `UserDefaults` injectables, même précédence `flag → retenu → défaut`,
même tolérance à une valeur stockée qui ne se relit plus. Les deux motifs de menu
déjà en place sont réutilisés chacun là où il tombe juste : le rappel `onModel`
pour le hotkey, parce qu'un tap vivant doit être prévenu ; l'écriture directe
d'`inputSelected` pour le mode d'injection, relu à chaque injection.

## Décisions

### Trois orthographes possibles, celle qui tourne déjà l'emporte

`docs/architecture.md` spécifiait un TOML en `~/.config/parrot/config.toml`, jamais
écrit ; #7 proposait `UserDefaults` par un static codé en dur ; #26 propose un JSON
en `~/Library/Application Support/parrot/`. Le choix était déjà fait par la file de
merge — #21 et #14 ont livré `UserDefaults` — et [ADR-0004](../../docs/adr/0004-settings-in-userdefaults.md)
l'acte, plutôt que de laisser apparaître une quatrième orthographe.

### Le plist ne grave plus rien

C'est le cœur du correctif, pas un détail. `parrot install` gravait `--hotkey` et
`--inject-mode` dans les `ProgramArguments` ; un flag y gagne à chaque lancement,
donc il aurait défait en silence tout choix fait en menu bar — précisément pour les
utilisateurs daemonisés à qui la menu bar sert. L'argv devient
`[binary, "run", "--skip-doctor"]` et `install --hotkey X` enregistre le choix.

Les agents écrits par les versions précédentes portent encore les flags. Comme rien
ne le signalerait, `parrot doctor` gagne un contrôle `launch agent` qui prévient et
dit de relancer l'install — le même motif que `checkLegacyLogs`.

### Un clic en menu bar bat le flag de lancement

Sinon, sous install daemonisée, choisir dans le menu n'aurait eu aucun effet
visible. Le flag est la valeur de départ, pas un verrou.

### Le contrôle fn devient conditionnel, et c'est un bug fermé au passage

`checkFnKeyMapping` tournait sans condition et ses cas `.fail` gardent le
démarrage : avant ceci, un utilisateur sous `--hotkey right-option` pouvait se voir
refuser un lancement à cause d'une touche que parrot ne regardait pas.

### Changer de modificateur ne reconstruit pas le tap

Le tap reçoit déjà tous les `flagsChanged` ; seule la comparaison dans `handle()`
dépend du choix. `setHotkey` échange les deux champs et, si une touche était tenue,
réutilise l'événement `.interrupted` existant — celui de `reEnable()`, que
`FnDictationGesture` sait déjà annuler — pour qu'un enregistrement commencé sous
l'ancien modificateur ne reste pas ouvert.

## Vérification

Swift 6.3 / Xcode 26.4, arm64. Pas de job de test en CI — `.github/workflows` ne
tient qu'une release — donc tout en local.

- `swift build` : OK après chacune des six étapes ; `swift build -c release` : OK
- `swift test` : **21/21**, contre 5 avant. `SettingsStoreTests` (6),
  `DoctorLaunchAgentTests` (5) et `InstallUmaskTests` (5) ; les deux premiers sont
  les premiers tests d'un store du dépôt — `ModelStore` et `InputDeviceStore` n'en
  ont toujours aucun
- `parrot run --help` : `--hotkey` et `--inject-mode` listent toujours leurs 9 et 2
  valeurs ; le `(default:)` a disparu — les options sont devenues optionnelles pour
  qu'un flag absent se distingue d'un flag passé à sa valeur par défaut, ce qui est
  déjà la raison pour laquelle `--model` est un `String?` — et la discussion nomme
  le défaut retenu à la place
- `parrot run --hotkey nope` : toujours rejeté avec la liste des valeurs
- `parrot install --help` : les deux options disent « remember as the default »

**Le point porteur, celui dont tout dépend, a été vérifié pour de vrai :** que le
binaire lise bien un `UserDefaults` persistant. `defaults read parrot` contenait
déjà `modelID = whisper-large-v3-turbo`, écrit par un vrai run via `ModelStore` —
donc le domaine existe, porte le nom du process, et sert depuis la vague 2. En y
écrivant `hotkey = right-option`, `parrot doctor` a perdu son contrôle `fn key
mapping` ; la clé a été retirée ensuite et le domaine rendu à son état d'origine.
Les trois vagues listaient ce point en « non exercé » ; il ne l'est plus.

Le contrôle `launch agent` a d'abord été testé en déplaçant `HOME`, ce qui ne
prouve rien : `homeDirectoryForCurrentUser` passe par `getpwuid` et ignore `HOME`,
vérifié séparément. Le contrôle prend donc maintenant son URL en paramètre — le
défaut restant le chemin réel — et ses cinq cas sont couverts par des plists
temporaires. Le plist réellement installé sur la machine date du 20 août, ne porte
ni `--hotkey` ni `--inject-mode`, et ressort `ok` à juste titre.

**Le daemon a tourné, pour la première fois dans ces quatre passes.** Binaire signé
par `scripts/install-local.sh` (exigence ancrée sur la feuille du certificat, donc
le grant d'Accessibilité survit), plist régénéré, agent relancé : `listening on fn
hold · model: whisper-large-v3-turbo`, puis des dictées réelles transcrites
(`○ captured 3.10s` → `→ 1.73s · 32 chars`). Le plist ne porte plus que
`[binary, run, --skip-doctor]` — le `--model` gravé par une version antérieure est
parti avec, donc un changement de modèle en menu bar tient désormais au login.

**Non exercés malgré ça** : les sous-menus eux-mêmes, le changement de modificateur
en vol, et la remise à zéro par `.interrupted` pendant une dictée verrouillée. Ils
demandent de cliquer dans la menu bar. Le reste — build, 21 tests, surface CLI,
round-trip du store, warmup et dictée bout en bout — l'est.

## Un défaut de la vague 1 trouvé en installant pour de vrai

La réinstallation a sorti un bug qui dormait dans le code fusionné en vague 1, sans
rapport avec #7 mais découvert par sa vérification.

`Install.swift` posait `plist["Umask"] = 127`, c'est-à-dire `0o177`. Le commentaire
dit vouloir un log en 0600 si launchd le recrée, et c'est bien ce que ça donne pour
un **fichier** — mais le Umask du launch agent s'applique à tout ce que le process
crée, **répertoires compris**, et `0o777 & ~0o177` vaut `0600` : un répertoire sans
bit d'exécution, dans lequel on ne peut donc rien écrire.

Conséquence observée sur une vraie install : WhisperKit crée
`TextDecoder.mlmodelc` en `drw-------`, échoue à y écrire (`EACCES`), le warmup
part en erreur, `Run.run()` sort en 1, et `KeepAlive` relance en boucle. C'est
exactement le scénario B2 + `ThrottleInterval` que la vague 1 avait listé en angle
mort, déclenché ici par une seule valeur octale.

La bonne valeur est `0o077` (63) : mêmes `0600` pour les fichiers, `0700` pour les
répertoires. Corrigé, sorti dans une constante nommée `Install.logUmask`, et
couvert par `InstallUmaskTests` — dont un cas garde explicitement le bit
d'exécution propriétaire, puisque c'est la seule chose qui distinguait les deux
valeurs.

Le défaut ne se déclenche qu'avec `--log-file`. Les agents installés sans lui n'ont
pas de clé `Umask` et n'ont jamais été touchés, ce qui explique qu'il ait survécu à
trois vagues.

## Ce que ça ne règle pas

Des huit angles morts connus, deux se ferment ici (persistance du hotkey, et le
mode d'injection avec). Restent ouverts les six du 20 août : migration des modèles
existants, warmup non fatal (B2), `ThrottleInterval` dans le plist, rotation et
plafond du log, `parrot --version`, état réel dans `models list`. Plus la migration
du turbo compressé, ouverte par la vague 2.

Trois limites propres à cette passe :

1. **Le plist installé n'est pas réécrit tout seul.** Qui met à jour le binaire
   sans relancer `parrot install` garde un agent sans les flags gravés seulement
   s'il datait d'avant qu'ils le soient ; sinon `doctor` prévient, mais ne corrige
   pas.
2. **`--model` reste gravé** dans l'agent installé sur cette machine, écrit par une
   version antérieure. `Install.swift` ne l'écrit plus, mais rien ne le retire.
3. **La bannière de démarrage** nomme le modificateur de lancement. La ligne de
   verrouillage, elle, suit le choix courant.

#7 peut être considérée comme traitée, adpadillar crédité pour le diagnostic et la
forme. **#26 reste ouverte**, et l'arbitrage qu'ADR-0002 voulait immédiatement
après la vague 1 en est maintenant à quatre passes de retard : `ParrotSettings`, sa
propre orthographe du même besoin, est ce qu'ADR-0004 écarte.
