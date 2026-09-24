# Architecture

## Goals

1. **CLI executable.** ~~Single binary, launched from the terminal.~~ The menu bar arrived in wave 3 and the settings window with it; the dock icon appears only while that window is open; and the daemon now ships inside `~/Applications/Plume.app` with `~/.local/bin/plume` as a shim into it. The bundle is for TCC, not for looks: unbundled, the Accessibility grant attaches to whichever terminal launched the daemon. See [ADR-0004](./adr/0004-settings-in-userdefaults.md), [ADR-0007](./adr/0007-a-settings-window-and-a-session-history.md) and [ADR-0008](./adr/0008-ship-a-real-app-bundle.md).
2. **Push-to-talk.** Hold Fn, speak, release — transcript appears at the cursor.
3. **Minimal recording feedback.** A small floating pill at the bottom of the screen while recording, so the user knows the mic is hot. Click-through, borderless, hidden when idle.
4. **On-device.** No network calls for transcription. Audio never leaves the machine.
5. **Pluggable models.** Whisper out of the box; Parakeet (or future engines) via a JSON-driven registry.
6. **Native and lean.** One Swift Package executable target. No sidecar processes. No HTTP servers.

## Non-goals

- Cross-platform (macOS only)
- ~~Menubar, dock icon, settings window, preferences UI~~ — all three shipped; see ADR-0004 and ADR-0007
- Cloud transcription providers
- AI post-processing, summarization, agents
- Speaker diarization, meeting recording, semantic search
- Auto-launch at login (user wires this themselves with `launchd` if desired)

## Why Swift

- **CoreML / ANE access.** WhisperKit and FluidAudio are Swift-native and run inference on the Apple Neural Engine — lower power, lower latency than CPU/GPU paths in Rust.
- **No FFI for platform APIs.** `AVAudioEngine`, `CGEventTap`, `CGEvent`, `AXIsProcessTrusted`, `NSWindow` — all first-party, no bindings to maintain.
- **Permissions plumbing** (microphone, accessibility) is dramatically smoother in a Swift binary than via Rust crates.
- **AppKit overlay for free.** The recording indicator (see below) is a borderless `NSWindow` — trivial in Swift, awkward in Rust.

The binary is a Swift Package executable — `swift build`, `swift run`. It is then assembled into `Plume.app` by `scripts/bundle.sh`, with no Xcode project and no `.xcodeproj` anywhere: a plist template, a directory layout and `codesign`. ~~Even with the overlay window, there is no `.app` bundle, no menubar entry, no dock icon.~~ All three clauses are now false; see [ADR-0008](./adr/0008-ship-a-real-app-bundle.md).

## High-level shape

```
$ plume
                                    ┌──────────────────┐
                                    │   PlumeCLI      │
                                    │   (main.swift)   │
                                    └────────┬─────────┘
                                             │ wires modules, runs RunLoop
                                             ▼
┌──────────────────┐  hotkey down   ┌──────────────────┐
│   HotkeyMonitor  │ ─────────────▶ │  AudioCapture    │
│  (CGEventTap)    │  hotkey up     │ (AVAudioEngine)  │
└──────────────────┘ ◀───────────── └────────┬─────────┘
                                             │ [Float] PCM
                                             ▼
                                    ┌──────────────────┐
                                    │   Transcriber    │
                                    │   (protocol)     │
                                    │  ┌────────────┐  │
                                    │  │ WhisperKit │  │
                                    │  └────────────┘  │
                                    │  ┌────────────┐  │
                                    │  │  Parakeet  │  │
                                    │  └────────────┘  │
                                    └────────┬─────────┘
                                             │ String
                                             ▼
                                    ┌──────────────────┐
                                    │  TextInjector    │
                                    │   (CGEvent)      │
                                    └──────────────────┘
```

## Modules

### `main.swift` (PlumeCLI)

