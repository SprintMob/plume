# Annuler une dictée avec Échap

Status: ready-for-agent

**Non implémenté.** Ce fichier existe pour conserver l'intention de 116 lignes
de tests écrits en TDD contre une API qui n'a jamais été ajoutée, et sortis de
`Tests/parrotTests/FnDictationGestureTests.swift` au début du rebranding
`plume` parce qu'ils empêchaient `swift build --build-tests` d'aboutir, donc
rendaient tout le reste invérifiable.

Les tests étaient bons. C'est le seul reproche qu'on peut leur faire : ils
décrivaient exactement la machine à états voulue, et rien ne la fournissait.

Point de départ : `main` @ `0dd69e9`. Les tests sortis sont récupérables par
`git show 0dd69e9 -- Tests/parrotTests/FnDictationGestureTests.swift` sur la
version modifiée non commitée, ou reconstruits depuis ce qui suit.

## La demande

Pendant qu'une dictée est en cours, micro chaud, appuyer sur Échap doit la
jeter. Pas de transcription, pas d'injection, pas de presse-papier. On s'est
trompé, on repart.

C'est le seul chemin par lequel une dictée peut être abandonnée volontairement.
Aujourd'hui la seule sortie est de relâcher la touche et de laisser le
transcript arriver au curseur, puis de le supprimer à la main.

## L'API manquante

`FnDictationGesture.Input` gagne un cas, et `Action` en gagne un :

```swift
enum Input {
    case pressed(at: TimeInterval)
    case released(at: TimeInterval)
    case secondTapTimedOut
    case cancelled          // neuf
}

enum Action: Equatable {
    case startRecording
    case stopRecording
    case discardRecording   // neuf
    case showLocked
    case scheduleSecondTapTimeout(after: TimeInterval)
    case cancelSecondTapTimeout
}
```

`discardRecording` n'est pas `stopRecording`. `stopRecording` transcrit et
injecte ; `discardRecording` jette le tampon audio et ne produit rien.

## Le comportement, tel que les tests l'exigeaient

Une phase `cancelled` s'ajoute à `Phase`, distincte de `.idle`, parce que la
machine doit savoir avaler le relâchement qui suivra.

| Situation au moment d'Échap | Sortie | Ce qui suit |
|---|---|---|
| Maintien simple, touche encore enfoncée | `[.discardRecording]` | Le `.released` suivant rend `[]`, il n'est pas lu comme « termine » |
| Dictée verrouillée, touche relâchée | `[.discardRecording]`, `isLocked` repasse à `false` | Le `.pressed` suivant rend `[.startRecording]`, il ne poursuit pas la dictée annulée |
| Presse d'arrêt d'une dictée verrouillée déjà tenue | `[.discardRecording]`, `isLocked` à `false` | Le `.released` suivant rend `[]` |
| Dans la fenêtre de double-tap, micro chaud | `[.cancelSecondTapTimeout, .discardRecording]`, dans cet ordre | `.secondTapTimedOut` rend ensuite `[]` |
| Deuxième tap tenu | `[.discardRecording]` | Le `.released` suivant rend `[]` |
| Aucune dictée en cours | `[]` | `hasActiveRecording` reste `false` |
| Échap répété, ou auto-répétition d'un Échap tenu | Le premier rend `[.discardRecording]`, tous les suivants `[]` | Aucun double rejet |

Deux invariants sont testés à part parce que le reste du code en dépend :

1. **`hasActiveRecording` est `false` après une annulation.** C'est la question
   que `FnDictationGestureController.handle` pose sur `.interrupted` pour
   décider s'il termine la dictée. Répondre `true` pour une dictée déjà jetée
   la pousserait dans `finishRecording()`, c'est-à-dire transcrirait et
   injecterait exactement ce que l'utilisateur venait d'annuler.
2. **La presse suivante démarre une dictée neuve.** Après annulation puis
   relâchement, `.pressed` rend `[.startRecording]` et `.released` rend
   `[.stopRecording]`. La machine est revenue au repos, pas dans un état
   intermédiaire.

