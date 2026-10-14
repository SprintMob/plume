import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

/// Injected effects keep startup tests away from host permissions and model stores.
struct StartupServices {
    var snapshot: (HotkeyMonitor.Hotkey) async -> StartupReadiness
    var warmUp: (@escaping @Sendable (Double) -> Void) async throws -> Void
    var requestMicrophone: () -> Void
    var requestAccessibility: () -> Void
    var setLogin: (Bool) throws -> Void
    var isLoginEnabled: () -> Bool = { false }

    static func live(transcriber: ActiveTranscriber, bundled: Bool) -> Self {
        Self(snapshot: { hotkey in
            await Task.detached {
                let url = Bundle.main.bundleURL
                let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
                let fn = DoctorReport.checkFnKeyMapping()
                let fnOK: Bool
                if case .ok = fn.status { fnOK = true } else { fnOK = false }
                return StartupReadiness(
                    installedLocation: !bundled || !InstallationLocation.isTransient(url, readOnly: readOnly),
                    microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                    accessibility: AXIsProcessTrusted(), fnConfigured: fnOK,
                    conflictingBundle: bundled && !DaemonSingleton.otherRunningBundles().isEmpty)
            }.value
        }, warmUp: { progress in
            try await transcriber.warmUp(onProgress: progress)
        }, requestMicrophone: {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }, requestAccessibility: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }, setLogin: { enabled in
            if enabled { try Install.writeAgent(logFile: false, restartLoaded: false) }
            else { try Install.removeAgent() }
        }, isLoginEnabled: { Install.isAgentInstalled })
    }
}

@MainActor
final class StartupController: NSObject, ObservableObject, NSApplicationDelegate, NSWindowDelegate {
    enum Step: Int { case welcome, permissions, hotkey, model, test }
    @Published private(set) var step: Step = .welcome
    @Published private(set) var completed: Bool
    @Published private(set) var checking = false
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginError: String?
    private let state: DaemonState
    private let store: OnboardingStore
    private let services: StartupServices
    private let showSettings: () -> Void
    private var window: NSWindow?
    private var observer: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var preparationTask: Task<Void, Never>?
    private var hasStarted = false
    private var hasRefreshed = false
    private let presentWindow: Bool
    private(set) var presentationCount = 0

    init(state: DaemonState, store: OnboardingStore = OnboardingStore(),
         services: StartupServices, presentWindow: Bool = true, showSettings: @escaping () -> Void) {
        self.state = state
        self.store = store
        self.services = services
        self.presentWindow = presentWindow
        self.showSettings = showSettings
        completed = store.completed
        loginEnabled = services.isLoginEnabled()
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observer = DistributedNotificationCenter.default().addObserver(
            forName: DaemonSingleton.reopen, object: String(getuid()), queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reopen() }
            }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        if presentWindow {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        if !completed { show() }
        refresh()
    }

    func refresh() {
        guard !checking else { return }
        checking = true
        let hotkey = state.hotkey
        Task { [weak self] in
            guard let self else { return }
            let facts = await services.snapshot(hotkey)
            let changed = !hasRefreshed || facts != state.readiness
            hasRefreshed = true
            state.updateReadiness(facts)
            checking = false
            if !facts.installedLocation || facts.conflictingBundle {
                if changed { show() }
                return
            }
            if completed {
                if !facts.permitsPreparation(hotkey: state.hotkey) {
                    step = facts.microphone && facts.accessibility ? .hotkey : .permissions
                    if changed { show() }
                } else if state.preparation == .waiting {
                    prepare()
                }
            } else if step != .welcome {
                advanceFromFacts()
            }
        }
    }

    func advance() {
        switch step {
        case .welcome: step = state.readiness.microphone && state.readiness.accessibility ? .hotkey : .permissions
        case .permissions:
            if state.readiness.microphone && state.readiness.accessibility { step = .hotkey }
        case .hotkey:
            if state.readiness.permitsPreparation(hotkey: state.hotkey) {
                step = state.preparation == .ready ? .test : .model
            }
        case .model, .test: advanceFromFacts()
        }
    }

