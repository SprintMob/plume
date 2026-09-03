# 03 — La coquille : NSWindow, menu principal, bascule d'activation

Status: ready-for-human

`SettingsWindowController` — `NSWindow` 900×620, titlebar transparente,
`NSHostingController` (et non `NSHostingView` comme l'overlay : c'est une vraie
fenêtre avec un premier répondeur), taille et position mémorisées.

Deux choses non évidentes :

1. **La bascule `.accessory` → `.regular`.** Sans elle, pas de ⌘C, ⌘V, ⌘W. Retour
   en `.accessory` sur `windowWillClose`.
2. **Le menu principal est construit en code.** Il n'y a pas de bundle `.app`, donc
   pas de MainMenu.nib, et `.regular` afficherait une barre vide. App / Edit /
   Window, dont les quatre commandes d'édition qui sont la raison d'être de tout ça.

L'activation est reportée d'un tour de runloop : AppKit ne reconstruit pas toujours
la barre de menus de façon synchrone après un changement de politique.

Implémenté. Voir `spec.md`.
