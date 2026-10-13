import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Watches a single modifier key (default: Fn) and emits press/release edges.
/// Requires Accessibility permission. If the tap fails to register, callers
/// will see an error from `start()`.
final class HotkeyMonitor {
    enum Event: Equatable { case pressed, released, interrupted }
    enum HotkeyError: Error { case tapCreateFailed }

    /// A modifier key usable as push-to-talk.
    ///
    /// `mask` is the flag the modifier raises; `keycode` disambiguates the
    /// left and right instances of a modifier, which share a single flag.
    /// Fn uses no keycode filter — Apple keyboards raise `.maskSecondaryFn`
    /// on their own, and third-party keyboards never send Fn to the host at
    /// all (it is a firmware-local modifier), which is why they need one of
    /// the other options here.
    enum Hotkey: String, CaseIterable {
        case fn
        case rightOption = "right-option"
        case leftOption = "left-option"
        case rightCommand = "right-command"
        case leftCommand = "left-command"
        case rightControl = "right-control"
        case leftControl = "left-control"
        case rightShift = "right-shift"
        case leftShift = "left-shift"

        var mask: CGEventFlags {
            switch self {
            case .fn: return .maskSecondaryFn
            case .rightOption, .leftOption: return .maskAlternate
            case .rightCommand, .leftCommand: return .maskCommand
            case .rightControl, .leftControl: return .maskControl
            case .rightShift, .leftShift: return .maskShift
            }
        }

        /// Virtual keycode of the physical key, where it matters.
        var keycode: Int64? {
            switch self {
            case .fn: return nil
            case .rightOption: return 61
            case .leftOption: return 58
            case .rightCommand: return 54
            case .leftCommand: return 55
            case .rightControl: return 62
            case .leftControl: return 59
            case .rightShift: return 60
            case .leftShift: return 56
            }
        }
    }

    /// Mask of the modifier we treat as the hotkey. Fn = `.maskSecondaryFn`.
    /// Mutable so the modifier can be swapped from the menu bar without the tap
    /// being torn down and rebuilt.
    private var mask: CGEventFlags
    /// When set, only flagsChanged events with this keycode are considered,
    /// so left/right variants of a modifier can be told apart.
    private var keycode: Int64?
    private let debug: Bool
    private var onEvent: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var edges = HotkeyEdgeState()
    private var tapContext: HotkeyTapContext?

    init(mask: CGEventFlags = .maskSecondaryFn, keycode: Int64? = nil, debug: Bool = false) {
        self.mask = mask
        self.keycode = keycode
        self.debug = debug
    }

    /// Resolve a named modifier to the flag and keycode it is watched by.
    convenience init(hotkey: Hotkey, debug: Bool = false) {
        self.init(mask: hotkey.mask, keycode: hotkey.keycode, debug: debug)
    }

    /// Watch a different modifier from now on. The tap already receives every
    /// flagsChanged event, so only the comparison in `handle()` depends on the
    /// choice and nothing has to be restarted.
    func setHotkey(_ hotkey: Hotkey) {
        mask = hotkey.mask
        keycode = hotkey.keycode
        // A key held under the old modifier can never send a release we would
        // recognise, so the reset `reEnable()` does applies here too: without
        // it a recording started before the switch never ends.
        if edges.isPressed, let session = edges.session,
           let interruption = edges.interrupt(session: session) {
            onEvent?(interruption)
        }
    }