    private func advanceFromFacts() {
        let facts = state.readiness
        guard facts.installedLocation, !facts.conflictingBundle else { return }
        if !facts.microphone || !facts.accessibility { step = .permissions }
        else if !facts.permitsPreparation(hotkey: state.hotkey) || step == .permissions { step = .hotkey }
        else if step == .hotkey { return }
        else if state.preparation != .ready { step = .model }
        else { step = .test }
    }

    func prepare() {
        guard state.readiness.permitsPreparation(hotkey: state.hotkey),
              !state.preparation.isRunning, state.preparation != .ready else { return }
        state.setPreparation(.downloading(nil))
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await services.warmUp { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.state.preparation.isRunning else { return }
                        let fraction = min(max(fraction, 0), 1)
                        self.state.setPreparation(fraction >= 1 ? .loading : .downloading(fraction))
                    }
                }
                guard !Task.isCancelled else { return }
                state.setPreparation(.ready)
                if !completed || window?.isVisible == true { advanceFromFacts() }
            } catch {
                guard !Task.isCancelled else { return }
                state.setPreparation(.failed(error.localizedDescription))
                step = .model
                show()
            }
        }
    }

    @discardableResult
    func finish() -> Bool {
        guard store.finish(ready: state.canCapture) else { return false }
        completed = true
        window?.close()
        return true
    }

    func requestMicrophone() {
        guard hasRefreshed, state.readiness.installedLocation else { return }
        services.requestMicrophone()
    }
    func requestAccessibility() {
        guard hasRefreshed, state.readiness.installedLocation else { return }
        services.requestAccessibility()
    }
    func setLogin(_ enabled: Bool) {
        guard hasRefreshed, completed || state.canCapture, state.readiness.installedLocation else { return }
        do {
            try services.setLogin(enabled)
            loginEnabled = enabled
            loginError = nil
        } catch { loginError = error.localizedDescription }
    }

    func reopen() {
        if !completed || !state.canCapture { show() } else { showSettings() }
        refresh()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopen()
        return true
    }

    func show() {
        presentationCount += 1
        if case .failed = state.preparation { step = .model }
        guard presentWindow else { return }
        if window == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                                     styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            newWindow.title = "Welcome to Plume"
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.contentViewController = NSHostingController(rootView: OnboardingView(state: state, startup: self))
            newWindow.center()
            window = newWindow
        }
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Completion is written only by Finish. A close keeps the task alive.
    }
    func applicationWillTerminate(_ notification: Notification) { preparationTask?.cancel() }

    /// Open the installed bundle only after this process has exited; opening it
    /// first would just deliver a reopen event to this same cached TCC process.
    func relaunch() {
        guard hasRefreshed, state.readiness.installedLocation, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                          "plume-relaunch", String(getpid()), Bundle.main.bundleURL.path]
        do { try task.run(); NSApp.terminate(nil) }
        catch { state.setPreparation(.failed("Could not relaunch: \(error.localizedDescription)")) }
    }

    deinit {
        refreshTimer?.invalidate()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
}

