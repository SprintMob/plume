# A settings window, and a session history to put in it

`docs/architecture.md` rules out two things this builds. Its first goal says "No
menubar, no dock icon, no settings window", its non-goals repeat "Menubar, dock
icon, settings window, preferences UI", and the deliberate-cuts list closes with
"No settings window and no preferences panel. Configuration is flags plus the menu
bar." A second bullet in the same list says "No history, transcript log, or
clipboard manager."

Both are reopened here, together, because the second is what makes the first worth
building.

**The window.** The menu bar carries four submenus and answers every question with
a tick or nothing. It cannot show why a dictation produced no text, which of five
models is on disk, or that the Fn key is bound to Show Emoji — all of which the
daemon already knows and only tells a terminal. `parrot doctor` prints the answer
to a user who has to know the command exists, which is the wrong half of the
audience for a background daemon. So: **a settings window with five sections,
built on nothing new.** Every control moves an existing setting and every readout
shows state the daemon already computes. [ADR-0004](./0004-settings-in-userdefaults.md)
already superseded the "no menu bar" half of the same sentence for the same
reason — the merge queue had built it — and the `*Store`-per-concern shape it
settled is what the window writes through.

**The history.** Nothing survived a dictation, so a "History" section had nothing
to read and would have been a fifth sidebar row leading nowhere. The alternative
was four sections, and four sections is a worse product: the list of what you just
said is the part of a dictation tool people actually return to, and parrot
throwing it away is a decision nobody made on purpose — it fell out of "no
transcript log", which was about **files**.

So: **finished dictations are kept in a capped in-memory buffer for the life of
the daemon run, and nowhere else.** `TranscriptHistory` holds 200 entries, newest
first, cleared on restart, with a `Clear` button and a `Keep session history`
switch that turns it off entirely. No file, no database, no `~/Library`
directory.

This is a smaller step than it sounds, and smaller than one already taken.
[ADR-0006](./0006-transcript-always-on-the-pasteboard.md) put **every** transcript
on the pasteboard unconditionally, where it sits indefinitely, readable by every
process on the machine, and gets written to disk by whatever clipboard manager the
user runs. Against that, a process-local array that dies with the process is the
more contained of the two. The claim the README makes — parrot writes no
transcript to disk — is exactly as true after this as before it.

Two alternatives were weighed. **Persisting the history** is what the reference
product does and what makes search worth having across days; it was rejected
because it would be the first time parrot wrote a transcript to a file, and that
is a different decision that deserves its own ADR and its own encryption
question. **Shipping four sections and no History** was rejected as above: it
trades a real capability for a line in a document that had already been reopened
twice.

## Consequences

- **Two surfaces now change the same settings**, so neither can own them.
  `DaemonState` holds the live state and the remembered choices; `MenuBarController`
  lost its six setters and its own copies and now reads that state when its menu
  opens. This also removes the reason `Parrot.swift` reached into `menuBar.injectMode`
  at every injection.
- **`--no-overlay` and `--mute-output` became remembered choices**, keys `overlay`
  and `muteOutput`. A switch in a window that forgets itself on restart is broken,
  and ADR-0004 already made exactly this move for `--hotkey` and `--inject-mode`.
  Both flags still reach in one direction only — there is no `--overlay` — so a
  flag can silence the pill for a run but never force it back on. `parrot doctor`
  now warns when either is baked into the launch agent, alongside the two it
  already watched.
- **The daemon switches to `.regular` while the window is open.** `.accessory`
  gives a process no menu bar, and a window without one has no ⌘C, ⌘V or ⌘W —
  dead keys in the history search field. The dock icon that appears with it is the
  honest signal that parrot has something on screen; it goes away with the window.
  There is no `.app` bundle, so the main menu is built in code.
- **The window is reachable only from the menu bar.** No `parrot settings`
  subcommand: a second process cannot raise the running daemon's window without an
  IPC channel that would exist for this one thing.
- **The overlay and the mute controller are now always constructed**, since either
  can be switched on mid-run. Neither holds a resource until it is used.
- **`ModelWeights.isInstalled` has a caller for the first time.** It shipped with
  none; the models table is what it was written for.
- **The menu bar's "Push-to-talk key" is now "Hold-to-talk key"**, matching the
  glossary, which has proscribed the first spelling since `CONTEXT.md` was
  written. The window uses the glossary's words throughout.
- **`docs/architecture.md` goal 1 and two of its deliberate cuts are superseded.**
  That document has now been reopened by ADR-0004, ADR-0006 and this one; what
  survives of its "deliberately NOT building" list is the streaming, VAD and
  vocabulary bullets.
