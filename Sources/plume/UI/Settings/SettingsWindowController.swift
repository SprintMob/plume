import AppKit
import SwiftUI

/// The settings window: one sidebar, five sections, everything plume can be
/// told from a mouse.
///
/// Opened from the menu bar and from ⌘, — there is no `plume settings`
/// subcommand, because a second process cannot open the running daemon's
/// window without an IPC channel that would exist for this one thing.
///
/// Contradicts `docs/architecture.md`'s "no settings window" non-goal, on
/// purpose. See ADR-0007.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let state: DaemonState
    private let devices: InputDeviceStore
    private let history: TranscriptHistory

    init(state: DaemonState, devices: InputDeviceStore, history: TranscriptHistory) {
        self.state = state
        self.devices = devices
        self.history = history
        super.init()
    }

    func show() {
        ensureWindow()
        guard let window else { return }

        // `.accessory` gives the daemon no menu bar of its own, and a window
        // without one has no ⌘C, no ⌘V and no ⌘W — dead shortcuts in the
        // history search field. `.regular` for as long as the window is up is
        // what makes it behave like a window; the dock icon that comes with it
        // is the honest signal that plume has something on screen.
        NSApp.setActivationPolicy(.regular)
        installMainMenuIfNeeded()
        // AppKit does not always rebuild the menu bar synchronously after a
        // policy change. Activating on the next turn of the run loop is what
        // makes the new menu bar the one that appears.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func showFromMenu() {
        show()
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a daemon with no dock icon. The window itself is kept: every
        // section reads live state, so there is nothing to rebuild.
        NSApp.setActivationPolicy(.accessory)
    }

    private func ensureWindow() {
        if window != nil { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Plume"
        // The sidebar's material runs up behind the traffic lights, the way
        // every macOS sidebar window looks.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 780, height: 520)
        // Held in this property, so AppKit must not release it on close.
        window.isReleasedWhenClosed = false
        window.delegate = self

        // `NSHostingController` rather than the `NSHostingView` the overlay and
        // the fallback panel use: this is a real window with a first responder
        // and keyboard commands, and the controller is what puts SwiftUI in the
        // responder chain.
        window.contentViewController = NSHostingController(
            rootView: SettingsRootView(state: state, devices: devices, history: history)
        )

        // Size and position survive a close; centred the first time.
        if !window.setFrameUsingName("plume.settings") {
            window.center()
        }
        window.setFrameAutosaveName("plume.settings")

        self.window = window
    }

    /// There is no `.app` bundle, so there is no MainMenu.nib and `.regular`
    /// would otherwise show an empty menu bar. Built once, kept for the life of
    /// the process.
    private func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }

        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Plume")
        appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(showFromMenu),
            keyEquivalent: ","
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Plume",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        appMenu.addItem(
            withTitle: "Quit Plume",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // The reason the main menu exists at all: these four are what a text
        // field needs to be usable.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.miniaturize(_:)),
            keyEquivalent: "m")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