Argument parsing (via `swift-argument-parser`), config loading, module wiring. Calls `NSApplication.shared.setActivationPolicy(.accessory)` so the process has no dock icon and no menu bar entry, then runs `NSApp.run()` to keep the process alive and drive the AppKit run loop (needed for `NSWindow`, `CGEventTap`, and AVFoundation). Exits cleanly on SIGINT. Logs status to stderr so a user running it in a terminal can see what's happening.

Subcommands:
- `plume` (default) — run the daemon
- `plume models list` — show registered models, mark which are downloaded
- `plume models download <id>` — pre-fetch a model
- `plume doctor` — check microphone and accessibility permissions, print remediation steps

### `HotkeyMonitor`

Global hotkey via `CGEventTap` (requires Accessibility permission). Default: **hold Fn**. Detected via `flagsChanged` events with `NSEvent.ModifierFlags.function` / `kCGEventFlagMaskSecondaryFn`. Emits `.pressed` / `.released` / `.interrupted`. Configurable via the `--hotkey` flag or the menu bar, which swaps the watched modifier in place — the tap already sees every `flagsChanged` event, so only the comparison changes and nothing is rebuilt.

**Fn key caveat:** macOS by default maps the Fn (🌐) key to "Show Emoji & Symbols" or "Start Dictation" depending on the user's setting in System Settings → Keyboard → Press 🌐 key to. The CGEventTap sees the keypress regardless, but the system action also fires. `plume doctor` will detect this setting and instruct the user to change it to "Do Nothing" so Fn becomes a clean modifier.

### `AudioCapture`

`AVAudioEngine` tap on the input node. Streams 16 kHz mono `Float32` buffers into a ring buffer while the hotkey is held. On release, hands the full buffer to the active `Transcriber`.

### `Transcriber` (protocol)

```swift
protocol Transcriber {
    func transcribe(_ audio: [Float]) async throws -> String
    var modelID: String { get }
}
```

Concrete implementations:

- `WhisperKitTranscriber` — wraps the `WhisperKit` package. CoreML, ANE-accelerated.
- `ParakeetTranscriber` — wraps `FluidAudio` (or direct CoreML) for NVIDIA Parakeet TDT.

Adding an engine = one new file conforming to `Transcriber`.

### `TextInjector`

Delivers the transcript, pasteboard first. Every non-empty transcript is written to the pasteboard before anything else happens to it — in both modes, and whether or not a field was found. That is the pasteboard guarantee: the daemon copies before the focus probe runs, so a probe that hangs, a password box, or an app that swallows what we send it cannot lose a dictation. What the user had copied is replaced and never put back. See [ADR-0006](./adr/0006-transcript-always-on-the-pasteboard.md).

How the transcript is then delivered to the focused app is picked from the menu bar or `--inject-mode`:

- `paste` (default) — posts ⌘V and lets the app read the pasteboard.
- `type-unicode` — `CGEventKeyboardSetUnicodeString`, the original mode. Slower, and silently dropped by apps that ignore synthesized unicode. It no longer leaves the pasteboard alone; nothing does.

`copyToPasteboard` is the guarantee on its own, called before the probe and again by `inject`. A repeat write of the same string that nothing has taken since is skipped, so one dictation is one entry in a clipboard manager. Keystrokes leave through a `KeyStroke` seam (`.commandV`, `.unicode`) rather than as `CGEvent`s, which is what lets the tests watch a delivery without posting into the session.

### `FocusedTextTarget` and `AccessibilityOptIn`

The focus probe. `FocusedTextTarget.probe()` reads the system-wide focused element and walks up to 6 ancestors and 96 descendants asking whether any of them can take text, under a 0.6 s budget so a slow app cannot block the main actor. A secure field is refused outright — a transcript must never be delivered into a password box. `FocusRules` holds the decision as a pure function over `ElementFacts`, which is where its tests live.

`AccessibilityOptIn` is what makes the probe work in a browser. Chromium and Electron apps keep their accessibility tree off until an assistive technology asks, so plume asks — `AXEnhancedUserInterface` and `AXManualAccessibility` on the focused app, as each dictation starts. See [ADR-0005](./adr/0005-wake-chromium-accessibility.md); `--no-wake-accessibility` turns it off, `--debug-focus` reports what the probe saw.

