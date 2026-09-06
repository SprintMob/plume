import AppKit
import CoreGraphics
import Foundation

/// Delivers the transcript: to the pasteboard always, and to the focused app when
/// there is a field to speak into.
///
/// The pasteboard write is the guarantee. Every non-empty transcript that reaches
/// this type is on the pasteboard when the call returns — in both modes, whether
/// or not the focused app takes what we send it. What the user had copied is
/// replaced and never put back: that is the deliberate trade, and it is what a
/// clipboard manager is for. See [ADR-0006](../../../docs/adr/0006-transcript-always-on-the-pasteboard.md).
@MainActor
enum TextInjector {
    enum Mode: String, CaseIterable {
        /// Post ⌘V and let the focused app read the pasteboard. Terminals and
        /// Electron apps read key events in ways that drop synthesized unicode,
        /// but all of them implement paste.
        case paste
        /// Synthesize the characters directly. Slower, and silently loses text in
        /// apps that ignore unicode-string key events. The transcript reaches the
        /// pasteboard either way; the mode picks only how it is delivered.
        case typeUnicode = "type-unicode"
    }

    /// What a delivery asks of the keyboard, stated as an intent rather than as a
    /// `CGEvent`. Posting needs the accessibility grant and lands in whatever
    /// window has focus — a `swift test` run included — so this is the seam the
    /// tests replace, and no test ever posts anything.
    enum KeyStroke: Equatable {
        case commandV
        case unicode([UniChar])
    }

    /// Puts the transcript where the user can reach it. The daemon calls this
    /// before the focus probe, so a probe that hangs, a password box, or an app
    /// that swallows synthesized keys cannot cost the user their dictation.
    /// Whatever was copied before is replaced and never put back.
    ///
    /// Empty text is left alone: a dictation that produced nothing must not clear
    /// the pasteboard, and this guard is what lets the call site copy before it
    /// has checked. A pasteboard already holding exactly this string is left
    /// alone too, so one dictation is one entry in a clipboard manager rather
    /// than two identical ones.
    static func copyToPasteboard(_ text: String, to pasteboard: NSPasteboard = .general) {
        guard !text.isEmpty else { return }
        guard pasteboard.string(forType: .string) != text else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Delivers the transcript to whatever holds the keyboard focus. The
    /// pasteboard write comes first in both modes: an injection the app drops
    /// still leaves the user one ⌘V from their text.
    static func inject(
        _ text: String,
        mode: Mode = .paste,
        to pasteboard: NSPasteboard = .general,
        post: (KeyStroke) -> Void = postToSession
    ) {
        guard !text.isEmpty else { return }
        copyToPasteboard(text, to: pasteboard)
        switch mode {
        case .paste:
            post(.commandV)
        case .typeUnicode:
            for chunk in chunks(of: text) { post(.unicode(chunk)) }
        }
    }

    /// `keyboardSetUnicodeString` has a per-event limit of around 20 UTF-16
    /// units, so a transcript goes out in chunks. Units, not characters: units
    /// are what the API counts. Pure, and the only decision left in the type,
    /// which is where its test lives.
    nonisolated static func chunks(of text: String, size: Int = 20) -> [[UniChar]] {
        let units = Array(text.utf16)
        return stride(from: 0, to: units.count, by: size).map { start in
            Array(units[start..<min(start + size, units.count)])
        }
    }

    // MARK: - Posting

    /// The production adapter: an intent, turned into posted CoreGraphics events.
    nonisolated static func postToSession(_ stroke: KeyStroke) {
        switch stroke {
        case .commandV: postCommandV()
        case .unicode(let chunk): postUnicode(chunk)
        }
    }

    private nonisolated static func postCommandV() {
        // Keycode 9 is `v` on the ASCII-capable layout macOS uses to match
        // command key equivalents, so this stays correct on non-QWERTY layouts.
        let vKey: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        // Set flags explicitly: any modifier the user is still physically
        // holding would otherwise ride along and turn this into a different
        // shortcut.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    private nonisolated static func postUnicode(_ chunk: [UniChar]) {
        var chunk = chunk
        let length = chunk.count
        guard length > 0 else { return }

        // NOTE: posting to `.cgSessionEventTap` collides with HotkeyMonitor's
        // own listen-only tap, which is installed at `.headInsertEventTap` on
        // that same `.cgSessionEventTap` location — the synthetic keystrokes
        // get silently swallowed before reaching the focused app. Posting to
        // `.cgAnnotatedSessionEventTap` (further down the pipeline, past that
        // tap) delivers reliably. Confirmed empirically: cghidEventTap and
        // cgSessionEventTap both silently no-op here; cgAnnotatedSessionEventTap
        // lands in the focused text field every time.
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
        down?.post(tap: .cgAnnotatedSessionEventTap)

        // The keyUp deliberately carries no unicode payload: attaching the same
        // string to both events makes the focused app insert the text twice.
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
