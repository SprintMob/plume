# La marque, la lignée, la licence

Status: ready-for-human

Huitième et dernière feature du programme de `docs/rebranding/`. En dernier
parce qu'elle montre le résultat, donc elle a besoin que le résultat existe.

## L'obligation qui n'était pas honorée

Le plan la listait comme **bloquante** et non vérifiée. Vérifiée maintenant, en
lisant les fichiers de licence dans `.build/checkouts` :

| Composant | Licence | Détenteur |
|---|---|---|
| `swift-argument-parser` 1.7.1 | **Apache-2.0** | The Swift project authors |
| `argmax-oss-swift` (WhisperKit) | **MIT** | (c) 2024 argmax, inc. |
| `FluidAudio` 0.15.5 | **Apache-2.0** | FluidInference |

Le plan supposait une seule obligation Apache-2.0. Il y en a **deux**, plus une
troisième transitive : `argmax-oss-swift` vendorise du code dérivé de
`huggingface/swift-transformers` (Apache-2.0) sous `Sources/ArgmaxCore/External`
et porte un fichier `NOTICES` que l'article 4(d) demande de propager.

L'article 4 exige que la licence et toute NOTICE voyagent avec les
distributions « in Source **or Object** form ». Un binaire lié statiquement est
de la forme objet, donc l'obligation s'attache à l'artefact de release, et
aucune release jusqu'ici ne la portait.

`scripts/third-party.sh` génère `THIRD-PARTY.md` depuis les checkouts, et
`bundle.sh` le copie en `Contents/Resources/ACKNOWLEDGEMENTS.txt`. Une source,
deux destinations, aucune dérive possible.

## Le crédit, et le compte honnête

**MIT exige que la notice de copyright soit conservée.** On ajoute une ligne, on
ne remplace pas : deux lignes de copyright au-dessus d'un corps MIT inchangé,
Andrew Jones et SprintMob. C'est la forme standard et non controversée.

Le `NOTICE` crédite **8 auteurs**, nommés, avec leurs numéros de PR, plus
`bdeol2` listé à part parce que son analyse a servi et pas son patch.
**25 PR ouvertes upstream, 16 mergées, 8 auteurs distincts.** Créditer 25
auteurs serait généreux et **faux**, et le NOTICE est le document qui affirme la
provenance.

La décision prise est : **crédit dans le repo, aucun message envoyé aux
auteurs.** ADR-0001 faisait de ces auteurs un levier assumé pour attirer des
contributeurs. Puisque le message est écarté, le repo est le **seul** canal,
donc le crédit doit être lisible sans être cherché. D'où les huit noms dans le
README, en section « Lineage », au-dessus du reste, et la phrase qui rend la
section crédible : « SprintMob publishes it; SprintMob did not write most of
it. »

## Le README, réordonné

Il était bon mais il s'adressait à quelqu'un qui avait déjà décidé. En open
source c'est la vitrine. Le nouvel ordre : le nom et le glyphe, la commande, la
lignée, l'avertissement Gatekeeper, puis l'usage, puis la référence CLI.

La règle de voix s'applique : phrases courtes, pas de tiret cadratin (il n'en
reste aucun), les chiffres avant les promesses. Le chiffre disponible est la
latence, moins de 500 ms après le relâchement, et c'est lui qui remplace les
adjectifs.

L'avertissement Gatekeeper est écrit en deux points parce que la moitié de ce
que les gens croient sur le sujet est faux, et parce que le second point est
celui qui coûte vraiment : **chaque mise à jour fait perdre l'autorisation
d'Accessibilité**, et c'est l'argument pour acheter un Developer ID, pas
Gatekeeper.

## La page

`plume.sprintmob.com`, sur le modèle d'`aws.sprintmob.com` : projet séparé,
CNAME indépendant, aucune interaction avec `www` qui reste sur Framer.

Son travail est de faire tourner **une seule commande**, donc la commande est le
plus gros élément interactif de la page et un clic la copie. Pas de grille de
features, pas de témoignage : ce n'est pas une page de vente, c'est une page
d'installation.

