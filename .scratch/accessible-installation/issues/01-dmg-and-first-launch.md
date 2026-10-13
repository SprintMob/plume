# Distribution par DMG et premier lancement guidé

Status: ready-for-human

Implementation: complete and independently reviewed

Implémenter le parcours approuvé dans [la spécification](../spec.md) puis obtenir
une review indépendante. La publication signée et la validation sur compte Mac
vierge restent conditionnées aux accès Apple nécessaires.

## Comments

- 2026-10-13 : l'utilisateur a demandé un agent d'implémentation et un agent de review.
- 2026-10-13 : implémentation et review indépendantes terminées. La review a fait
  corriger l'état de touche retenu après perte d'autorisation et les statuts
  trompeurs d'un modèle chargé sans autorisation. Les 113 tests Swift et quatre
  contrôles de distribution passent ; bundle, ZIP et DMG locaux vérifiés.
- La publication signée et la validation sur compte Mac vierge sont suivies dans
  [le ticket 02](02-signed-public-release.md).
