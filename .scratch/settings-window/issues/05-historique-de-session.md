# 05 — L'historique de session

Status: ready-for-human

La seule addition de comportement du lot. `TranscriptHistory` garde les dictées
terminées du run courant : 200 entrées, plus récente en tête, en RAM, vidées au
redémarrage, débrayables.

`grouped` et `filtered` sont statiques et pures, sur un `Calendar` et un `now`
injectés — testables comme `FocusRules`, sans attendre minuit. Le filtre ignore la
casse et les accents, pour que « reglement » trouve « règlement ».

Les transcripts vides sont enregistrés aussi et rendus en italique : une dictée qui
n'a rien produit reste quelque chose que l'utilisateur a fait et veut voir expliqué.

Contredit le non-goal « No history, transcript log » de `docs/architecture.md`.
L'argument est dans [ADR-0007](../../../docs/adr/0007-a-settings-window-and-a-session-history.md) :
[ADR-0006](../../../docs/adr/0006-transcript-always-on-the-pasteboard.md) met déjà
chaque transcript sur le presse-papiers indéfiniment, d'où un gestionnaire de
presse-papiers l'écrira sur disque. Un tableau qui meurt avec le processus est plus
contenu que ça.

Implémenté. Voir `spec.md`.