`scripts/install.sh` y est copié **au déploiement** plutôt que commité sous
`site/`, pour que le fichier que les gens passent à un shell et celui du repo ne
puissent pas diverger.

Trois défauts trouvés en la regardant vraiment dans un navigateur, et corrigés :
la commande était tronquée au lieu de passer à la ligne, le `<img>` du GIF
absent cassait la mise en page, et le mark à 72px est **sous le seuil** où
l'écart entre les deux barres se referme, donc il utilise la coupe à écart
ouvert, exactement comme l'icône aux tailles ≤ 64px.

Euclid Circular B n'est pas servie non plus : aucune licence web n'est établie
et la page est publique.

## Une erreur de ma part, corrigée

Le commit du paquet affirmait copier deux bundles de ressources SwiftPM dans
`Contents/Resources/` et présentait ça comme un crash latent supprimé.
**C'était faux.** `swift-crypto_Crypto.bundle` et `swift-transformers_Hub.bundle`
étaient des artefacts périmés dans `.build`, datés du 2026-08-24, laissés par
une révision plus ancienne d'`argmax-oss-swift`. Le graphe actuel rend trois
paquets, n'émet aucun bundle de ressources, et rien dans les cibles liées
n'appelle `Bundle.module`. Vérifié en les supprimant et en rebuildant.

La rétractation est écrite dans ADR-0008, dans `.scratch/paquet-app/spec.md`, et
dans le plan d'origine `docs/rebranding/03`, qui portait la même erreur mesurée
sur les mêmes artefacts. La boucle de copie reste dans `bundle.sh`, sans
prétendre corriger quoi que ce soit.

## Fichiers de communauté

`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, deux templates d'issue.

Chacun dit quelque chose que ce projet a de particulier plutôt que de recopier
un gabarit. CONTRIBUTING explique que l'essentiel du code vient de PR non revues
et que c'est **pour ça** que la revue ici n'est pas une formalité. Le code de
conduite dit la même chose autrement : quoi qu'il arrive, personne n'aura ici
l'expérience des 25 PR laissées quatre mois sans réponse. SECURITY liste ce qui
est déjà connu et n'est pas une vulnérabilité, ce qui évite trois rapports
inutiles. Le template de bug demande la sortie de `plume doctor`, qui est de
loin la chose la plus utile dans un rapport sur cette app.

## Vérification

- `swift build -c release` et `swift test` : 94 tests, 0 échec.
- `./scripts/check-rename.sh` : vert.
- `bash -n` sur les six scripts, `yaml.safe_load` sur les trois workflows.
- Aucun lien relatif cassé dans les six documents markdown de la racine.
- `bundle.sh` embarque `ACKNOWLEDGEMENTS.txt`, `plume.icns` et un `Info.plist`
  qui passe `plutil -lint`. Le paquet fait 7,3 Mo, ce qui est le chiffre écrit
  sur la page.
- **La page a été regardée dans un navigateur**, en haut et en bas, et les trois
  défauts trouvés là ont été corrigés.

## Ce qui reste à vous

- **Créer `github.com/sprintmob/plume`** et y pointer `origin`. Trancher fork
  GitHub contre dépôt neuf : la recommandation est un dépôt neuf, parce qu'un
  fork arrive avec Issues et Actions désactivés et chaque PR visant l'upstream
  par défaut, et parce que le NOTICE et la section lignée en disent de toute
  façon plus que la bannière « forked from ».
- **Le CNAME `plume.sprintmob.com`** et activer GitHub Pages sur le dépôt.
- **Enregistrer la démo animée.** C'est ce que les gens regardent en premier, et
  c'est le seul trou volontaire de la page et du README.
- **Vérifier que `security@sprintmob.com` et `conduct@sprintmob.com` existent**
  avant publication : un SECURITY.md qui pointe vers une boîte morte est pire
  que pas de SECURITY.md.
- **Le préfixe reverse-DNS.** `com.sprintmob.plume` est gravé dans
  `packaging/Info.plist.in`. Si l'équipe publie déjà sous `io.` ou `app.`, le
  changer **maintenant** coûte une ligne ; le changer après une release coûte
  une deuxième migration aux utilisateurs.
