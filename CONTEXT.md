# Plume

Fork of [`digimata/parrot`](https://github.com/digimata/parrot), a macOS dictation
daemon: hold a key, speak, and the transcribed text is inserted into whatever app
has focus. Upstream has had no code commit since 2026-05-11 and carries 25 clean,
unreviewed PRs, so the work here is merging and arbitrating other people's patches
rather than writing new ones — see
[ADR-0001](./docs/adr/0001-fork-rather-than-contribute-upstream.md).

## Language

### Dictation

**Dictation**:
One press-speak-insert cycle: audio captured while the trigger key is held,
transcribed, then inserted into the focused app.
_Avoid_: recording, transcription (each names only the middle step)

**Hold-to-talk**:
The trigger model where audio is captured only while the Fn key is held down. The
upstream default.
_Avoid_: push-to-talk, PTT, hotkey mode

**Toggle-to-record**:
The competing trigger model where one press starts capture and a second ends it.
Not a variant of hold-to-talk but a replacement for it.
_Avoid_: tap-to-talk, lock mode (Fn-locked hold-to-talk is a third, distinct thing)

**Text injection**:
Getting transcribed text into the focused app, whether by synthesising keystrokes
or by pasting what the pasteboard guarantee has already written.
_Avoid_: paste, typing, output (each names one implementation of it)

**Doctor**:
The built-in self-check (`plume doctor`) reporting whether permissions, models and
the launch agent are in a usable state.

**Remembered choice**:
A setting picked in the menu bar or the **settings window** that survives a
restart, held in `UserDefaults` by one `*Store` type per concern — `SettingsStore`
for the modifier, the injection mode, the overlay, output muting and the session
history, `InputDeviceStore` for the microphone, `ModelStore` for the active model id.
All resolve alike: the flag wins for the launch that passes it, else the remembered
value, else the default. Note `ModelStore` the type is not the **Model store**
below, which is a directory of weights.
_Avoid_: config, preferences, config file (there is no file — see [ADR-0004](./docs/adr/0004-settings-in-userdefaults.md))

**Settings window**:
The five-section window — Home, Configuration, Sound, Models, History — opened
from the menu bar or ⌘,. It exposes no capability the daemon did not already have;
every control moves a remembered choice and every readout shows state the daemon
already computes. Named for what `docs/architecture.md` calls it, not for the
`preferences` its non-goals used — see [ADR-0007](./docs/adr/0007-a-settings-window-and-a-session-history.md).
_Avoid_: preferences window, preferences panel, settings panel

**Section**:
One row of the settings window's sidebar and the pane it shows. Always one of the
five; there is no sixth, because there is no sixth feature to put in one.
_Avoid_: tab, page, pane

**Daemon state**:
`DaemonState` — the live state of a run (what the dictation is doing, which model
is loaded, which switch is in flight) plus the remembered choices, held in one
place because the menu bar and the settings window both read and write them. The
menu bar used to hold this itself.
_Avoid_: app state, view model, controller

**Session history**:
The finished dictations of the current daemon run, capped at 200 and held in RAM
by `TranscriptHistory`. Cleared when the daemon restarts and never written to
disk, which is what keeps the no-transcripts-on-disk promise true while the
History section exists.
_Avoid_: history log, transcript log, recents (the first two name a file, which
this deliberately is not)

### Speech models

**Model**:
A speech-to-text model, named by its Hugging Face id (`whisper-large-v3-turbo`).
_Avoid_: engine, backend (those name the runtime — WhisperKit, Parakeet — not the weights)

**Model store**:
The single on-disk directory holding every downloaded model on a machine. Where it
lives is upstream defect B1.
_Avoid_: cache, download base, huggingface folder

**Warmup**:
Loading the active model into memory when the daemon starts, before any dictation.
A failed warmup is what makes the daemon exit.

**Dataless model**:
A model iCloud has evicted: directory and file names survive, the blocks don't.
`ls` still reports the full size, `du` reports zero.
_Avoid_: missing, corrupted, evicted

### The macOS substrate

**Event tap**:
A `CGEventTap` — the mechanism plume uses both to observe the trigger key and to
inject text. Nothing else in the app touches keyboard events.

**Tap collision**:
Two event taps live at once competing over the same events, which is how injected
text ends up duplicated or dropped.

**Focus probe**:
The accessibility-API read deciding whether text injection has anywhere to land —
is the focused element editable, and is it a password box. Its answer picks between
injection and the transcript fallback.
_Avoid_: focus check, AX check (the probe is a walk over several elements, not one
attribute read)

**Accessibility opt-in**:
The handshake that makes an app expose its accessibility tree at all: Chromium
watches for `AXEnhancedUserInterface`, Electron for `AXManualAccessibility`. Both
keep that tree off until an assistive technology asks, so without the opt-in the
focus probe is blind to every browser text field — see
[ADR-0005](./docs/adr/0005-wake-chromium-accessibility.md).
_Avoid_: enabling accessibility (that names the permission macOS grants plume,
which is a different thing entirely)

**Pasteboard guarantee**:
Every non-empty transcript is written to the pasteboard before plume does anything
else with it, so a dictation survives a focus probe that hangs, a password box, and
an app that drops synthesized keystrokes. Unconditional, in both injection modes,
and it replaces what was copied before without putting it back — see
[ADR-0006](./docs/adr/0006-transcript-always-on-the-pasteboard.md).
_Avoid_: clipboard backup, auto-copy, copy fallback (it is not a fallback: it
happens on every dictation, including the ones that inject cleanly)

**Transcript fallback**:
Where a dictation goes when the focus probe finds nowhere to put it: a panel showing
the transcript the pasteboard guarantee has already copied, with a Copy button for
the case where something else has taken the pasteboard since.
_Avoid_: popover, bubble (the type is named `TranscriptFallbackPopover` but it is an
`NSPanel`)

**App bundle**:
`Plume.app` — the daemon, its `Info.plist` and the two SwiftPM resource bundles,
assembled by `scripts/bundle.sh` without Xcode. It exists so macOS has an identity
to anchor the Accessibility grant on; unbundled, that grant belonged to whichever
terminal launched the daemon. One string, `com.sprintmob.plume`, is its bundle
identifier, its launch agent label and its preferences domain — see
[ADR-0008](./docs/adr/0008-ship-a-real-app-bundle.md).
_Avoid_: the app, the package (the first is ambiguous with the daemon, the second
is the SwiftPM package)

**CLI shim**:
`/usr/local/bin/plume` — three lines that `exec` the executable inside the bundle.
Not a symlink: `Bundle.main` does not resolve through one, so a symlinked `plume`
would read a different preferences domain than the daemon. The launch agent points
at neither, always at the path inside the bundle.
_Avoid_: symlink, alias, wrapper

**Launch agent**:
The per-user `com.sprintmob.plume` job that keeps the daemon running at login. Its
`KeepAlive` policy is what turns a warmup failure into a relaunch loop. Its
`ProgramArguments[0]` must be inside the **app bundle**: outside one the daemon
reads the process-name preferences domain and every **remembered choice** is
invisible to it. Before the rename the label was `com.digimata.parrot`, which
`doctor` still knows about.
_Avoid_: service, daemon config, plist (the plist is the file, the launch agent is the job)

### The fork

**Upstream**:
`digimata/parrot` — specifically its `main` plus its 25 open PRs, which are this
repo's main source of code.
_Avoid_: origin, original repo

**Upstream defect**:
One of the five failures diagnosed on 2026-08-20 before the sources were read,
numbered B1–B5. Always cite the number: four of the five already have an upstream
PR that fixes them.
_Avoid_: bug, issue (keep those for anything found after the fork opens)

**Blind spot**:
A defect none of the 25 open PRs addresses. There are six, and they are the only
places where writing new code is justified.
_Avoid_: gap, missing feature, TODO

**Wave**:
One batch of upstream PRs merged together, numbered 1 to 5. Waves are ordered by
rebase cost, not by how valuable their contents are — see
[ADR-0002](./docs/adr/0002-merge-upstream-prs-in-waves.md).
_Avoid_: phase, milestone, sprint, batch
