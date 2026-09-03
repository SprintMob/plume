import AppKit

/// Status bar item in the top-right of the menu bar. Shows dictation state at
/// a glance and gives the fastest route to the choices the settings window also
/// offers — two clicks to another microphone, without a window.
///
/// It holds no state of its own: every label and every tick is read from
/// `DaemonState` in `menuWillOpen`. A closed menu shows nothing, so there is
/// nothing to keep up to date in between.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let modelLabel: NSMenuItem
    private let stateLabel: NSMenuItem
    private let modelItem: NSMenuItem
    private let inputItem: NSMenuItem
    private let hotkeyItem: NSMenuItem
    private let injectItem: NSMenuItem
    private let state: DaemonState
    private let devices: InputDeviceStore
    /// Set after construction: the window outlives any one menu, so the daemon
    /// owns it and hands the menu a way to raise it.
    var onOpenSettings: (() -> Void)?

    init(state: DaemonState, devices: InputDeviceStore) {
        self.state = state
        self.devices = devices
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())

        stateLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        modelLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        modelLabel.isEnabled = false
        menu.addItem(modelLabel)

        modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        modelMenu.autoenablesItems = false
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        inputItem = NSMenuItem(title: "Input", action: nil, keyEquivalent: "")
        let inputMenu = NSMenu()
        inputMenu.autoenablesItems = false
        inputItem.submenu = inputMenu
        menu.addItem(inputItem)

        hotkeyItem = NSMenuItem(title: "Hold-to-talk key", action: nil, keyEquivalent: "")
        let hotkeyMenu = NSMenu()
        hotkeyMenu.autoenablesItems = false
        hotkeyItem.submenu = hotkeyMenu
        menu.addItem(hotkeyItem)

        injectItem = NSMenuItem(title: "Injection", action: nil, keyEquivalent: "")
        let injectMenu = NSMenu()
        injectMenu.autoenablesItems = false
        injectItem.submenu = injectMenu
        menu.addItem(injectItem)

        let example = NSMenuItem(
            title: "Edit dictation examples…",
            action: #selector(editDictationExamples),
            keyEquivalent: "")
        menu.addItem(example)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit parrot",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        super.init()

        settings.target = self
        example.target = self
        quit.target = self
        menu.addItem(quit)

        // Rebuild the lists on open: a switch in flight and a newly plugged-in
        // mic are both reflected without the menu holding its own copy of the
        // state or watching CoreAudio for device changes.
        menu.delegate = self

        statusItem.menu = menu
        refreshLabels()
        configureButton()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    /// Creates the file on first use so the format is explained where it is
    /// edited, then hands it to whatever opens .txt.
    @objc private func editDictationExamples() {
        do {
            try DictationExamples.ensureFileExists()
            NSWorkspace.shared.open(DictationExamples.file)
        } catch {
            FileHandle.standardError.write(Data("could not open dictation example: \(error)\n".utf8))
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLabels()
        rebuildInputMenu()
        rebuildHotkeyMenu()
        rebuildInjectMenu()
        rebuildModelMenu()
    }

    // MARK: - Labels

    private func refreshLabels() {
        stateLabel.title = stateTitle
        modelLabel.title = modelTitle
    }

    private var stateTitle: String {
        switch state.dictation {
        case .idle:
            return "idle · hold \(state.hotkey.rawValue) or double-tap to lock"
        case .recording:
            return "● recording"
        case .locked:
            return "🔒 recording · tap \(state.hotkey.rawValue) to stop"
        case .transcribing:
            return "transcribing…"
        }
    }

    /// A switch in flight is reported ahead of the model still loaded: the
    /// choice is taken, and pretending otherwise is what made the menu look
    /// like it ignored the click.
    private var modelTitle: String {
        if let pending = state.pendingModel {
            guard let fraction = state.switchProgress, fraction < 1 else {
                return "loading \(pending.id)…"
            }
            return String(format: "downloading %@… %.0f%%", pending.id, fraction * 100)
        }
        if let failed = state.failedModel {
            return "model: \(state.model.id) · \(failed.id) failed"
        }
        return "model: \(state.model.id)"
    }

    // MARK: - Submenus

    private func rebuildModelMenu() {
        guard let modelSubmenu = modelItem.submenu else { return }
        modelSubmenu.removeAllItems()
        for row in ModelCatalog.rows(
            active: state.model,
            pending: state.pendingModel,
            progress: state.switchProgress,
            failed: state.failedModel)
        {
            let item = NSMenuItem(
                title: "\(row.model.displayName) · \(row.model.sizeMB) MB",
                action: #selector(modelSelected),
                keyEquivalent: "")
            item.target = self
            item.representedObject = row.model.id
            // A dash rather than a tick while it arrives: the choice is taken,
            // the model is not ready.
            switch row.status {
            case .downloading, .loading: item.state = .mixed
            case .active: item.state = .on
            case .installed, .available, .failed: item.state = .off
            }
            item.isEnabled = row.isSelectable
            modelSubmenu.addItem(item)
        }
    }

    /// Hands the choice to the daemon, which loads it before dropping the model
    /// in use. Every label follows on the next open.
    @objc private func modelSelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let chosen = ModelRegistry.find(id)
        else { return }
        state.selectModel(chosen)
    }

    private func rebuildInputMenu() {
        guard let submenu = inputItem.submenu else { return }
        submenu.removeAllItems()

        let selected = devices.selectedUID
        submenu.addItem(inputChoice(title: "Same as System", uid: nil, checked: selected == nil))
        submenu.addItem(.separator())
        for device in devices.available() {
            submenu.addItem(inputChoice(title: device.name, uid: device.uid, checked: device.uid == selected))
        }
    }

    private func inputChoice(title: String, uid: String?, checked: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(inputSelected), keyEquivalent: "")
        item.target = self
        item.representedObject = uid
        item.state = checked ? .on : .off
        return item
    }

    /// Only writes the preference — the next recording resolves it, so there is
    /// nothing to notify.
    @objc private func inputSelected(_ sender: NSMenuItem) {
        devices.selectedUID = sender.representedObject as? String
    }

    private func rebuildHotkeyMenu() {
        guard let submenu = hotkeyItem.submenu else { return }
        submenu.removeAllItems()
        for candidate in HotkeyMonitor.Hotkey.allCases {
            let item = NSMenuItem(
                title: candidate.rawValue,
                action: #selector(hotkeySelected),
                keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.rawValue
            item.state = candidate == state.hotkey ? .on : .off
            submenu.addItem(item)
        }
    }

    /// Unlike a model switch there is no load that can fail, so telling the tap
    /// and recording the choice happen in one go — both inside `DaemonState`.
    @objc private func hotkeySelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let chosen = HotkeyMonitor.Hotkey(rawValue: raw)
        else { return }
        state.hotkey = chosen
    }

    private func rebuildInjectMenu() {
        guard let submenu = injectItem.submenu else { return }
        submenu.removeAllItems()
        for candidate in TextInjector.Mode.allCases {
            let item = NSMenuItem(
                title: candidate.rawValue,
                action: #selector(injectSelected),
                keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.rawValue
            item.state = candidate == state.injectMode ? .on : .off
            submenu.addItem(item)
        }
    }

    /// Like the input device: written down and read fresh at the next
    /// injection, so there is nothing to notify.
    @objc private func injectSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let chosen = TextInjector.Mode(rawValue: raw)
        else { return }
        state.injectMode = chosen
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = Self.birdImage()
        image?.isTemplate = true
        button.image = image
    }

    // Inlined Lucide bird SVG. Keeping it in source means the executable has
    // no separate resource bundle to install alongside it — true single-binary.
    private static let birdSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
    viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" \
    stroke-linecap="round" stroke-linejoin="round">\
    <path d="M16 7h.01"/>\
    <path d="M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/>\
    <path d="m20 7 2 .5-2 .5"/>\
    <path d="M10 18v3"/>\
    <path d="M14 17.75V21"/>\
    <path d="M7 18a6 6 0 0 0 3.84-10.61"/>\
    </svg>
    """

    private static func birdImage() -> NSImage? {
        guard let data = birdSVG.data(using: .utf8),
              let image = NSImage(data: data)
        else { return nil }
        // Menu-bar status icons are nominally 18pt tall; size the SVG to match.
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
