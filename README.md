# plume

A minimal macOS dictation daemon. Push-to-talk, on-device transcription, text inserted at the cursor.

## Install

```sh
curl -fsSL https://plume.sprintmob.com/install.sh | sh
plume setup                       # grants mic + accessibility, downloads the model
plume install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 14+ on Apple Silicon (M1 or newer). Transcription runs on the Apple Neural Engine via CoreML — so the installer refuses to run on Intel.

The installer drops the binary in `/usr/local/bin/plume`. Builds are unsigned for now, so the installer strips the quarantine xattr — once you've inspected the script you'll see exactly what it does.

## How to use

1. **Run it.** Either `plume install --launch-at-login` (daemonized, runs forever, lives in the menu bar), or `plume` in any terminal tab.
2. **Click into the text field you want to dictate into** — Messages, the address bar, a Slack thread, anywhere a cursor blinks.
3. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of the screen while the mic is hot.
4. **For hands-free dictation, double-tap `fn`.** The recording stays active and a lock appears beside the waveform.
5. **Tap `fn` once to stop a locked dictation.** Plume restores audio, transcribes, and types at the cursor.
6. **The transcript types itself in at the cursor** after recording stops. Usually within 200-300ms. It goes to the clipboard every time as well, so ⌘V gets it back if the app swallowed it — and if no editable text field has the focus, a panel shows you the transcript and tells you it's waiting on the clipboard.

That's it. There is no record button, no stop button, no "send" — `fn` is the whole interface.

## The settings window

Everything above can be changed without a terminal. Open **Settings…** from the
menu bar, or press ⌘, once plume is in front.

| Section | What's in it |
|---|---|
| **Home** | What plume is doing, the active model, and the five `plume doctor` checks with the fix for each |
| **Configuration** | The dictation overlay, the hold-to-talk key, launch at login, injection mode, and whether to keep a session history |
| **Sound** | Which microphone to use, and whether to mute system audio while dictating |
| **Models** | Every model, its size, and whether it's downloaded — click one to switch |
| **History** | What you've dictated since plume started. Click an entry to copy it |

The window is the same settings as the menu bar, not more: every control moves
something the CLI flags already moved. While it's open plume takes a dock icon,
so ⌘C, ⌘V and ⌘W work; both go away when you close it.

**The history is kept in memory only.** It holds the last 200 dictations of the
current run, it is gone when plume restarts, and it is never written to disk.
Turn it off entirely under Configuration → Application.

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is set to "Change input source" or "Show emoji & symbols," `plume setup` will tell you how to flip it back to plain `fn`.

## CLI

```sh
plume                                 # run in the foreground (^C to quit)
plume setup                           # one-time setup: permissions + model download
plume install --launch-at-login       # register a LaunchAgent (background daemon)
plume install --uninstall             # remove the LaunchAgent
plume install --purge-legacy-logs     # delete world-readable /tmp logs from older versions
plume doctor                          # check permissions + push-to-talk key setting
plume models list                     # list available models
plume models download <id>            # pre-download a model
plume --model whisper-large-v3-turbo  # bigger, multilingual, slower first-run
plume --hotkey right-option           # change the push-to-talk key
plume --inject-mode type-unicode      # type the text instead of pasting it
plume --mute-output                   # mute system audio while recording
plume --no-overlay                    # disable the bottom-of-screen pill
```

### Non-Apple keyboards

`fn` only exists as far as macOS is concerned on Apple keyboards. Third-party
keyboards handle their `Fn` key entirely in firmware — it reshapes the F-row
locally and never sends anything to the host, so no application can bind to it.
On those, pick another modifier:

```sh
plume --hotkey left-option
```

`--hotkey` accepts `fn`, and the left/right variants of `option`, `command`,
`control`, and `shift`. Run `plume run --debug-hotkey` to print the keycodes
your keyboard actually emits. Note that it logs every key you press while it
runs, so use it to identify a key and then stop it.

You can also pick the key from the menu bar, under **Hold-to-talk key**, or in the
settings window under Configuration. It takes
effect immediately — no restart — and is remembered, so a daemonized install keeps
it across logins without re-running `plume install`. The flag stays useful for a
one-off run: it sets the key for that launch without changing what you come back
to.

### Injection modes

Also selectable from the menu bar under **Injection**, or in the settings window
under Configuration → Application, and remembered the same way.

Whichever you pick, the transcript goes to the clipboard first, every time —
including when there is nowhere to inject it. It replaces what you had copied
and does not put it back, so pair plume with a clipboard manager if you care
about your history.

`--inject-mode paste` (the default) sends ⌘V and lets the app read the
clipboard. Terminals and Electron apps discard synthesized unicode key events
but all handle paste, so this is the mode that works everywhere.

`--inject-mode type-unicode` synthesizes the characters directly, at the cost of
silently dropping text in those apps. It used to leave the clipboard untouched;
it no longer does.

### Mute while dictating

`--mute-output` mutes the active macOS output for the duration of a recording
and restores the previous mute or volume state when it stops, so a browser tab
or Spotify is not playing into the microphone.

It is a remembered choice, like `--no-overlay`: set it once in the settings window
(Sound → Playback, and Configuration → Appearance for the overlay) and it sticks.
Both flags only reach one way — there is no `--overlay` — so a flag can silence
the pill for one run but never force it back on over a remembered "off".

## Privacy

Transcripts are never written to disk. The daemon logs timing and length only
(`→ 0.42s · 63 chars`); `--echo-transcripts` prints the full text to stderr, and its
help text says so, but it is never used by the LaunchAgent.

Every transcript goes to the clipboard as well (see [Injection modes](#injection-modes)).
Plume keeps no history of its own — each dictation overwrites the last — but if you run
a clipboard manager, that manager's history is a transcript log on disk. Plume can
promise it writes none; it cannot promise nothing does.

`plume install --launch-at-login` discards the daemon's output. To keep it, add
`--log-file` and it goes to `~/Library/Logs/plume.log`, created `0600` and owned by you.
Either way the log holds no transcript text.

> **If you installed this back when it was parrot**, the daemon was writing every transcript
> in plaintext to `/tmp/parrot.err.log`, which any local user can read, with no rotation
> and no size cap. `plume doctor` will flag the file if it's still there. Read it, then
> remove it with `plume install --purge-legacy-logs`.

`--dump-wav` writes raw recorded audio to `~/Library/Caches/plume/last-capture.wav`
(`0600`, in a `0700` directory).

## Stack

- **Swift** — single SPM executable target
- **WhisperKit** — Whisper inference via CoreML, ANE-accelerated
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSWindow** (borderless, click-through) — recording-indicator pill
- **SwiftUI + NSHostingController** — the settings window

See [docs/architecture.md](docs/architecture.md) for design notes.

## Build from source

```sh
swift build -c release
.build/release/plume --help
```
