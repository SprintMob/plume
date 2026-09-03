import Foundation

/// The settings a person changes from the menu bar and expects to still be
/// there next login: which modifier starts a dictation, and how the
/// transcript is delivered.
///
/// `--hotkey` and `--inject-mode` still win for the launch that passes them, the
/// same way `--model` does, so a one-off run can try a modifier without changing
/// what the daemon comes back as.
final class SettingsStore {
    private static let hotkeyKey = "hotkey"
    private static let injectModeKey = "injectMode"

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

    /// Modifier to listen on: the flag, else the remembered choice, else Fn.
    func resolvedHotkey(flag: HotkeyMonitor.Hotkey?) -> HotkeyMonitor.Hotkey {
        flag ?? hotkey ?? .fn
    }

    /// How to deliver the transcript: the flag, else the remembered choice, else
    /// paste, which is the mode that works everywhere.
    func resolvedInjectMode(flag: TextInjector.Mode?) -> TextInjector.Mode {
        flag ?? injectMode ?? .paste
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
}
