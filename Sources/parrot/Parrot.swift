import AppKit
import ArgumentParser
import Foundation
import WhisperKit

@main
struct Parrot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parrot",
        abstract: "Minimal macOS dictation daemon. Hold Fn, speak, release.",
        subcommands: [Run.self, Setup.self, Doctor.self, Models.self, Install.self],
        defaultSubcommand: Run.self
    )
}

extension HotkeyMonitor.Hotkey: ExpressibleByArgument {}
extension TextInjector.Mode: ExpressibleByArgument {}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the daemon (default)."
    )

    @Flag(name: .long, help: "Skip permission checks at startup.")
    var skipDoctor: Bool = false

    @Flag(name: .long, help: "Print every keyboard event the tap sees (debug).")
    var debugHotkey: Bool = false

    @Flag(name: .long, help: "Write each capture to ~/Library/Caches/parrot/last-capture.wav for inspection. The file holds raw recorded audio.")
    var dumpWav: Bool = false

    @Flag(name: .long, help: "Print the full transcript text to stderr. The text of everything you dictate will appear in logs.")
    var echoTranscripts: Bool = false

    @Flag(name: .long, help: "Print what the accessibility API reports about the focused element on each dictation (debug).")
    var debugFocus: Bool = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Never ask apps to switch their accessibility tree on.",
            discussion: "Chromium and Electron apps keep that tree off until an assistive "
                + "technology asks for it, and their text fields are invisible to parrot until "
                + "they do. Pass this to stop asking; dictation into a browser will then fall "
                + "back to the transcript popover."
        ))
    var noWakeAccessibility: Bool = false

    @Flag(name: .long, help: "Disable the on-screen recording overlay.")
    var noOverlay: Bool = false

    @Flag(name: .long, help: "Mute the active macOS output while recording.")
    var muteOutput: Bool = false

    @Option(name: .long, help: "Model id to use. Defaults to the recommended model.")
    var model: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Push-to-talk modifier to hold.",
            discussion: "Third-party keyboards handle Fn in firmware and never send it to macOS; "
                + "pick another modifier on those. Options: "
                + HotkeyMonitor.Hotkey.allCases.map(\.rawValue).joined(separator: ", ")
                + ". Defaults to whatever was last chosen in the menu bar, else fn."
        ))
    var hotkey: HotkeyMonitor.Hotkey?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "How the transcript is delivered to the focused app.",
            discussion: "paste briefly uses the pasteboard and works in terminals and Electron "
                + "apps; type-unicode leaves the pasteboard untouched but is dropped by some apps."
                + " Defaults to whatever was last chosen in the menu bar, else paste."
        ))
    var injectMode: TextInjector.Mode?

    /// Both purge sites report the same way; the number is the only reason the
    /// user would care that a purge happened at all.
    private func reclaim(_ bytes: Int64) {
        guard bytes > 0 else { return }
        FileHandle.standardError.write(Data(
            "freed \(ModelWeights.describe(bytes: bytes)) of unused models\n".utf8))
    }

    func run() throws {
        // Resolved before the doctor gate: whether the Fn mapping is worth
        // checking at all depends on which modifier we end up watching.
        let settings = SettingsStore()
        let hotkey = settings.resolvedHotkey(flag: self.hotkey)
        let injectMode = settings.resolvedInjectMode(flag: self.injectMode)

        if !skipDoctor {
            let checks = DoctorReport.run(hotkey: hotkey)
            if !DoctorReport.allOK(checks) {
                FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
                DoctorReport.print(checks)
                FileHandle.standardError.write(Data("\nfix the above or pass --skip-doctor\n".utf8))
                throw ExitCode(1)
            }
        }

        let models = ModelStore()
        guard let chosenModel = models.resolved(flag: model) else {
            if let id = model {
                FileHandle.standardError.write(Data("unknown model: \(id)\n".utf8))
                FileHandle.standardError.write(Data("run `parrot models list` to see options.\n".utf8))
                // Exit 0 for the same reason as a missing permission: a bad model id
                // is not transient, and KeepAlive would relaunch us forever.
                throw ExitCode(0)
            }
            FileHandle.standardError.write(Data("no models registered\n".utf8))
            throw ExitCode(1)
        }

        let transcriber = ActiveTranscriber(model: chosenModel)
        let warmupSemaphore = DispatchSemaphore(value: 0)
        var warmupError: Error?
        Task.detached {
            do {
                try await transcriber.warmUp()
            } catch {
                warmupError = error
            }
            warmupSemaphore.signal()
        }
        warmupSemaphore.wait()
        if let warmupError {
            FileHandle.standardError.write(Data("warmup failed: \(warmupError)\n".utf8))
            throw ExitCode(1)
        }

        // Whatever an earlier run left behind is dead weight now that this model
        // is loaded — except the one switched away from, which the user is one
        // menu click from wanting again.
        reclaim(ModelWeights.purge(keeping: [chosenModel, models.previous].compactMap { $0 }))

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let monitor = HotkeyMonitor(hotkey: hotkey, debug: debugHotkey)
        let devices = InputDeviceStore()
        let capture = AudioCapture()
        let outputMute = muteOutput ? OutputMuteController() : nil
        let dumpWav = self.dumpWav
        let echoTranscripts = self.echoTranscripts
        let debugFocus = self.debugFocus
        let wakeAccessibility = !self.noWakeAccessibility
        let overlay: RecordingOverlay? = noOverlay ? nil : MainActor.assumeIsolated { RecordingOverlay() }
        if let overlay {
            capture.onLevel = { level in overlay.pushLevel(level) }
        }
        let menuBar = MainActor.assumeIsolated {
            MenuBarController(model: chosenModel, hotkeyLabel: hotkey.rawValue, devices: devices)
        }
        let fallbackPopover = MainActor.assumeIsolated { TranscriptFallbackPopover() }
        MainActor.assumeIsolated {
            menuBar.onModel = { [weak menuBar] next in
                Task {
                    do {
                        let outgoing = try await transcriber.use(next) { fraction in
                            Task { @MainActor in menuBar?.setSwitchProgress(fraction) }
                        }
                        // Only now: a model that failed to load is not what the
                        // daemon should come back as after a restart.
                        models.selectedID = next.id
                        models.previousID = outgoing?.id
                        reclaim(ModelWeights.purge(keeping: [next, outgoing].compactMap { $0 }))
                        await MainActor.run { menuBar?.setModel(next) }
                    } catch {
                        FileHandle.standardError.write(Data("switch to \(next.id) failed: \(error)\n".utf8))
                        await MainActor.run { menuBar?.setModelFailed(next) }
                    }
                }
            }
        }

        func beginRecording() -> Bool {
            // Chromium and Electron apps only build their accessibility tree
            // once an assistive technology asks. Ask at the start of the
            // dictation, so the tree is ready by the time — a second or more
            // from now — the transcript needs somewhere to land.
            if wakeAccessibility {
                MainActor.assumeIsolated { _ = AccessibilityOptIn.wakeFocusedApp() }
            }
            outputMute?.mute()
            do {
                try capture.start(device: devices.resolved()?.id)
                FileHandle.standardError.write(Data("● recording\n".utf8))
                MainActor.assumeIsolated {
                    fallbackPopover.hide()
                    overlay?.show(.recording)
                    menuBar.setRecording(true)
                }
                return true
            } catch {
                outputMute?.restore()
                FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
                return false
            }
        }

        func finishRecording() {
            let samples = capture.stop()
            outputMute?.restore()
            MainActor.assumeIsolated {
                overlay?.show(.transcribing)
                menuBar.setTranscribing()
            }
            let seconds = Double(samples.count) / AudioCapture.targetSampleRate
            let rms = computeRMS(samples)
            FileHandle.standardError.write(Data(
                String(format: "○ captured %.2fs · rms %.3f\n", seconds, rms).utf8
            ))
            if dumpWav, !samples.isEmpty {
                do {
                    let path = try dumpWavPath()
                    try WAVWriter.write(samples: samples, sampleRate: 16_000, to: path)
                    FileHandle.standardError.write(Data("  wrote \(path)\n".utf8))
                } catch {
                    FileHandle.standardError.write(Data("  wav write failed: \(error)\n".utf8))
                }
            }
            guard !samples.isEmpty else {
                MainActor.assumeIsolated {
                    overlay?.hide()
                    menuBar.setRecording(false)
                }
                return
            }
            Task {
                let started = Date()
                do {
                    let text = try await transcriber.transcribe(samples)
                    let elapsed = Date().timeIntervalSince(started)
                    let line = echoTranscripts
                        ? String(format: "→ %.2fs · %@\n", elapsed, text)
                        : String(format: "→ %.2fs · %ld chars\n", elapsed, text.count)
                    FileHandle.standardError.write(Data(line.utf8))
                    await MainActor.run {
                        overlay?.hide()
                        menuBar.setRecording(false)
                        // Before anything that can hang or refuse: the probe
                        // below spends up to 0.6s in the accessibility API,
                        // twice, on an app that may never answer. Whatever
                        // happens after this line, the dictation is on the
                        // pasteboard. Empty text is left alone in there, which
                        // is why this can run before the guard.
                        TextInjector.copyToPasteboard(text)
                    }
                    guard !text.isEmpty else { return }

                    var probe = await MainActor.run { FocusedTextTarget.probe() }
                    // A tree woken only moments ago may still be building, and
                    // Chromium lets its own lapse when no assistive technology
                    // has been about. One more ask, one beat, one more look —
                    // but never for a password box, where the refusal is the
                    // point.
                    let retry = !probe.isEditable && probe.outcome != .secureField
                        && wakeAccessibility
                    if retry {
                        await MainActor.run { _ = AccessibilityOptIn.wakeFocusedApp(force: true) }
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        probe = await MainActor.run { FocusedTextTarget.probe() }
                    }

                    let resolved = probe
                    await MainActor.run {
                        if debugFocus {
                            FileHandle.standardError.write(
                                Data(resolved.debugLine(retried: retry).utf8))
                        }
                        if resolved.isEditable {
                            TextInjector.inject(text, mode: injectMode)
                        } else {
                            fallbackPopover.show(text)
                        }
                    }
                } catch {
                    FileHandle.standardError.write(Data("transcription failed: \(error)\n".utf8))
                    await MainActor.run {
                        overlay?.hide()
                        menuBar.setRecording(false)
                    }
                }
            }
        }

        // Respect the user's macOS double-click preference, while keeping the
        // recognition window short enough to feel immediate for dictation.
        let doubleTapInterval = min(max(NSEvent.doubleClickInterval, 0.30), 0.50)
        let gestureController = MainActor.assumeIsolated {
            FnDictationGestureController(
                doubleTapInterval: doubleTapInterval,
                startRecording: beginRecording,
                stopRecording: finishRecording,
                showLocked: {
                    FileHandle.standardError.write(
                        Data("🔒 recording locked · tap \(hotkey.rawValue) to stop\n".utf8))
                    overlay?.show(.locked)
                    menuBar.setLockedRecording()
                }
            )
        }

        do {
            try monitor.start { event in
                MainActor.assumeIsolated {
                    gestureController.handle(event)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("failed to register hotkey tap: \(error)\n".utf8))
            FileHandle.standardError.write(Data("run `parrot setup` to configure permissions.\n".utf8))
            // Exit 0: a missing permission is not transient, and the LaunchAgent's
            // KeepAlive would otherwise restart us into an endless prompt loop.
            throw ExitCode(0)
        }

        let cleanUp = {
            MainActor.assumeIsolated {
                gestureController.cancel()
            }
            _ = capture.stop()
            outputMute?.restore()
        }
        let terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: app,
            queue: .main
        ) { _ in
            cleanUp()
        }

        let shutDown = {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            monitor.stop()
            cleanUp()
            NSApp.terminate(nil)
        }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler(handler: shutDown)
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler(handler: shutDown)
        sigterm.resume()
        signal(SIGTERM, SIG_IGN)

        FileHandle.standardError.write(
            Data("listening on \(hotkey.rawValue) hold · model: \(chosenModel.id) · ^C to quit\n".utf8))
        app.run()
        NotificationCenter.default.removeObserver(terminationObserver)
    }
}

