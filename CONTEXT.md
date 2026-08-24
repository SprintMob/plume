# Parrot

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
or by writing to the pasteboard and pasting.
_Avoid_: paste, typing, output (each names one implementation of it)

**Doctor**:
The built-in self-check (`parrot doctor`) reporting whether permissions, models and
the launch agent are in a usable state.

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
A `CGEventTap` — the mechanism parrot uses both to observe the trigger key and to
inject text. Nothing else in the app touches keyboard events.

**Tap collision**:
Two event taps live at once competing over the same events, which is how injected
text ends up duplicated or dropped.

**Launch agent**:
The per-user `com.digimata.parrot` job that keeps the daemon running at login. Its
`KeepAlive` policy is what turns a warmup failure into a relaunch loop.
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