    func start(onEvent: @escaping (Event) -> Void) throws {
        // Every start owns a fresh edge session, even when a physical release
        // was lost while the previous tap was stopped.
        stop()
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if !trusted {
            FileHandle.standardError.write(Data(
                "accessibility not granted. system prompt opened; grant access, then quit and relaunch plume.\n".utf8
            ))
            throw HotkeyError.tapCreateFailed
        }

        // Only flagsChanged is ever acted on in `handle`. keyDown/keyUp are
        // subscribed *only* under --debug-hotkey: listening to every keystroke
        // system-wide costs main-thread work, raises the odds macOS disables
        // the tap for timeout, and needlessly exposes typed content (including
        // password fields) to an Accessibility-privileged process.
        var mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        if debug {
            mask |=
                (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        }
        self.onEvent = onEvent
        let context = HotkeyTapContext(monitor: self, session: edges.beginSession())
        tapContext = context
        let userInfo = Unmanaged.passUnretained(context).toOpaque()

        // .cgSessionEventTap is the right level for an accessibility-granted
        // user process (.cghidEventTap requires root).
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: hotkeyCallback,
                userInfo: userInfo
            )
        else {
            stop()
            throw HotkeyError.tapCreateFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        // Invalidate delivery first: already queued callbacks keep their old
        // session and cannot alter a stopped or newly restarted monitor.
        edges.endSession()
        onEvent = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        tapContext = nil
    }

    /// Called from the tap callback when macOS disables our tap. Without this
    /// the process keeps running, the menu bar icon stays put, and the hotkey
    /// silently does nothing until the user restarts plume.
    fileprivate func reEnable(session: UUID) {
        guard edges.isCurrent(session), let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        // The disable swallowed whatever edges happened while it was down, so
        // the release that ends an in-flight recording may never arrive. Reset
        // the edge state and tell the caller, rather than staying stuck
        // believing the key is still held.
        if let interruption = edges.interrupt(session: session) {
            onEvent?(interruption)
        }
        FileHandle.standardError.write(Data(
            "event tap was disabled by the system, re-enabled\n".utf8
        ))
    }

    fileprivate func handle(type: CGEventType, event: CGEvent, session: UUID) {
        guard edges.isCurrent(session) else { return }
        if debug {
            let flags = event.flags
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            FileHandle.standardError.write(
                Data(
                    "  [debug] type=\(type.rawValue) keycode=\(keycode) flags=\(String(flags.rawValue, radix: 16))\n"
                        .utf8
                ))
        }
        guard type == .flagsChanged else { return }
        // Left/right instances of a modifier share one flag, so filter on the
        // physical key before reading the flag.
        if let keycode, event.getIntegerValueField(.keyboardEventKeycode) != keycode { return }
        let pressed = event.flags.contains(mask)
        if let edge = edges.receive(pressed: pressed, session: session) {
            onEvent?(edge)
        }
    }
}

/// The production input edge seam. Synthetic tests use the same session and
/// transition rules without creating an event tap or requesting permissions.
struct HotkeyEdgeState {
    private(set) var session: UUID?
    private(set) var isPressed = false

    mutating func beginSession() -> UUID {
        let next = UUID()
        session = next
        isPressed = false
        return next
    }

    mutating func endSession() {
        session = nil
        isPressed = false
    }

    func isCurrent(_ candidate: UUID) -> Bool { session == candidate }

    mutating func receive(pressed: Bool, session: UUID) -> HotkeyMonitor.Event? {
        guard isCurrent(session), pressed != isPressed else { return nil }
        isPressed = pressed
        return pressed ? .pressed : .released
    }

    mutating func interrupt(session: UUID) -> HotkeyMonitor.Event? {
        guard isCurrent(session) else { return nil }
        isPressed = false
        return .interrupted
    }
}

/// Each native tap keeps its own immutable token. Queued closures retain this
/// context after stop invalidates the port, so an old callback can never borrow
/// the token of a replacement tap.
private final class HotkeyTapContext {
    weak var monitor: HotkeyMonitor?
    let session: UUID
    init(monitor: HotkeyMonitor, session: UUID) {
        self.monitor = monitor
        self.session = session
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<HotkeyTapContext>.fromOpaque(userInfo).takeUnretainedValue()
    guard let monitor = context.monitor else { return Unmanaged.passUnretained(event) }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // The tap must be re-enabled from the run loop that owns it.
        DispatchQueue.main.async { [weak monitor] in monitor?.reEnable(session: context.session) }
        return Unmanaged.passUnretained(event)
    }

    let copy = event.copy()
    DispatchQueue.main.async { [weak monitor] in
        if let copy {
            monitor?.handle(type: type, event: copy, session: context.session)
        }
    }
    return Unmanaged.passUnretained(event)
}