### `TranscriptFallbackPopover`

The transcript fallback: when the probe finds nowhere to put the text, this panel tells the user the dictation went to the pasteboard instead. The transcript is already there — the pasteboard guarantee put it there before the probe ran — so the Copy button is for the narrower case where something else has taken the pasteboard since. A borderless non-activating `NSPanel` at `.statusBar` level, bottom-center, sharing the overlay's anchor.

### `RecordingOverlay`

A single borderless `NSWindow` displayed at the bottom-center of the active screen while recording. Provides visual feedback that the mic is hot.

Window configuration:
- `styleMask: .borderless`
- `backgroundColor: .clear`, `isOpaque: false`, `hasShadow: true`
- `level: .statusBar` (or `.floating`) — sits above all other windows
- `ignoresMouseEvents = true` — clicks pass through to whatever is underneath
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]` — visible across Spaces, doesn't appear in window switcher

Content: a small SwiftUI view hosted via `NSHostingView`, showing a pulsing dot + "listening" text, optionally a live mic level meter fed from `AudioCapture`. Total footprint: ~120pt wide, ~40pt tall, positioned 60pt above the bottom of the screen.

States:
- **Hidden** — idle. No window on screen.
- **Recording** — shown on `.pressed`, mic level animated.
- **Transcribing** — brief spinner state between hotkey release and text injection (usually <500 ms).
- **Hidden** — back to idle after injection.

This is the only reason the process needs an `NSApplication` run loop instead of a bare `CFRunLoop`.

### `ModelRegistry`

JSON-driven, mirrors OpenWhispr's pattern:

```swift
struct TranscriptionModel: Codable {
    let id: String              // "whisper-large-v3-turbo"
    let displayName: String
    let engine: Engine          // .whisperKit | .parakeet
    let sizeMB: Int
    let downloadURL: URL
    let languages: [String]
    let recommended: Bool
}

