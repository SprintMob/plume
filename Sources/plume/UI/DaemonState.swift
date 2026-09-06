import Foundation

/// The daemon's live state, and the remembered choices that steer it, shared by
/// every surface that shows them.
///
/// While the menu bar was the only surface it held this itself, and the daemon
/// read `menuBar.injectMode` at every injection. Two surfaces cannot both hold
/// it — the window would have to ask the menu bar what the injection mode is —
/// so it moved here and the menu bar became a reader like the window. See
/// ADR-0007.
///
/// Writing a remembered choice persists it: a pick beats whatever flag the
/// launch passed, because the flag is the starting value, not a lock.
@MainActor
final class DaemonState: ObservableObject {
    enum Dictation: Equatable {
        case idle
        case recording
        case locked
        case transcribing
    }

    @Published private(set) var dictation: Dictation = .idle

    // MARK: - The model

    @Published private(set) var model: TranscriptionModel
    /// The model being switched to. Set on click so both surfaces answer the
    /// click rather than the download, which can take minutes.
    @Published private(set) var pendingModel: TranscriptionModel?
    /// Download fraction — the only part of a switch either engine reports.
    @Published private(set) var switchProgress: Double?
    /// The model the last switch failed on. Cleared by the next attempt.
    @Published private(set) var failedModel: TranscriptionModel?

    // MARK: - Remembered choices

    @Published var hotkey: HotkeyMonitor.Hotkey {
        didSet {
            guard hotkey != oldValue else { return }
            settings.hotkey = hotkey
            onHotkey?(hotkey)
        }
    }

    /// Read fresh at each injection rather than pushed to the daemon: there is
    /// nothing to notify.
    @Published var injectMode: TextInjector.Mode {
        didSet {
            guard injectMode != oldValue else { return }
            settings.injectMode = injectMode
        }
    }

    @Published var overlayEnabled: Bool {
        didSet {
            guard overlayEnabled != oldValue else { return }
            settings.overlay = overlayEnabled
        }
    }

    @Published var muteOutputEnabled: Bool {
        didSet {
            guard muteOutputEnabled != oldValue else { return }
            settings.muteOutput = muteOutputEnabled
        }
    }

    @Published var sessionHistoryEnabled: Bool {
        didSet {
            guard sessionHistoryEnabled != oldValue else { return }
            settings.sessionHistory = sessionHistoryEnabled
        }
    }

    // MARK: - Wiring

    /// Set after construction: switching needs the daemon, and the daemon needs
    /// the state it reports back into.
    var onModel: ((TranscriptionModel) -> Void)?
    /// Set after construction, like `onModel`: swapping the modifier means
    /// telling the live event tap, which only the daemon holds.
    var onHotkey: ((HotkeyMonitor.Hotkey) -> Void)?

    private let settings: SettingsStore

    init(
        model: TranscriptionModel,
        hotkey: HotkeyMonitor.Hotkey,
        injectMode: TextInjector.Mode,
        overlayEnabled: Bool,
        muteOutputEnabled: Bool,
        sessionHistoryEnabled: Bool,
        settings: SettingsStore
    ) {
        self.model = model
        self.hotkey = hotkey
        self.injectMode = injectMode
        self.overlayEnabled = overlayEnabled
        self.muteOutputEnabled = muteOutputEnabled
        self.sessionHistoryEnabled = sessionHistoryEnabled
        self.settings = settings
        // `didSet` does not run during init, which is the point: the values
        // above are what the flags and the store already resolved to, and
        // writing them back would turn a one-off `--hotkey` into a choice.
    }

    // MARK: - What the daemon reports

    func setDictation(_ next: Dictation) {
        dictation = next
    }

    /// Entry point for both surfaces. Records the choice, then hands it to the
    /// daemon, which loads the new model before dropping the one in use.
    func selectModel(_ next: TranscriptionModel) {
        guard next.id != model.id, pendingModel == nil else { return }
        pendingModel = next
        switchProgress = nil
        failedModel = nil
        onModel?(next)
    }

    func switchProgressed(_ fraction: Double) {
        guard pendingModel != nil else { return }
        switchProgress = fraction
    }

    func switched(to next: TranscriptionModel) {
        model = next
        pendingModel = nil
        switchProgress = nil
        failedModel = nil
    }

    func switchFailed(_ attempted: TranscriptionModel) {
        pendingModel = nil
        switchProgress = nil
        failedModel = attempted
    }
}
