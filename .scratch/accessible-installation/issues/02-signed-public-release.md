# Configurer la signature Apple et publier le DMG

Status: ready-for-human

Le compte Apple Developer est actif. Le certificat Developer ID Application de
SprintMob est créé, sa chaîne Apple G2 est reconnue par macOS et sa clé publique
correspond à la clé privée préparée. L'export P12 protégé reste dans un répertoire
temporaire privé. Les six secrets de signature et de notarisation API sont configurés
et leurs noms vérifiés dans GitHub Actions SprintMob/plume. La release publique
v0.1.0 porte une signature ad hoc ; elle ne valide pas le parcours navigateur.
Les artefacts 0.2.0 locaux sont maintenant signés Developer ID, notarizés et
agrafés. Gatekeeper les accepte. La validation du téléchargement navigateur et
de la première dictée sur un compte vierge précède encore la publication stable.

Le candidat public est disponible :
https://github.com/SprintMob/plume/releases/tag/installation-preview-0.2.0.
Son téléchargement via Chrome conserve la quarantaine navigateur ; son SHA256,
son ticket Apple et son acceptation Gatekeeper ont été vérifiés. Il reste la
première installation/dictée sur un compte Mac vierge avant la release stable.

## Prérequis Apple à configurer de façon sécurisée

Dans les secrets GitHub Actions de SprintMob/plume :

- MACOS_CERTIFICATE_P12 : certificat **Developer ID Application** avec sa clé privée,
  exporté en .p12 protégé par mot de passe, puis encodé en base64.
- MACOS_CERTIFICATE_PASSWORD : mot de passe de cet export.
- MACOS_SIGN_IDENTITY : identité Developer ID Application correspondante.
- MACOS_NOTARY_KEY_ID : identifiant de la clé API d'équipe ASC autorisée.
- MACOS_NOTARY_ISSUER_ID : identifiant de son émetteur.
- MACOS_NOTARY_KEY_P8 : contenu P8 de cette clé API.

MACOS_NOTARY_PROFILE est facultatif et vaut `plume-notary` par défaut. Le chemin
Apple ID/mot de passe spécifique reste disponible en remplacement complet du
trio API ; voir le guide pour les noms des secrets et les règles de sélection.

Ne pas déposer ces valeurs dans le dépôt ou la conversation. Suivre le guide de
distribution livré avec l'implémentation pour leur configuration.

## Après implémentation et review

1. Construire une release candidate signée et notarizée ; vérifier ses signatures,
   tickets et sommes SHA256.
2. Télécharger le DMG dans un navigateur sur un compte Mac vierge. Vérifier
   installation, autorisations, première dictée, réouverture et lancement à la session.
3. Publier la release stable, puis activer le bouton de téléchargement du site.

## Comments

- 2026-10-13 : l'implémentation peut être vérifiée localement sans ces secrets ;
  la publication destinée au grand public en dépend.
- L'utilisateur préfère une récupération/configuration automatique, comme Expo.
  ASC et Fastlane sont installés ; le profil ASC actif utilise déjà une clé API
  stockée dans le trousseau. Pas de session web Apple ni d'identité Developer ID
  locale. Étudier la réutilisation de l'authentification API pour la notarisation,
  plutôt que demander une saisie manuelle de sept secrets.
- Le chemin API est implémenté et approuvé par la review indépendante. Le CSR
  public est chargé dans le portail Apple pour SprintMob, G2 Sub-CA sélectionnée.
  La création du certificat attend la confirmation au moment de l'action exigée
  par l'outil navigateur. Aucun certificat créé ni secret envoyé à GitHub à ce stade.
- Le certificat Developer ID a ensuite été créé après confirmation. Il expire
  le 12 novembre 2027 ; prévoir son renouvellement avant cette date.
- Correction de la sélection ASC : le profil actif `asc` n'appartient pas à
  l'équipe SprintMob (Team ID vérifié sur ses certificats publics). Sa lecture de
  clé a été arrêtée avant export. La demande du trousseau correspondante est
  annulée ; aucun P8 de ce profil n'a été copié.
- Le formulaire App Store Connect SprintMob est prêt pour une clé dédiée
  `Plume Notarization`, rôle Developer, minimum permettant la notarisation.
  Apple ne limite pas les clés d'équipe à une seule app. La création et le dépôt
  des secrets de signature/notarisation dans SprintMob/plume attendent l'accord
  de l'utilisateur affiché au moment de l'action. La version 0.2.0 compile.
- L'utilisateur a approuvé la création et la configuration GitHub. La clé dédiée
  est créée, téléchargée vers le répertoire privé et acceptée par Notary API.
  Les six secrets sont déposés par l'API chiffrée via gh, sans affichage des valeurs.
  Le preflight réel du script passe avec l'authentification API.
- Le test réel a nécessité d'ajouter le trousseau temporaire à la liste de recherche
  macOS. L'app 0.2.0 est maintenant signée Developer ID et vérifiée strictement.
  La review du correctif de release a trouvé la normalisation des alias /tmp et
  /private/tmp à corriger ; fix ciblé en cours. La notarisation complète et les
  vérifications navigateur/compte vierge restent à effectuer avant publication stable.
- Le correctif de trousseau (fc9d7d8, a16f1fa) est approuvé par la review indépendante.
  Le contrôleur a revérifié 23 tests Python, la syntaxe Bash 3.2 et les diffs.
  Le script complet de release 0.2.0 a réussi avec un chemin temporaire /tmp alias :
  signature Developer ID, notarisation Apple Accepted, agrafage et validation de
  l'app puis du DMG, acceptation Gatekeeper et SHA256 ZIP/DMG. Son trousseau et son
  répertoire de travail temporaires ont été retirés. Le candidat peut être publié
  pour les vérifications d'installation restantes ; le bouton stable reste désactivé.
- Le candidat est publié avec DMG, ZIP et leurs checksums ; le tag de preview
  n'active pas le workflow de tags stables v*. La PR brouillon est
  https://github.com/SprintMob/plume/pull/1. Les deux jobs CI de build, tests et
  bundle sont réussis sur 38c717f. Le téléchargement du DMG public dans Chrome a
  été vérifié : quarantaine présente, SHA256 identique, signature/ticket valides,
  Gatekeeper Notarized Developer ID. La demande utilisateur de validation de
  première dictée sur compte vierge reste en attente ; ne pas présumer sa réussite.