Le piège que le quatrième cas documente : le timeout de second tap laissé
programmé se déclenche plus tard et met à `nil` le `timeoutWorkItem` de la
dictée **suivante**, qui devient alors impossible à annuler. D'où l'ordre
`cancelSecondTapTimeout` avant `discardRecording`.

## Ce que la spec ne couvre pas encore

Le pur automate est spécifié ; le câblage ne l'est pas.

- **D'où vient `.cancelled`.** `HotkeyMonitor` observe déjà les `flagsChanged`
  et les `keyDown` du tap d'événements. Il faut décider si Échap est observé
  seulement pendant une dictée (moins de surface, mais il faut armer et
  désarmer) ou en permanence, et surtout **s'il est consommé ou laissé passer**.
  Avaler l'Échap de l'utilisateur pendant qu'une dictée tourne casserait la
  fermeture de dialogue de l'app au premier plan. Le laisser passer est
  probablement correct, et c'est une décision à écrire.
- **Ce que la bulle montre.** Le rebranding lui a donné un état `failed` avec
  `showFailure()` et son garde de génération `hideGeneration`. Une annulation
  est un deuxième état auto-effaçant du même type, avec une autre copie, et il
  se construit sur exactement le même mécanisme. Voir
  `Sources/plume/UI/RecordingOverlay.swift`.
- **Le tampon audio.** `discardRecording` doit atteindre `AudioCapture` sans
  passer par le chemin de transcription. À vérifier : ce que fait l'arrêt de la
  capture des échantillons déjà accumulés.

## Pourquoi cette feature n'a pas été fondue dans le rebranding

Un lot où le renommage, l'empaquetage et une feature de comportement se mêlent
n'est plus bisectable. Le rebranding ne devait ajouter **aucune** capacité
nouvelle, et la seule exception assumée est l'état d'erreur de la bulle, qui
rend visible un échec déjà présent dans stderr. Voir
`docs/rebranding/05-checklist-et-verification.md`.

## Les tests, mot pour mot

Sortis de `Tests/parrotTests/FnDictationGestureTests.swift` tels quels. Ils se
recollent en fin de classe le jour où `.cancelled` et `.discardRecording`
existent.