enum Engine: String, Codable { case whisperKit, parakeet }
```

Backed by a bundled `models.json` resource. Adding a model = appending an entry. Adding an engine = one new `Transcriber` conformance + one entry in the `Engine` enum.

The registry is the single source of truth for: download URLs, file names, sizes, recommended flags, what shows up in `plume models list`.

### `ModelDownloader`

On first selection (or via `plume models download <id>`), downloads to `~/Library/Application Support/plume/models/<engine>/<id>/`. Progress bar to stderr (using `\r` overwrites). Resumable, validates size. Refuses to start the daemon if the selected model isn't present.

### Settings

One `UserDefaults`-backed store per concern, each resolving the same way: the CLI
flag wins for the launch that passes it, else the remembered choice, else the
default. A stored value that no longer parses falls through to the default rather
than failing the launch.

| Store | Keys | Chosen from |
|---|---|---|
| `ModelStore` | `modelID`, `previousModelID` | menu bar → Model |
| `InputDeviceStore` | `inputDeviceUID` | menu bar → Input |
| `SettingsStore` | `hotkey`, `injectMode` | menu bar → Hold-to-talk key, Injection · window → Configuration |
| `SettingsStore` | `overlay`, `muteOutput`, `sessionHistory` | window → Configuration, Sound |

The TOML file at `~/.config/plume/config.toml` this section used to specify was
never built; see [ADR-0004](./adr/0004-settings-in-userdefaults.md) for why the
merge queue settled on `UserDefaults` instead. The launch agent deliberately bakes
none of these into its `ProgramArguments`, since a flag there would override the
menu bar and the settings window on every login.

`overlay` and `muteOutput` were `--no-overlay` and `--mute-output` and nothing
else until the window needed switches that survive a restart. Both flags still
reach one way only: there is no `--overlay`, so a flag can silence the pill for a
run but never force it back on over a remembered "off". `sessionHistory` has no
flag at all — the history is only readable from the window.

Neither surface owns the live state. `DaemonState` holds it, and both read from
it: the window through `@ObservedObject`, the menu bar by rebuilding its labels
when it opens. A closed menu shows nothing, so there is nothing to keep in sync in
between.

## Permissions

Two prompts on first run, both surfaced via `plume doctor`:

1. **Microphone** — standard `AVCaptureDevice` request, fires on first audio engine start.
2. **Accessibility** — required for `CGEventTap` (hotkey) and `CGEvent` posting (text injection). User toggles in System Settings → Privacy & Security → Accessibility, granting **Plume** permission. Before the `.app` bundle, the grant went to the *terminal* that launched the daemon, since a bare binary inherits its parent's TCC identity.

`plume doctor` checks both and prints actionable next steps if either is missing. Without these, the daemon refuses to start.

### The TCC quirk the bundle removed

This section used to read: launching `plume` from `Terminal.app` granted accessibility to *Terminal*, not to plume, so switching terminals meant re-granting, and running under `launchd` meant granting to whatever spawned it. It was never a plume bug: a bare binary has no identity of its own, so macOS attributed the request to the process that did.

`Plume.app` has a stable `CFBundleIdentifier`, so the grant attaches to Plume and survives a change of terminal. What remains, until there is a Developer ID certificate, is that an ad-hoc signature anchors the requirement on the build's `cdhash`, so each release reads as a different application and costs the grant once. `plume doctor` says so when it happens. See [ADR-0008](./adr/0008-ship-a-real-app-bundle.md).

## Models — what ships

Initial registry:

| Engine | Model | Size | Notes |
|---|---|---|---|
| WhisperKit | `whisper-base.en` | ~80 MB | Fast, English only, low resource |
| WhisperKit | `whisper-large-v3-turbo` | ~800 MB | Recommended for daily use |
| Parakeet | `parakeet-tdt-0.6b-v3` | ~600 MB | English, fastest on ANE |

Models live in `~/Library/Application Support/plume/models/`. Not bundled — fetched on first selection or via `plume models download`.

## Data flow, end-to-end

1. User runs `plume` in a terminal.
2. `PlumeCLI` validates permissions (`plume doctor` logic), loads config, instantiates modules.
3. Sets `.accessory` activation policy and enters `NSApp.run()`. Status: `listening`. Overlay hidden.
4. User holds Fn.
5. `HotkeyMonitor` fires `.pressed`. `RecordingOverlay` shows. Status: `recording`.
6. `AudioCapture` starts the AVAudioEngine tap. Buffers fill. Overlay animates mic level.
7. User releases Fn.
8. `HotkeyMonitor` fires `.released`. Overlay switches to spinner. Status: `transcribing`.
9. `AudioCapture` stops, hands buffer to active `Transcriber`.
10. `Transcriber` runs CoreML inference. Returns string.
11. Overlay hides. Status: `listening`. The transcript goes to the pasteboard — before the probe, so nothing the probe does can lose it.
12. `FocusedTextTarget.probe()` asks whether the focused element can take text. On a No it wakes the app's accessibility tree and asks once more.
13. Editable → `TextInjector` delivers the string at the cursor. Not editable, or a secure field → `TranscriptFallbackPopover` shows what is already on the pasteboard. Loop.
14. User hits `^C`. Process exits cleanly.

End-to-end latency target: <500 ms after hotkey release for utterances under 10 seconds, on Apple Silicon.

## What we are deliberately NOT building

- No streaming partial transcripts in v1. Press, speak, release, get full text.
- No VAD-based hands-free mode. Push-to-talk is more reliable and uses zero idle CPU.
- No transcript log and no clipboard manager. Nothing plume produces is written to disk. Output goes to the cursor, and to the pasteboard on the way — one entry, overwritten every dictation. Finished dictations are also kept in a capped in-memory buffer for the life of the daemon run, which the window's History section reads and a switch turns off. (This bullet originally ruled out the pasteboard as an output at all, and then ruled out any history. See [ADR-0006](./adr/0006-transcript-always-on-the-pasteboard.md) and [ADR-0007](./adr/0007-a-settings-window-and-a-session-history.md).)
- No custom vocabulary, prompts, or post-processing.
- ~~No settings window and no preferences panel.~~ Configuration is flags, the menu bar, and a settings window with five sections — Home, Configuration, Sound, Models, History — reachable from the menu bar and from ⌘,. The window exposes no capability the daemon did not already have. (This bullet originally ruled out the menu bar too; waves 2 and 3 merged it, and the window followed. See [ADR-0004](./adr/0004-settings-in-userdefaults.md) and [ADR-0007](./adr/0007-a-settings-window-and-a-session-history.md).)

These are deliberate cuts. Each can be revisited if real usage demands it.

## Project layout (planned)

Organized by feature area. These are folders within a single SPM executable target — Swift sees them as one module, but the directory grouping keeps related code together. If a group later earns its keep as a reusable library (e.g. `Transcription` consumed by another tool), it can be promoted to its own SPM target with no rewriting.

```
plume/
  Package.swift                 # SPM, single executable target
  Sources/plume/
    main.swift                  # entry point, argument parsing, NSApp.run()
    SettingsStore.swift
    Doctor.swift

    Transcription/              # the inference layer
      Transcriber.swift         # protocol
      WhisperKitTranscriber.swift
      ParakeetTranscriber.swift

    Models/                     # registry + download pipeline
      ModelRegistry.swift
      ModelDownloader.swift
      TranscriptionModel.swift  # Codable types

    Audio/
      AudioCapture.swift        # AVAudioEngine tap + ring buffer

    Input/
      HotkeyMonitor.swift       # CGEventTap, listen-only, watches the hotkey
      FnDictationGesture.swift  # hold vs double-tap-lock state machine
      TextInjector.swift        # CGEvent posting + pasteboard
      FocusedTextTarget.swift   # the focus probe
      AccessibilityOptIn.swift  # wakes Chromium/Electron a11y trees

    UI/
      RecordingOverlay.swift        # borderless NSPanel + SwiftUI pill
      MenuBarController.swift       # NSStatusItem and its menu
      TranscriptFallbackPopover.swift  # transcript fallback panel
      DaemonState.swift             # live state + remembered choices, read by both surfaces
      Style.swift                   # the two colours plume paints its own chrome in
      Settings/                     # the settings window
        SettingsWindowController.swift  # NSWindow + main menu + .regular/.accessory
        SettingsRootView.swift          # sidebar and section routing
        SettingsControls.swift          # page, group, row, key cap
        HomeSection.swift               # doctor checks and what plume is doing
        ConfigurationSection.swift      # overlay, hotkey, launch agent, injection
        SoundSection.swift              # microphone, system audio while dictating
        ModelsSection.swift             # the registry as a table
        HistorySection.swift            # this run's dictations

  Resources/
    models.json
  docs/
    architecture.md
  README.md
```

Build: `swift build -c release`. Resulting binary at `.build/release/plume`. Install: copy to `~/.local/bin/` or `/usr/local/bin/`.

### On Swift "modules"

Swift's module unit is the **SPM target** (one target = one module = one `import` namespace). For plume v1 we use a single executable target with the folder structure above; everything is in the same module so no `import` statements between files. If we ever want enforced boundaries (e.g. `Transcription` and `UI` shouldn't reach into `Audio` internals), we promote folders to separate targets in `Package.swift` — a structural change, not a semantic one.

## Open questions

- **Parakeet via FluidAudio vs. direct CoreML?** FluidAudio is faster to integrate but adds a dependency. Decide once we benchmark both.
- **Hotkey conflicts.** Right-Option is unused on most keyboards but some users remap it. Print a clear error if `CGEventTap` registration fails.
- **First-run UX.** Bundle `whisper-base.en` so `plume` works out of the box, or always require an explicit download? Probably the latter — keeps the binary small and the model directory clean.
- **Code signing.** A self-built unsigned binary works fine locally but accessibility permission persistence is more reliable for signed binaries. Decide if we sign for personal distribution.
