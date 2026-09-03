import AppKit
import ApplicationServices
import Foundation

/// Asks the app under the cursor to switch its accessibility tree on.
///
/// Chromium apps (Chrome, Arc, Brave, Edge) and Electron apps (Slack, VS Code,
/// Notion) ship with that tree switched off and only build it once an assistive
/// technology announces itself. Until one does, a focused `<input>` is invisible
/// over the accessibility API: `FocusedTextTarget` sees nothing editable and
/// every dictation into a browser lands in the fallback popover instead of the
/// field the user is looking at.
///
/// The two families watch different attributes. Chromium wakes on
/// `AXEnhancedUserInterface` — the flag VoiceOver sets — and Electron wakes on
/// `AXManualAccessibility`. Neither is declared in a header; they are private
/// names those apps look for, so both are spelled out below. Setting one on an
/// app that does not use it fails with `kAXErrorAttributeUnsupported`, which
/// costs nothing.
///
/// Do not drop this without reading ADR-0005 — the focus probe cannot see into
/// a browser without it.
@MainActor
enum AccessibilityOptIn {
    /// What Electron looks for.
    private static let manualAccessibility = "AXManualAccessibility" as CFString
    /// What Chromium looks for, and what VoiceOver sets.
    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString

    private static var wokenPIDs: Set<pid_t> = []
    private static var observingTermination = false

    /// Wakes the app owning the focused element. Skipped when that app has
    /// already been woken, unless `force` is set — Chromium lets its tree lapse
    /// again after a spell with no assistive technology about, so a probe that
    /// just came back empty is reason enough to ask twice.
    ///
    /// Returns the pid it asked, or nil when there was nothing to ask.
    @discardableResult
    static func wakeFocusedApp(force: Bool = false) -> pid_t? {
        guard let pid = focusedApplicationPID() else { return nil }
        guard force || !wokenPIDs.contains(pid) else { return nil }

        observeTermination()
        wokenPIDs.insert(pid)

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, manualAccessibility, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, enhancedUserInterface, kCFBooleanTrue)
        return pid
    }

    /// The pid owning the focused element, which is not always the frontmost
    /// app — a non-activating panel can hold the focus while another app stays
    /// frontmost. Falls back to the frontmost app when the accessibility API
    /// will not say.
    private static func focusedApplicationPID() -> pid_t? {
        let ours = ProcessInfo.processInfo.processIdentifier
        var pid: pid_t?

        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &value
        ) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            var focusedPID: pid_t = 0
            if AXUIElementGetPid(value as! AXUIElement, &focusedPID) == .success, focusedPID > 0 {
                pid = focusedPID
            }
        }

        let resolved = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Waking ourselves would tell us nothing we do not already know.
        return resolved == ours ? nil : resolved
    }

    /// Forget pids as their apps quit, so a relaunch under a recycled pid is
    /// woken again rather than assumed awake.
    private static func observeTermination() {
        guard !observingTermination else { return }
        observingTermination = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { _ = wokenPIDs.remove(pid) }
        }
    }
}
