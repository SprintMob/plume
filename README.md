# parrot

A minimal macOS dictation daemon. Push-to-talk, on-device transcription, text inserted at the cursor.

## Install

```sh
curl -fsSL https://digimata.github.io/parrot/install.sh | sh
parrot setup                       # grants mic + accessibility, downloads the model
parrot install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 14+ on Apple Silicon (M1 or newer). Transcription runs on the Apple Neural Engine via CoreML — so the installer refuses to run on Intel.

The installer drops the binary in `/usr/local/bin/parrot`. Builds are unsigned for now, so the installer strips the quarantine xattr — once you've inspected the script you'll see exactly what it does.

## How to use

1. **Run it.** Either `parrot install --launch-at-login` (daemonized, runs forever, lives in the menu bar), or `parrot` in any terminal tab.
2. **Click into the text field you want to dictate into** — Messages, the address bar, a Slack thread, anywhere a cursor blinks.
3. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of the screen while the mic is hot.
4. **For hands-free dictation, double-tap `fn`.** The recording stays active and a lock appears beside the waveform.
5. **Tap `fn` once to stop a locked dictation.** Parrot restores audio, transcribes, and types at the cursor.
6. **The transcript types itself in at the cursor** after recording stops. Usually within 200-300ms. If no editable text field has the focus, a popover holds the transcript so you can copy it instead of losing it.

That's it. There is no record button, no stop button, no "send" — `fn` is the whole interface.

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is set to "Change input source" or "Show emoji & symbols," `parrot setup` will tell you how to flip it back to plain `fn`.

## CLI

```sh
parrot                                 # run in the foreground (^C to quit)
parrot setup                           # one-time setup: permissions + model download
parrot install --launch-at-login       # register a LaunchAgent (background daemon)
parrot install --uninstall             # remove the LaunchAgent
parrot install --purge-legacy-logs     # delete world-readable /tmp logs from older versions
parrot doctor                          # check permissions + fn key setting
parrot models list                     # list available models
parrot models download <id>            # pre-download a model
parrot --model whisper-large-v3-turbo  # bigger, multilingual, slower first-run
parrot --hotkey right-option           # change the push-to-talk key
parrot --inject-mode type-unicode      # type the text instead of pasting it
parrot --mute-output                   # mute system audio while recording
parrot --no-overlay                    # disable the bottom-of-screen pill
```

### Non-Apple keyboards

`fn` only exists as far as macOS is concerned on Apple keyboards. Third-party
keyboards handle their `Fn` key entirely in firmware — it reshapes the F-row
locally and never sends anything to the host, so no application can bind to it.
On those, pick another modifier:

```sh
parrot --hotkey left-option
```

`--hotkey` accepts `fn`, and the left/right variants of `option`, `command`,
`control`, and `shift`. Run `parrot run --debug-hotkey` to print the keycodes
your keyboard actually emits. Note that it logs every key you press while it
runs, so use it to identify a key and then stop it.

### Injection modes

`--inject-mode paste` (the default) puts the transcript on the pasteboard,
sends ⌘V, and restores your previous pasteboard contents. Terminals and
Electron apps discard synthesized unicode key events but all handle paste, so
this is the mode that works everywhere.

`--inject-mode type-unicode` synthesizes the characters directly and never
touches the pasteboard, at the cost of silently dropping text in those apps.

### Mute while dictating

`--mute-output` mutes the active macOS output for the duration of a recording
and restores the previous mute or volume state when it stops, so a browser tab
or Spotify is not playing into the microphone.

## Privacy

Transcripts are never written to disk. The daemon logs timing and length only
(`→ 0.42s · 63 chars`); `--echo-transcripts` prints the full text to stderr, and its
help text says so, but it is never used by the LaunchAgent.

`parrot install --launch-at-login` discards the daemon's output. To keep it, add
`--log-file` and it goes to `~/Library/Logs/parrot.log`, created `0600` and owned by you.
Either way the log holds no transcript text.

> **If you installed parrot before this change**, the daemon was writing every transcript
> in plaintext to `/tmp/parrot.err.log`, which any local user can read, with no rotation
> and no size cap. `parrot doctor` will flag the file if it's still there. Read it, then
> remove it with `parrot install --purge-legacy-logs`.

`--dump-wav` writes raw recorded audio to `~/Library/Caches/parrot/last-capture.wav`
(`0600`, in a `0700` directory).

## Stack

- **Swift** — single SPM executable target
- **WhisperKit** — Whisper inference via CoreML, ANE-accelerated
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSWindow** (borderless, click-through) — recording-indicator pill

See [docs/architecture.md](docs/architecture.md) for design notes.

## Build from source

```sh
swift build -c release
.build/release/parrot --help
```
