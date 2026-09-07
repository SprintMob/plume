import Foundation

/// The settings a person changes from the menu bar or the settings window and
/// expects to still be there next login: which modifier starts a dictation, how
/// the transcript is delivered, whether the overlay shows, whether system audio
/// is muted while dictating, and whether the session history is kept.
///
/// `--hotkey` and `--inject-mode` still win for the launch that passes them, the
/// same way `--model` does, so a one-off run can try a modifier without changing
/// what the daemon comes back as.
final class SettingsStore {
    private static let hotkeyKey = "hotkey"
    private static let injectModeKey = "injectMode"
    private static let overlayKey = "overlay"
    private static let muteOutputKey = "muteOutput"
    private static let sessionHistoryKey = "sessionHistory"

    /// Every key this store writes, so `Migration` carries them without anyone
    /// having to remember to add them there. A store that gains a key gains
    /// migration with it.
    static let migratableKeys = [
        hotkeyKey, injectModeKey, overlayKey, muteOutputKey, sessionHistoryKey,
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hotkey: HotkeyMonitor.Hotkey? {
        get { read(Self.hotkeyKey) }
        set { write(newValue?.rawValue, to: Self.hotkeyKey) }
    }

    var injectMode: TextInjector.Mode? {
        get { read(Self.injectModeKey) }
        set { write(newValue?.rawValue, to: Self.injectModeKey) }
    }

    var overlay: Bool? {
        get { readBool(Self.overlayKey) }
        set { writeBool(newValue, to: Self.overlayKey) }
    }

    var muteOutput: Bool? {
        get { readBool(Self.muteOutputKey) }
        set { writeBool(newValue, to: Self.muteOutputKey) }
    }

    var sessionHistory: Bool? {
        get { readBool(Self.sessionHistoryKey) }
        set { writeBool(newValue, to: Self.sessionHistoryKey) }
    }

    /// Modifier to listen on: the flag, else the remembered choice, else Fn.
    func resolvedHotkey(flag: HotkeyMonitor.Hotkey?) -> HotkeyMonitor.Hotkey {
        flag ?? hotkey ?? .fn
    }

    /// How to deliver the transcript: the flag, else the remembered choice, else
    /// paste, which is the mode that works everywhere.
    func resolvedInjectMode(flag: TextInjector.Mode?) -> TextInjector.Mode {
        flag ?? injectMode ?? .paste
    }

    /// Whether the dictation overlay shows: `--no-overlay` for the launch that
    /// passes it, else the remembered choice, else shown.
    ///
    /// The flag only reaches in one direction — there is no `--overlay` — so it
    /// can force the pill off for a run but never force it back on.
    func resolvedOverlay(disabledByFlag: Bool) -> Bool {
        disabledByFlag ? false : (overlay ?? true)
    }

    /// Whether system audio is muted for the length of a dictation: the flag,
    /// else the remembered choice, else left playing. `--mute-output` reaches
    /// only towards muting, the mirror of `--no-overlay`.
    func resolvedMuteOutput(forcedByFlag: Bool) -> Bool {
        forcedByFlag ? true : (muteOutput ?? false)
    }

    /// Whether finished dictations are kept in the session history. No flag:
    /// the history is a window feature, and the window is the only place it can
    /// be read.
    func resolvedSessionHistory() -> Bool {
        sessionHistory ?? true
    }

    /// A remembered value that no longer names a case falls through to the
    /// default instead of failing the launch, the same way `ModelStore` treats
    /// a model id that has left the registry.
    private func read<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:))
    }

    private func write(_ rawValue: String?, to key: String) {
        if let rawValue {
            defaults.set(rawValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// `object(forKey:)` rather than `bool(forKey:)`, which answers `false` for
    /// a key that was never written and would make "off" indistinguishable from
    /// "not chosen yet" — the difference the defaults above turn on.
    private func readBool(_ key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    private func writeBool(_ value: Bool?, to key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