struct OnboardingView: View {
    @ObservedObject var state: DaemonState
    @ObservedObject var startup: StartupController
    @State private var testText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Style.Space.x4) {
            Text(title).font(Style.font(Style.Text.title, .semibold))
            if !state.readiness.installedLocation {
                Text("Drag Plume into Applications, eject the disk image, then open Plume from Applications. You can also use your own ~/Applications folder. Setup needs a permanent home before requesting permissions or enabling launch at login.")
            } else if state.readiness.conflictingBundle {
                Text("Another Plume is already running. Quit that copy from its menu bar, then click Check again. Plume will keep only one dictation daemon running.")
            } else {
                content
            }
            Spacer()
            HStack {
                Button("Quit Plume") { NSApp.terminate(nil) }
                Spacer()
                Button("Check again") { startup.refresh() }.disabled(startup.checking)
                if state.readiness.installedLocation && !state.readiness.conflictingBundle {
                    if startup.step == .welcome {
                        Button("Get started") { startup.advance() }.disabled(startup.checking).keyboardShortcut(.defaultAction)
                    } else if startup.step == .test {
                        Button("Finish") { startup.finish() }.disabled(!state.canCapture).keyboardShortcut(.defaultAction)
                    } else if startup.step == .permissions || startup.step == .hotkey {
                        Button("Continue") { startup.advance() }
                            .disabled(startup.step == .permissions
                                ? !state.readiness.microphone || !state.readiness.accessibility
                                : !state.readiness.permitsPreparation(hotkey: state.hotkey))
                    }
                }
            }
        }
        .padding(32)
        .frame(width: 600, height: 540)
        .onChange(of: state.hotkey) { _, _ in startup.refresh() }
    }

    private var title: String {
        if !state.readiness.installedLocation { return "Move Plume to Applications" }
        if state.readiness.conflictingBundle { return "Plume is already running" }
        switch startup.step {
        case .welcome: return "Your voice, wherever you type"
        case .permissions: return "Allow Plume to help you dictate"
        case .hotkey: return "Choose your hold-to-talk key"
        case .model: return "Prepare your speech model"
        case .test: return "Try your first dictation"
        }
    }

    @ViewBuilder private var content: some View {
        switch startup.step {
        case .welcome:
            Text("Hold a key, speak, release. Plume inserts your words into the focused text field. Speech runs locally on your Mac; no account is needed.")
            Text("macOS 14 or later · Apple Silicon\nThe recommended Parakeet TDT v3 model downloads about 461 MB on first use. Your remembered model choice is preserved.")
                .foregroundStyle(.secondary)
        case .permissions:
            Text("Microphone access captures your voice only while dictating. Accessibility lets Plume observe your hold-to-talk key and insert text into the app you are using.")
            permissionRow("Microphone", granted: state.readiness.microphone, request: startup.requestMicrophone,
                          destination: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            permissionRow("Accessibility", granted: state.readiness.accessibility, request: startup.requestAccessibility,
                          destination: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            hotkeyPicker
            Text("After allowing Plume, return here or click Check again. If macOS still reports a missing permission, relaunch Plume after checking its switch in System Settings.").foregroundStyle(.secondary)
            Button("Relaunch Plume") { startup.relaunch() }
        case .hotkey:
            Text("For Fn / 🌐, open Keyboard settings and set ‘Press 🌐 key to’ to ‘Do Nothing’. If your keyboard handles Fn itself, choose another modifier.")
            hotkeyPicker
            Button("Open Keyboard Settings") { open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") }
        case .model:
            Text("\(state.model.displayName) · about \(state.model.sizeMB) MB\nDownload once, then load locally. Keep Plume open while it prepares.")
            Text(state.preparation.description).fixedSize(horizontal: false, vertical: true)
            switch state.preparation {
            case .downloading(let fraction):
                if let fraction { ProgressView(value: fraction) } else { ProgressView() }
            case .loading: ProgressView()
            case .failed: Button("Retry") { startup.prepare() }
            case .waiting: Button("Prepare model") { startup.prepare() }
            case .ready: Button("Continue") { startup.advance() }
            }
        case .test:
            Text("Click the field below. Hold \(state.hotkey.glyph), speak a short sentence, then release. Your words should appear here. Finish when you are ready.")
            TextEditor(text: $testText).frame(height: 120).border(Color(nsColor: .separatorColor))
                .accessibilityLabel("Try dictation here")
            Toggle("Launch Plume at login", isOn: Binding(get: { startup.loginEnabled }, set: startup.setLogin))
            Text("Initially off. You can also change this in Settings.").foregroundStyle(.secondary)
            if let error = startup.loginError { Text(error).foregroundStyle(.red) }
        }
    }

    private var hotkeyPicker: some View {
        Picker("Hold-to-talk key", selection: $state.hotkey) {
            ForEach(HotkeyMonitor.Hotkey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }
    private func permissionRow(_ name: String, granted: Bool, request: @escaping () -> Void, destination: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(name): \(granted ? "Allowed" : "Required")").fontWeight(.medium)
            HStack {
                Button("Allow \(name)", action: request).disabled(granted)
                Button("Open System Settings") { open(destination) }
            }
        }
    }
    private func open(_ destination: String) {
        if let url = URL(string: destination) { NSWorkspace.shared.open(url) }
    }
}