/// Destination for `--dump-wav`. Recorded audio is as sensitive as the
/// transcript, so it stays out of world-readable /tmp.
private func dumpWavPath() throws -> String {
    let fm = FileManager.default
    let dir = fm.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/parrot", isDirectory: true)
    try fm.createDirectory(
        at: dir,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    // createDirectory doesn't retighten a directory that already exists.
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

    let path = dir.appendingPathComponent("last-capture.wav").path
    // Pre-create 0600; a plain write would land under the process umask (0644).
    _ = fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
    return path
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, accessibility, and push-to-talk key configuration."
    )

    func run() throws {
        let checks = DoctorReport.run(hotkey: SettingsStore().resolvedHotkey(flag: nil))
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage transcription models.",
        subcommands: [List.self, Download.self]
    )

    struct List: ParsableCommand {
        func run() throws {
            // Column width follows the longest id: `padding(toLength:)` truncates
            // when the string is longer, and a truncated id cannot be copied into
            // `parrot models download`.
            let width = ModelRegistry.shared.map(\.id.count).max() ?? 26
            for m in ModelRegistry.shared {
                let star = m.recommended ? "★" : " "
                let id = m.id.padding(toLength: width, withPad: " ", startingAt: 0)
                let langs = "[\(m.languages.joined(separator: ","))]"
                    .padding(toLength: 9, withPad: " ", startingAt: 0)
                let size = String(format: "%5d MB", m.sizeMB)
                print("\(star) \(id) \(size)  \(langs)  \(m.displayName)")
            }
        }
    }

    struct Download: ParsableCommand {
        @Argument(help: "Model id to download.") var id: String

        func run() throws {
            guard let m = ModelRegistry.find(id) else {
                print("unknown model: \(id)")
                throw ExitCode(1)
            }
            let t = WhisperKitTranscriber(model: m)

            let sem = DispatchSemaphore(value: 0)
            var capturedError: Error?
            Task.detached {
                do { try await t.warmUp() } catch { capturedError = error }
                sem.signal()
            }
            sem.wait()
            if let e = capturedError { throw e }
        }
    }
}
