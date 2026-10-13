# Configurer la signature Apple et publier le DMG

Status: ready-for-human

Le compte Apple Developer est actif, mais aucun certificat Developer ID Application
ni secret MACOS_* n'est actuellement disponible dans ce projet. La release publique
v0.1.0 porte une signature ad hoc ; elle ne valide pas le parcours navigateur.

## Prérequis Apple à configurer de façon sécurisée

Dans les secrets GitHub Actions de SprintMob/plume :

- MACOS_CERTIFICATE_P12 : certificat **Developer ID Application** avec sa clé privée,
  exporté en .p12 protégé par mot de passe, puis encodé en base64.
- MACOS_CERTIFICATE_PASSWORD : mot de passe de cet export.
- MACOS_SIGN_IDENTITY : identité Developer ID Application correspondante.
- MACOS_NOTARY_APPLE_ID : identifiant Apple autorisé à notariser.
- MACOS_NOTARY_TEAM_ID : identifiant de l'équipe Apple Developer.
- MACOS_NOTARY_APP_PASSWORD : mot de passe spécifique à l'application.
- MACOS_NOTARY_PROFILE : nom du profil que le runner crée dans son trousseau temporaire.

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
