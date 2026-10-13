import Foundation

/// Required startup facts only. Optional doctor warnings remain diagnostics.
struct StartupReadiness: Equatable {
    var installedLocation = true
    var microphone = false
    var accessibility = false
    var fnConfigured = false
    var conflictingBundle = false

    func permitsPreparation(hotkey: HotkeyMonitor.Hotkey) -> Bool {
        installedLocation && microphone && accessibility
            && (hotkey != .fn || fnConfigured) && !conflictingBundle
    }
}

enum Preparation: Equatable {
    case waiting
    case downloading(Double?)
    case loading
    case ready
    case failed(String)

    var isRunning: Bool {
        switch self { case .downloading, .loading: return true; default: return false }
    }
    var description: String {
        switch self {
        case .waiting: return "Setup required"
        case .downloading(let fraction):
            return fraction.map { "Downloading model · \(Int($0 * 100))%" } ?? "Preparing model…"
        case .loading: return "Loading model…"
        case .ready: return "Ready"
        case .failed(let message): return "Preparation failed: \(message)"
        }
    }
}

final class OnboardingStore {
    private let defaults: UserDefaults
    private static let key = "onboardingCompleted"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var completed: Bool { defaults.bool(forKey: Self.key) }
    @discardableResult
    func finish(ready: Bool) -> Bool {
        guard ready else { return false }
        defaults.set(true, forKey: Self.key)
        return true
    }
}

/// A transient bundle must never become the identity registered with TCC or launchd.
enum InstallationLocation {
    static func isTransient(_ url: URL, readOnly: Bool = false) -> Bool {
        let path = url.standardizedFileURL.path
        return readOnly || path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }
}
