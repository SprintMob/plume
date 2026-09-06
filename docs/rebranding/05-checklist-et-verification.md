# Checklist, questions ouvertes, vérification

## Checklist branding

Ce qui demande une action ou une décision de l'utilisateur est marqué **(vous)**.
Le reste est exécutable.

### Nom et enregistrements

- [x] `plume` libre sur le `PATH` (contrairement à `dash` et `echo`, qui
      collisionnent avec des binaires système)
- [x] Aucune formule Homebrew `plume` (404 sur formulae.brew.sh)
- [x] Pas de collision dans l'outillage de dictée (contrairement à `mynah`, déjà
      une org ASR sur GitHub)
- [x] Domaine tranché : `plume.sprintmob.com`
- [ ] **(vous)** Créer `github.com/sprintmob/plume` et pointer `origin` dessus
- [ ] **(vous)** Trancher fork GitHub contre dépôt neuf
- [ ] **(vous)** CNAME `plume.sprintmob.com`, indépendant de `www` qui reste sur
      Framer, sur le modèle déjà retenu pour `aws.sprintmob.com`
- [ ] **(vous)** Hors périmètre mais visible : le profil GitHub de l'org annonce
      encore `www.sprintmob.fr`

### Identité visuelle

- [ ] `Style.swift` remplacé par le jeu de tokens, les dix `hc-*` repris un pour un
- [ ] `KeyCap` perd son `design: .rounded`, qui est une deuxième police dans un
      seul contrôle
- [ ] Glyphe menu bar : **taille de corps redessinée**, écart passant de 12,5% à
      50% de la hauteur de barre. Au ratio d'origine il vaut 0,52pt et les deux
      barres fusionnent
- [ ] **(vous)** Vérifier sur appareil que `NSImage(data:)` décode bien le SVG
      inliné. `configureButton` fait `button.image = ...` sans titre ni tooltip
      de repli, donc un décodage raté donne un item de menu bar **vide et
      silencieux**. Si ça échoue, tracer en `NSBezierPath`, ce qui donne en prime
      le calage sur la grille de pixels
- [ ] Icône d'app : squircle `#0A0A0A`, filet `hc-line`, mark lime. `.icns` via
      `iconutil`, **commité**, et les tailles ≤ 64px rendues depuis la version à
      écart ouvert. Variante inverse lime pour le README
- [ ] La bulle refaite : filet de 1pt, 5 barres penchées, état d'échec, état de
      transcription qui cesse d'être un spinner système
- [ ] **Deux bugs de la bulle, indépendants de la marque** : `hide()` coupe
      l'animation à 60%, et la bulle n'a aucun bord sur fond sombre
- [ ] Panneau de repli sur les tokens `Dark`, plus le bug `NSScreen.main` qui
      peut l'afficher sur un autre écran que la bulle
- [ ] Fenêtre de réglages : puces de sidebar en lime, marqueur « recommandé » en
      pastille au lieu d'une étoile invisible en clair, docteur inchangé
- [ ] Capture animée de la bulle en action pour le README, c'est ce que les gens
      regardent en premier

### Écrit

- [ ] Toutes les chaînes visibles réécrites dans la voix SprintMob : phrases
      courtes, pas de tiret cadratin. **Il y en a cinq aujourd'hui**
- [ ] **Deux corrections de fond, pas de style** : une remédiation du docteur dit
      « hold Fn » alors que la fonction reçoit déjà la touche choisie, et deux
      autres disent d'activer la permission « for your terminal », ce que le
      bundle rend faux
- [ ] README refait, en-tête de marque et commande d'installation en évidence
- [ ] `CONTEXT.md` : le glossaire dit « parrot » jusque dans ses propres termes,
      et gagne deux entrées, **bundle d'app** et **shim CLI**. Les entrées
      **Upstream** et **Wave** ne bougent pas : elles décrivent l'histoire
- [ ] ADR-0008 actant le bundle `.app`, et disant que `SMAppService` est rouverte
      puis **refusée pour d'autres raisons qu'avant**
