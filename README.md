<img src="Design/icon/plume-icon.svg" width="96" alt="">

# Plume

Hold a key, speak, release. The text is at your cursor in under 500 ms, and the
audio never left the Mac.

```sh
curl -fsSL https://plume.sprintmob.com/install.sh | sh
"$HOME/.local/bin/plume" setup
```

A macOS dictation daemon by [SprintMob](https://sprintmob.com). On-device
transcription on the Apple Neural Engine, no account, no network call, no
transcript written to disk.

> **A demo GIF of the pill goes here.** It is the thing people look at first.
> Record one before announcing this anywhere.

**Requires:** macOS 14 or later on Apple Silicon. Transcription runs on the
Apple Neural Engine via CoreML, so the installer refuses to run on Intel.

The installer puts `Plume.app` in `~/Applications` and writes a three-line CLI
shim at `~/.local/bin/plume`. It needs no administrator password and does not
change your shell profile. Use the full path shown above, or add `~/.local/bin`
to your `PATH` yourself. Read the script before you pipe it to a shell.

To install a test release, pass its tag explicitly:

```sh
curl -fsSL https://plume.sprintmob.com/install.sh | sh -s -- --tag v0.1.0-rc.1
```

Without `--tag`, the installer selects the latest stable release.

## Lineage

Plume is a fork of [`digimata/parrot`](https://github.com/digimata/parrot) by
Andrew Jones, MIT-licensed. Upstream stopped taking commits in May 2026 with 25
open, unreviewed pull requests; this fork merged 16 of them across five waves
before writing a line of its own. See
[ADR-0001](docs/adr/0001-fork-rather-than-contribute-upstream.md) and
[ADR-0002](docs/adr/0002-merge-upstream-prs-in-waves.md).

Most of what Plume does was written by people who never got a review: andredezzy,
vipergsm, justinhnaylor, Entrepenulian, augiefra, tomiiide, imtamiliniyan and
L65FREAD. [NOTICE](NOTICE) says who wrote what. SprintMob publishes it; SprintMob
did not write most of it.

## Plume is not notarized

SprintMob does not have an Apple Developer ID yet, so the app carries an ad-hoc
signature. Two consequences, and neither is hidden:

1. **If you download the zip in a browser**, macOS quarantines it and refuses to
   open it. The message is "Plume is damaged and can't be opened," which is what
   macOS says about any app it cannot verify. The `curl … | sh` installer above
   does not go through a browser, so nothing is quarantined and this does not
   happen. If you did download it by hand:
   `xattr -dr com.apple.quarantine "$HOME/Applications/Plume.app"`.
2. **Every update costs you the Accessibility grant.** An ad-hoc signature is
   anchored to the exact bytes of the build, so macOS treats each release as a
   different application. After updating, Plume will still record and
   transcribe, and will silently stop typing at the cursor until you re-enable
   it under System Settings → Privacy & Security → Accessibility. `plume doctor`
   will tell you that is what happened.

Both go away the day we ship a Developer ID-signed, notarized build. The reason
to buy one is the second point, not the first.

## How to use

1. **Run it.** Either `plume install --launch-at-login`, which runs it forever
   from the menu bar, or `plume` in any terminal tab.
2. **Click into the text field you want to dictate into.** Messages, the address
   bar, a Slack thread, anywhere a cursor blinks.
3. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of
   the screen while the mic is hot.
4. **For hands-free dictation, double-tap `fn`.** Recording stays on and the
   pill's rim turns lime.
5. **Tap `fn` once to stop a locked dictation.** Plume restores audio,
   transcribes, and types at the cursor.
6. **The transcript types itself in.** It goes to the clipboard every time as
   well, so ⌘V gets it back if the app swallowed it, and if no editable text
   field has the focus a panel shows you the transcript and says where it went.

That's it. No record button, no stop button, no "send". `fn` is the whole
interface.

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is
> set to "Change input source" or "Show emoji & symbols," `plume setup` will tell
> you how to flip it back to plain `fn`.

## The settings window

Everything above can be changed without a terminal. Open **Settings…** from the
menu bar, or press ⌘, once Plume is in front.

| Section | What's in it |
|---|---|
| **Home** | What Plume is doing, the active model, and the `plume doctor` checks with the fix for each |
| **Configuration** | The dictation overlay, the hold-to-talk key, launch at login, injection mode, and whether to keep a session history |
| **Sound** | Which microphone to use, and whether to mute system audio while dictating |
| **Models** | Every model, its size, and whether it's downloaded. Click one to switch |
| **History** | What you've dictated since Plume started. Click an entry to copy it |

The window is the same settings as the menu bar, not more: every control moves
something the CLI flags already moved. While it's open Plume takes a dock icon,
so ⌘C, ⌘V and ⌘W work; both go away when you close it.

**The history is kept in memory only.** It holds the last 200 dictations of the
current run, it is gone when Plume restarts, and it is never written to disk.
Turn it off entirely under Configuration → Application.

## Upgrading from parrot

Plume was called parrot until September 2026. If you have an install from then,
run this once:

```sh
plume install --migrate
```

It boots the old launch agent out, moves the model weights (a rename on the same
volume, so instant rather than a multi-gigabyte copy), moves the log and the
capture cache, and carries every remembered choice over to the new preferences
domain. It checks everything it needs before it moves a single byte, and refuses
rather than half-finishing. Running it twice is safe. `plume doctor` tells you
when it is needed and confirms when it is done.

Two things it does not do. It leaves `~/Library/Preferences/parrot.plist` alone,
which is a few hundred bytes and the only way to replay the migration if you
throw the new install away. And it prints, rather than runs, the `sudo rm` for
the old `/usr/local/bin/parrot`: a background daemon has no business asking for
root.

The saved position of the settings window is not carried over. It is a
rectangle.

## CLI

```sh
plume                                 # run in the foreground (^C to quit)
plume setup                           # one-time setup: permissions + model download
plume doctor                          # check permissions and the push-to-talk key
plume install --launch-at-login       # register a LaunchAgent (background daemon)
plume install --uninstall             # remove the LaunchAgent, and list what is left
plume install --migrate               # move models and settings over from a parrot install
plume install --purge-legacy-logs     # delete world-readable /tmp logs from older versions
plume models list                     # list available models
plume models download <id>            # pre-download a model
plume --model whisper-large-v3-turbo  # bigger, multilingual, slower first-run
plume --hotkey right-option           # change the push-to-talk key
plume --inject-mode type-unicode      # type the text instead of pasting it
plume --mute-output                   # mute system audio while recording
plume --no-overlay                    # disable the bottom-of-screen pill
```

`plume install --uninstall` stops and removes the LaunchAgent, then prints the
absolute paths of any app, shim, or downloaded models still on disk. If you
have not added `~/.local/bin` to your `PATH`, run
`"$HOME/.local/bin/plume" install --uninstall` instead. Removing the models is
optional; keep them if you plan to reinstall.

### Non-Apple keyboards

`fn` only exists as far as macOS is concerned on Apple keyboards. Third-party
keyboards handle their `Fn` key entirely in firmware: it reshapes the F-row
locally and never sends anything to the host, so no application can bind to it.
On those, pick another modifier:

```sh
plume --hotkey left-option
```

`--hotkey` accepts `fn`, and the left and right variants of `option`, `command`,
`control`, and `shift`. Run `plume run --debug-hotkey` to print the keycodes
your keyboard actually emits. Note that it logs every key you press while it
runs, so use it to identify a key and then stop it.

You can also pick the key from the menu bar, under **Hold-to-talk key**, or in
the settings window under Configuration. It takes effect immediately, with no
restart, and is remembered, so a daemonized install keeps it across logins
without re-running `plume install`. The flag stays useful for a one-off run: it
sets the key for that launch without changing what you come back to.

### Injection modes

Also selectable from the menu bar under **Injection**, or in the settings window
under Configuration → Application, and remembered the same way.

Whichever you pick, the transcript goes to the clipboard first, every time,
including when there is nowhere to inject it. It replaces what you had copied
and does not put it back, so pair Plume with a clipboard manager if you care
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

It is a remembered choice, like `--no-overlay`: set it once in the settings
window (Sound → Playback, and Configuration → Appearance for the overlay) and it
sticks. Both flags only reach one way, since there is no `--overlay`, so a flag
can silence the pill for one run but never force it back on over a remembered
"off".

## Privacy

Transcripts are never written to disk. The daemon logs timing and length only
(`→ 0.42s · 63 chars`). `--echo-transcripts` prints the full text to stderr, and
its help text says so, but it is never used by the LaunchAgent.

Every transcript goes to the clipboard as well (see [Injection
modes](#injection-modes)). Plume keeps no history of its own on disk, but if you
run a clipboard manager, that manager's history is a transcript log on disk.
Plume can promise it writes none; it cannot promise nothing does.

`plume install --launch-at-login` discards the daemon's output. To keep it, add
`--log-file` and it goes to `~/Library/Logs/plume.log`, created `0600` and owned
by you. Either way the log holds no transcript text.

> **If you installed this back when it was parrot**, the daemon was writing every
> transcript in plaintext to `/tmp/parrot.err.log`, which any local user can
> read, with no rotation and no size cap. `plume doctor` will flag the file if
> it's still there. Read it, then remove it with
> `plume install --purge-legacy-logs`.

`--dump-wav` writes raw recorded audio to
`~/Library/Caches/plume/last-capture.wav` (`0600`, in a `0700` directory).

## Stack

- **Swift**, one SPM executable target, assembled into `Plume.app` by
  `scripts/bundle.sh` with no Xcode project
- **WhisperKit**, Whisper inference via CoreML, ANE-accelerated
- **AVAudioEngine**, mic capture
- **CGEventTap**, global hotkey
- **CGEvent**, text injection at the cursor
- **NSWindow**, borderless and click-through, for the dictation pill
- **SwiftUI + NSHostingController**, the settings window

See [docs/architecture.md](docs/architecture.md) for design notes, and
[docs/adr/](docs/adr/) for the decisions and their arguments.

## Build from source

```sh
swift build -c release
swift test
./scripts/bundle.sh              # dist/Plume.app, ad-hoc signed
```

Contributions are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains the
`.scratch/` and ADR conventions this repo uses, and why they exist.

## Licence

MIT. Two copyright lines over one unmodified MIT body: Andrew Jones, who wrote
parrot, and SprintMob, who publishes this. See [LICENSE](LICENSE),
[NOTICE](NOTICE) for the lineage, and [THIRD-PARTY.md](THIRD-PARTY.md) for the
dependencies, two of which are Apache-2.0 and whose notices ship inside the app.