```swift
    // MARK: - Cancelling a dictation

    /// Escape arrives while the hotkey is still physically down, so the
    /// release that follows must not be read as "finish this dictation".
    func testEscapeDuringAHoldDiscardsAndSwallowsTheRelease() {
        var gesture = FnDictationGesture()

        XCTAssertEqual(gesture.handle(.pressed(at: 1.0)), [.startRecording])
        XCTAssertEqual(gesture.handle(.cancelled), [.discardRecording])
        XCTAssertEqual(gesture.handle(.released(at: 2.0)), [])
    }

    func testEscapeWhileLockedDiscardsAndUnlocks() {
        var gesture = FnDictationGesture(doubleTapInterval: 0.4)

        _ = gesture.handle(.pressed(at: 1.0))
        _ = gesture.handle(.released(at: 1.1))
        _ = gesture.handle(.pressed(at: 1.2))
        XCTAssertEqual(gesture.handle(.released(at: 1.25)), [.showLocked])
        XCTAssertTrue(gesture.isLocked)

        XCTAssertEqual(gesture.handle(.cancelled), [.discardRecording])
        XCTAssertFalse(gesture.isLocked)
        // The hotkey is up in locked dictation, so the next press starts over
        // rather than being swallowed as the tail of the cancelled one.
        XCTAssertEqual(gesture.handle(.pressed(at: 3.0)), [.startRecording])
    }

    /// The press that would have stopped a locked dictation is already held
    /// when Escape lands. The lock must clear even though the release has yet
    /// to arrive.
    func testEscapeWhileTheStopPressIsHeldDiscardsAndUnlocks() {
        var gesture = FnDictationGesture(doubleTapInterval: 0.4)

        _ = gesture.handle(.pressed(at: 1.0))
        _ = gesture.handle(.released(at: 1.1))
        _ = gesture.handle(.pressed(at: 1.2))
        _ = gesture.handle(.released(at: 1.25))
        XCTAssertEqual(gesture.handle(.pressed(at: 3.0)), [])

        XCTAssertEqual(gesture.handle(.cancelled), [.discardRecording])
        XCTAssertFalse(gesture.isLocked)
        XCTAssertEqual(gesture.handle(.released(at: 3.1)), [])
    }

    /// A quick tap leaves the mic hot while the second tap is awaited. The
    /// pending timeout has to die with the dictation: left scheduled, it fires
    /// later and nils out the timer belonging to the *next* dictation, which
    /// then can never be cancelled.
    func testEscapeInsideTheDoubleTapWindowCancelsTheTimeoutToo() {
        var gesture = FnDictationGesture(doubleTapInterval: 0.4)

        XCTAssertEqual(gesture.handle(.pressed(at: 1.0)), [.startRecording])
        XCTAssertEqual(
            gesture.handle(.released(at: 1.1)),
            [.scheduleSecondTapTimeout(after: 0.4)]
        )
        XCTAssertEqual(
            gesture.handle(.cancelled),
            [.cancelSecondTapTimeout, .discardRecording]
        )
        XCTAssertEqual(gesture.handle(.secondTapTimedOut), [])
    }

    func testEscapeWhileTheSecondTapIsHeldDiscards() {
        var gesture = FnDictationGesture(doubleTapInterval: 0.4)

        _ = gesture.handle(.pressed(at: 1.0))
        _ = gesture.handle(.released(at: 1.1))
        XCTAssertEqual(gesture.handle(.pressed(at: 1.2)), [.cancelSecondTapTimeout])
        XCTAssertEqual(gesture.handle(.cancelled), [.discardRecording])
        XCTAssertEqual(gesture.handle(.released(at: 1.3)), [])
    }

    func testEscapeWhenNoDictationIsLiveDoesNothing() {
        var gesture = FnDictationGesture()

        XCTAssertEqual(gesture.handle(.cancelled), [])
        XCTAssertFalse(gesture.hasActiveRecording)
    }

    /// Auto-repeat of a held Escape, and a second press of it, both arrive as
    /// further `.cancelled` inputs. Neither may discard twice.
    func testRepeatedEscapesDiscardOnlyOnce() {
        var gesture = FnDictationGesture()

        _ = gesture.handle(.pressed(at: 1.0))
        XCTAssertEqual(gesture.handle(.cancelled), [.discardRecording])
        XCTAssertEqual(gesture.handle(.cancelled), [])
        XCTAssertEqual(gesture.handle(.cancelled), [])
    }

    /// The invariant the whole cancel path rests on. `.interrupted` — a tap the
    /// system disabled, or a hotkey swapped mid-hold — asks this question to
    /// decide whether to finish the dictation. Answering true for a dictation
    /// already discarded would push it through `finishRecording()`.
    func testACancelledDictationIsNoLongerActive() {
        var gesture = FnDictationGesture()

        _ = gesture.handle(.pressed(at: 1.0))
        XCTAssertTrue(gesture.hasActiveRecording)
        _ = gesture.handle(.cancelled)
        XCTAssertFalse(gesture.hasActiveRecording)
    }

    func testTheNextPressAfterACancelStartsAFreshDictation() {
        var gesture = FnDictationGesture()

        _ = gesture.handle(.pressed(at: 1.0))
        _ = gesture.handle(.cancelled)
        _ = gesture.handle(.released(at: 2.0))

        XCTAssertEqual(gesture.handle(.pressed(at: 3.0)), [.startRecording])
        XCTAssertEqual(gesture.handle(.released(at: 4.0)), [.stopRecording])
    }
```