- [ ] `docs/architecture.md` : le but n°1 et trois non-goals deviennent faux
- [ ] `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, templates d'issue, `SECURITY.md`

### Attribution et licence

- [ ] `LICENSE` : deux lignes de copyright au-dessus d'un corps MIT inchangé.
      Andrew Jones reste, SprintMob s'ajoute
- [ ] `NOTICE` créditant les **8 auteurs dont le code est dans l'arbre**, nommés,
      avec leurs numéros de PR
- [ ] Section « lignée » du README : 25 PR ouvertes, 16 mergées, et la phrase qui
      rend la section crédible
- [ ] **(vous)** `THIRD-PARTY.md` et `Contents/Resources/ACKNOWLEDGEMENTS.txt` :
      l'obligation Apache-2.0 de `swift-argument-parser` n'est pas honorée
      aujourd'hui
- [ ] **(vous)** Vérifier les licences de `argmax-oss-swift` et `FluidAudio`.
      **Bloquant pour la publication**, indépendamment du rebranding
- [x] Décidé : crédit dans le repo, aucun message envoyé aux auteurs. Le crédit
      doit donc être **visible sans être cherché**

### Distribution

- [ ] `release.yml` produit un `.app` en **zip via `ditto`**, plus son `sha256`.
      Zip et pas tar.gz parce que `notarytool` n'accepte que zip, pkg ou dmg
- [ ] **La CI de tests qui n'existe pas.** Trois lignes de YAML, et c'est ce qui
      rend « chaque commit compile isolément » vérifiable au lieu qu'espéré
- [ ] `install.sh` : `ditto -x -k` et non `unzip`, `xattr -dr` **récursif**
      (aujourd'hui `-d` sur un seul fichier), `codesign --verify` avec un vrai
      message d'erreur
- [ ] Avertissement Gatekeeper honnête dans le README, en deux points
- [ ] Une histoire de désinstallation, que `plume install --uninstall` imprime
- [ ] Page d'atterrissage hébergeant `install.sh`
- [ ] **(vous)** Signature : l'étape trousseau et `codesign` doit être lancée par
      vous, jamais par un agent
- [ ] **(vous)** Le garde-fou `cdhash` de `install-local.sh:45-52` doit survivre
      mot pour mot à la réécriture : il prouve que l'autorisation tiendra au
      prochain build
- [ ] Migration testée sur votre machine : `du -sh` avant et après, et confirmer
      que le déplacement a pris des millisecondes et non des minutes. S'il prend
      des minutes, ce n'est pas un `rename(2)` et la précondition « même volume »
      a échoué
- [ ] Tag `v0.1.0`

## Questions ouvertes

Trois se tranchent par une expérience courte, trois demandent une décision.

| Question | Ce qui la tranche | Ce qu'elle change |
|---|---|---|
| `Bundle.main` résout-il à travers un lien symbolique jusqu'au `.app` ? | Afficher `Bundle.main.bundleIdentifier` appelé des deux façons | Shim contre lien symbolique, et surtout si le domaine de préférences peut se scinder en deux |
| TCC redemande-t-il l'autorisation quand une app signée change de chemin ? | Déplacer `~/Applications/Plume.app` vers `/Applications` et observer | La destination par défaut de `install-local.sh` |
| Les deux bundles de ressources SwiftPM gênent-ils `codesign --strict` ? | Le lancer ; si oui, les signer de l'intérieur d'abord | Une ligne dans `bundle.sh` |
| **(vous)** SprintMob possède-t-il déjà un préfixe reverse-DNS ? | La liste des App ID de l'équipe | L'identifiant de bundle, donc le label launchd, donc le domaine de préférences. **Le changer après une release coûte une deuxième migration** |
| **(vous)** Où héberger `install.sh` ? | Décision | Page sur le domaine, ou `raw.githubusercontent` qui ne demande aucun setup |
| **(vous)** Fork GitHub ou dépôt neuf ? | Décision | Bannière « forked from » contre Issues et Actions actifs par défaut |

Une quatrième, seulement quand un Developer ID existera : le runtime durci
interagit-il mal avec le `CGEventTap` ou le mmap CoreML des poids ? Vérifiable
sur appareil, sans objet avant.

## Ce qui n'est délibérément pas fait

Les specs de ce repo ferment toujours leur périmètre.

- **Pas de notarisation Apple.** Elle demande un compte Developer payant et un
  identifiant d'équipe. On livre une app signée ad-hoc et un `install.sh` qui
  déquarantaine, et le README le dit franchement. Les deux paliers sont
  néanmoins écrits dans `release.yml` dès maintenant, le second conditionné à
  l'existence du secret.

  À noter pour quand la question se reposera : **l'argument pour acheter un
  Developer ID n'est pas Gatekeeper, c'est TCC.** Une signature ad-hoc s'ancre
  sur le `cdhash`, donc chaque release fait perdre l'autorisation Accessibilité.
  Un certificat Developer ID s'ancre sur l'équipe. C'est un défaut de
  fonctionnement récurrent contre un coût annuel, pas une question de confort à
  l'installation.
- **Pas de formule Homebrew.** Le nom est libre côté `brew`, donc l'option reste
  ouverte, mais un tap est une surface de distribution de plus à maintenir avant
  d'avoir un seul utilisateur.
- **Pas de traduction.** L'app est en anglais, la page aussi. La voix SprintMob
  est définie en français pour un site français ; ce sont ses règles d'écriture
  qu'on reprend, pas sa langue. Un outil de dictée publié sur GitHub s'adresse à
  des développeurs, et le README actuel est déjà en anglais.
- **Pas d'Euclid Circular B dans le binaire**, faute de licence établie pour cet
  usage. Si elle est un jour éclaircie, le mécanisme est un
  `CTFontManagerRegisterFontsForURL` au lancement, et le jeu de tokens est écrit
  avec une fabrique `Style.font` unique pour que ce changement ne touche qu'une
  fonction.
- **Pas de teinte d'état sur le glyphe de menu bar.** Techniquement possible,
  mais la menu bar suit l'apparence système et le lime y serait à 1,13:1 la
  moitié du temps.
- **Pas d'implémentation de Escape-cancel.** Ses tests sont sortis en c0 et
  repris après. Les fondre dans le rebranding ferait un lot où plus rien n'est
  bisectable.
- **Pas de refonte du parcours de premier lancement.** `plume setup` reste du
  texte de terminal.
- **Pas de nouvelle capacité.** Comme pour la fenêtre de réglages, le rebranding
  ne doit rien ajouter que le démon ne sache déjà faire. Les deux exceptions sont
  assumées et petites : l'état d'erreur de la bulle, qui rend visible un échec
  aujourd'hui muet dans stderr, et l'ancrage TCC, qui est le but du bundle.

## Vérification

Le repo ne teste aucune UI, et ce plan ne change pas cette règle. Ce qui est
testable automatiquement est étroit ; le reste se valide sur l'appareil.

### Ce que la machine vérifie

1. **Le point de départ est vert.** Après c0 : `swift build -c release` et
   `swift test` passent, 66 tests. Sans ça rien n'est mesurable.
2. **Chaque commit compile isolément.** Un commit par répertoire `.scratch/`,
   chacun vérifié seul, comme lors du dernier lot de quatre.
3. **La CI de tests, qui n'existe pas aujourd'hui**, rend le point 2 exécutable
   au lieu qu'aspirationnel.
4. **Le renommage n'a rien laissé.** `grep -ril parrot` sur les sources, scripts
   et docs ne doit plus rendre que les mentions volontaires : les chemins
   `/tmp/parrot.*.log`, la ligne d'origine du README, le `NOTICE`, ADR-0001, le
   remote `upstream`, et toute l'histoire dans `.scratch/` et `docs/adr/`.
5. **Les tests qui encodent le nom suivent.** `DoctorLaunchAgentTests` assert le
   label launchd et une chaîne de remédiation mot pour mot : ils échouent
   bruyamment si un seul des deux côtés bouge.
6. **Le contraste.** Un test unitaire calculant le ratio des paires de tokens,
   qui échoue si un texte lime se retrouve sur un fond clair. La règle vient de
   la marque, autant la rendre exécutable plutôt que de la laisser en
   commentaire. C'est aussi la culture d'ingénierie que le blueprint AWS
   affiche : « toute modification des constantes doit rejouer ces cas ».
7. **La migration**, contre un répertoire temporaire, via la structure de chemins
   injectable.
8. **`plutil -lint`** sur l'`Info.plist` généré.

### Ce qui demande l'appareil

Rien du chrome ne s'exerce sans démon signé et lancé, exactement comme pour la
fenêtre de réglages (`.scratch/settings-window/issues/06-validation-sur-appareil.md`).

1. **La signature, par vous.** L'étape trousseau et `codesign` ne passe pas par
   un agent.
2. **L'item de menu bar apparaît vraiment.** C'est le point le plus fragile :
   sans titre ni tooltip de repli, un glyphe qui ne se décode pas donne un item
   vide et silencieux. Vérifier en clair et en sombre, en 1x et en 2x, et que
   l'écart inter-barres ne s'est pas refermé.
3. **La bulle, dans ses cinq états** : au repos, en dictée, verrouillée, en
   transcription, **et en erreur** puisque c'est l'état neuf. Au-dessus d'une
   fenêtre claire **et** d'une fenêtre sombre, ce dernier cas étant celui que le
   filet existe pour régler, et par-dessus une app en plein écran, puisque c'est
   ce que le niveau `.screenSaver` sert à couvrir.
4. **Le panneau de repli**, déclenché en dictant dans une zone non éditable, et
   sur un poste multi-écran pour le bug `NSScreen.main`.
5. **La fenêtre de réglages** en apparence claire **et** sombre, les cinq
   sections. C'est là que le lime se casse la figure si la règle de fond clair
   n'a pas été respectée.
6. **La migration, en conditions réelles.** Les modèles ne sont pas
   re-téléchargés, l'ancien job launchd a disparu, les réglages retenus ont
   survécu, et `plume doctor` passe au vert.
7. **L'autorisation Accessibilité s'ancre sur l'app.** C'est la raison d'être du
   bundle : changer de terminal ne doit plus la faire perdre. Vérifier en plus
   que `codesign -d -r-` montre `identifier` **et** `certificate leaf`, puis
   rebuild deux fois et confirmer que l'autorisation survit. Si elle ne survit
   pas, la signature s'est ancrée sur le `cdhash` et le garde-fou du script a été
   perdu dans la réécriture.
8. **Le micro.** Un `.app` sans `NSMicrophoneUsageDescription` est tué par TCC.
   À exercer explicitement, en révoquant d'abord l'autorisation.
9. **Le double-clic sur `Plume.app`.** LaunchServices lance le binaire sans
   argument, et ArgumentParser sort en erreur sur tout argument inattendu.
10. **Une installation propre**, depuis l'URL publique, sur un compte macOS neuf
    si possible : c'est le seul moyen de voir ce que Gatekeeper fait vraiment à
    un `.app` non notarisé, et de distinguer le chemin `curl` du chemin
    navigateur.
