# Signature, distribution, et la CI qui n'existait pas

Status: ready-for-human

Quatrième feature du programme de `docs/rebranding/`. Le paquet existe et la
migration aussi ; il reste à le livrer, et à rendre vérifiable la promesse que
chaque commit compile seul.

## Trois mécanismes qu'on confond tout le temps

Le README les mélangeait, comme presque tout le monde.

**(a) L'exigence du noyau.** Un Mach-O arm64 doit porter *une* signature. `ld`
en applique une ad-hoc, `strip` la régénère. Rien à faire.

**(b) Gatekeeper.** Ne s'applique **qu'au code mis en quarantaine**, et c'est le
**téléchargeur** qui la pose. `curl` n'en pose pas. Donc
`curl -fsSL … | sh` n'est pas bloqué, ne l'a jamais été, et ne le sera pas.
Un téléchargement au navigateur l'est, et pour une app signée ad-hoc le message
est **« Plume est endommagé »**, plus dur que le « développeur non identifié »
réservé aux apps Developer ID non notarisées.

**L'énoncé honnête est donc étroit : le chemin navigateur empire, le chemin
`curl | sh` est inchangé.** Le README le dit dans ces termes.

**(c) TCC**, qui n'a rien à voir avec Gatekeeper et qui est le vrai coût. Une
signature ad-hoc ancre l'exigence désignée sur le `cdhash`, donc **chaque
release fait perdre l'autorisation d'Accessibilité**. Le symptôme est vicieux :
la dictée enregistre, transcrit, affiche la bulle, et **cesse silencieusement
d'écrire au curseur**.

**C'est ça, et non Gatekeeper, l'argument pour acheter un Developer ID.** Un
certificat ancre l'exigence sur l'équipe, que tous les builds futurs
satisfont.

## Les deux paliers, tous deux dans le workflow dès maintenant

Le palier 1 est conditionné à `secrets.MACOS_CERTIFICATE_P12 != ''`. L'activer
plus tard est **l'ajout de deux secrets**, pas une réécriture du workflow.
`packaging/plume.entitlements` est déjà là avec la seule clé nécessaire,
`com.apple.security.device.audio-input` : le runtime durci est requis pour la
notarisation, et il bloque le micro sans elle.

## Zip via `ditto`, pas tar.gz

La raison décisive est tournée vers l'avant : `xcrun notarytool` n'accepte que
`.zip`, `.pkg` et `.dmg`. Choisir tar.gz aujourd'hui, c'est réécrire l'étape le
jour où le Developer ID arrive. Secondairement, `--sequesterRsrc` préserve les
attributs étendus où vit le sceau, et `--keepParent` garde `Plume.app` comme
entrée de premier niveau au lieu d'exploser `Contents/` dans le répertoire
courant.

## Deux bugs d'un caractère dans `install.sh`

Ils attendaient depuis le début et deviennent sérieux avec un paquet :

- **`xattr -d` était non récursif.** Un bundle est un répertoire : `-d` sur un
  fichier laisse l'attribut sur tout le reste, c'est-à-dire sur l'essentiel.
  Maintenant `-dr`.
- **`unzip` devient `ditto -x -k`.** Certaines versions d'`unzip` perdent les
  attributs étendus, et le sceau de signature vit dedans.

Plus une ligne qui vaut la peine : `codesign --verify --strict` avant
d'installer. Un bundle corrompu produit « Plume est endommagé », que les
utilisateurs lisent comme « malware ». L'attraper dans l'installeur avec un vrai
message évite ce malentendu.

Et l'installeur détecte une installation parrot et affiche
`plume install --migrate` **avant** que les modèles se re-téléchargent.

## Une histoire de désinstallation

`plume install --uninstall` retirait le launch agent, ce qu'il a toujours
prétendu faire. Avec un vrai `.app`, il reste deux choses sur disque plus un
répertoire de poids. Il les **affiche** maintenant, avec le `sudo` là où il
faut. Affiché et pas exécuté : supprimer une app et plusieurs gigaoctets de
poids est une décision.

## La CI qui n'existait pas

Le repo avait un workflow de release et **aucun workflow de test**. C'est ce qui
rend « chaque commit compile isolément » vérifiable au lieu qu'espéré, et c'est
exactement ce qui aurait attrapé les 116 lignes de tests commitées contre une
API jamais écrite.

Quatre étapes : `swift build -c release`, `swift test`, `./scripts/bundle.sh`,
`plutil -lint`. Plus une cinquième.

### `scripts/check-rename.sh`

Un renommage mécanique a deux modes d'échec, et le script vérifie les deux.

**Il renomme ce qu'il ne fallait pas.** C'est le cas dur, et il est silencieux :
les chemins `/tmp/parrot.*.log` ont été écrits par parrot, la remédiation de
confidentialité qui les trouve est toute la raison pour laquelle ils portent
encore ce nom, et un chemin `plume` là supprimerait cette remédiation pour
exactement les gens qui migrent. Le script assert donc que les littéraux legacy
sont **toujours là**.

**Il en oublie.** La seconde moitié échoue sur tout `parrot` restant **hors
commentaire** : une chaîne, un chemin, un identifiant. Les commentaires sont
sautés exprès, parce qu'après ce travail presque chaque commentaire qui
mentionne parrot est là pour expliquer pourquoi la ligne en dessous a été
laissée tranquille.

## Vérification

- `swift test` : 85 tests, 0 échec.
- `bash -n` sur les cinq scripts, `yaml.safe_load` sur les deux workflows.
- `./scripts/check-rename.sh` : vert.
- `./scripts/bundle.sh --output /tmp/bundlecheck` puis `plutil -lint` : vert.

## Ce qui reste à vous

- **La signature locale.** `scripts/install-local.sh` doit être lancé par vous :
  l'étape trousseau ne passe pas par un agent. Le garde-fou `cdhash` du script a
  survécu mot pour mot à la réécriture ; c'est lui qui **prouve** que
  l'autorisation tiendra au prochain build.
- **Le dépôt `sprintmob/plume`**, vers lequel `install.sh` pointe déjà.
- **Les secrets `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`,
  `MACOS_SIGN_IDENTITY`, `MACOS_NOTARY_PROFILE`**, le jour où le Developer ID
  existe. Rien d'autre à changer.
- **Une installation propre depuis l'URL publique**, sur un compte macOS neuf si
  possible : c'est le seul moyen de voir ce que Gatekeeper fait vraiment, et de
  distinguer le chemin `curl` du chemin navigateur.
