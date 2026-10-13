import XCTest
@testable import plume

@MainActor
final class StartupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var domain: String!
    override func setUp() {
        super.setUp()
        domain = "plume-startup-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: domain)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: domain)
        super.tearDown()
    }
    private func state(hotkey: HotkeyMonitor.Hotkey = .fn) -> DaemonState {
        DaemonState(model: ModelRegistry.recommended()!, hotkey: hotkey, injectMode: .paste,
                    overlayEnabled: true, muteOutputEnabled: false, sessionHistoryEnabled: true,
                    settings: SettingsStore(defaults: defaults))
    }
    private var granted: StartupReadiness {
        StartupReadiness(microphone: true, accessibility: true, fnConfigured: true)
    }
    private func waitFor(_ predicate: () -> Bool) async {
        for _ in 0..<200 { if predicate() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Startup did not settle")
    }
    private func services(snapshot: StartupReadiness, warmup: @escaping (@Sendable (Double) -> Void) async throws -> Void = { _ in }) -> StartupServices {
        StartupServices(snapshot: { _ in snapshot }, warmUp: warmup,
                        requestMicrophone: {}, requestAccessibility: {}, setLogin: { _ in })
    }

    func testSelectedModelIsNotLoadedAndPermissionsGateCapture() {
        let state = state()
        XCTAssertFalse(state.canCapture)
        state.setPreparation(.ready)
        XCTAssertFalse(state.canCapture)
        state.updateReadiness(granted)
        XCTAssertTrue(state.canCapture)
        var revoked = granted
        revoked.microphone = false
        state.updateReadiness(revoked)
        XCTAssertFalse(state.canCapture)
        revoked = granted; revoked.accessibility = false
        state.updateReadiness(revoked)
        XCTAssertFalse(state.canCapture)
    }

    func testLoadedModelStatusDescribesPermissionAndKeyBlockers() {
        let state = state()
        state.setPreparation(.ready)
        state.updateReadiness(granted)
        XCTAssertNil(state.captureBlockerDescription)
        var facts = granted; facts.microphone = false
        state.updateReadiness(facts)
        XCTAssertEqual(state.captureBlockerDescription, "Microphone access required")
        facts = granted; facts.accessibility = false
        state.updateReadiness(facts)
        XCTAssertEqual(state.captureBlockerDescription, "Accessibility access required")
        facts = granted; facts.fnConfigured = false
        state.updateReadiness(facts)
        XCTAssertEqual(state.captureBlockerDescription, "Configure the Fn key")
        XCTAssertEqual(state.preparation, .ready)
    }

    func testLoadedModelStatusDescribesPendingDownloadAndLoading() {
        let state = state(); state.setPreparation(.ready); state.updateReadiness(granted)
        let next = ModelRegistry.shared.first { $0.id != state.model.id }!
        state.selectModel(next)
        XCTAssertFalse(state.canCapture)
        XCTAssertEqual(state.captureBlockerDescription, "Loading \(next.displayName)…")
        state.switchProgressed(0.5)
        XCTAssertEqual(state.captureBlockerDescription, "Downloading \(next.displayName) · 50%")
        state.switchProgressed(1)
        XCTAssertEqual(state.captureBlockerDescription, "Loading \(next.displayName)…")
        state.switched(to: next)
        XCTAssertTrue(state.canCapture)
        XCTAssertNil(state.captureBlockerDescription)
    }

    func testFnMustBeConfiguredOrAlternateKeySelected() {
        let state = state()
        var facts = granted; facts.fnConfigured = false
        state.updateReadiness(facts); state.setPreparation(.ready)
        XCTAssertFalse(state.canCapture)
        state.hotkey = .rightOption
        XCTAssertTrue(state.canCapture)
    }

    func testDownloadFailureCanRetryWithoutCompletingOnboarding() async {
        let state = state(); state.updateReadiness(granted)
        var attempts = 0
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services(snapshot: granted, warmup: { progress in
                attempts += 1
                progress(0.5)
                if attempts == 1 { throw NSError(domain: "download", code: 1) }
                progress(1)
            }), presentWindow: false, showSettings: {})
        startup.prepare()
        startup.prepare() // No second preparation while one is already running.
        await waitFor { if case .failed = state.preparation { return true }; return false }
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(startup.finish())
        XCTAssertFalse(OnboardingStore(defaults: defaults).completed)
        startup.prepare()
        await waitFor { state.preparation == .ready }
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(state.canCapture)
        XCTAssertEqual(startup.step, .test)
        XCTAssertTrue(startup.finish())
        XCTAssertTrue(OnboardingStore(defaults: defaults).completed)
    }

    func testCompletedInstallationPreparesQuietlyAndReopenShowsSettings() async {
        XCTAssertTrue(OnboardingStore(defaults: defaults).finish(ready: true))
        let state = state()
        var settingsOpened = 0
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services(snapshot: granted), presentWindow: false, showSettings: { settingsOpened += 1 })
        startup.start()
        await waitFor { state.canCapture }
        XCTAssertEqual(startup.presentationCount, 0)
        startup.reopen()
        XCTAssertEqual(settingsOpened, 1)
    }

    func testInterruptedOnboardingResumesFromActualFactsAndCompletionIsExplicit() async {
        let state = state()
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services(snapshot: granted), presentWindow: false, showSettings: {})
        startup.start()
        await waitFor { !startup.checking }
        startup.advance()
        XCTAssertEqual(startup.step, .hotkey)
        startup.advance()
        XCTAssertEqual(startup.step, .model)
        XCTAssertFalse(OnboardingStore(defaults: defaults).completed)
        XCTAssertFalse(startup.finish())
    }

    func testRefreshDetectsRevocationWithoutRepeatedFocusOrAnotherWarmup() async {
        _ = OnboardingStore(defaults: defaults).finish(ready: true)
        let state = state()
        var facts = granted
        var warms = 0
        let services = StartupServices(snapshot: { _ in facts }, warmUp: { _ in warms += 1 },
            requestMicrophone: {}, requestAccessibility: {}, setLogin: { _ in })
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services, presentWindow: false, showSettings: {})
        startup.start(); await waitFor { state.canCapture }
        facts.accessibility = false
        startup.refresh(); await waitFor { !startup.checking }
        XCTAssertFalse(state.canCapture)
        XCTAssertEqual(startup.presentationCount, 1)
        startup.refresh(); await waitFor { !startup.checking }
        XCTAssertEqual(startup.presentationCount, 1)
        facts.accessibility = true
        startup.refresh(); await waitFor { state.canCapture }
        XCTAssertEqual(warms, 1)
        XCTAssertTrue(startup.completed)
    }

    func testDownloadAndLoadingAreDistinctAndBothDisableCapture() async {
        let state = state(); state.updateReadiness(granted)
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services(snapshot: granted, warmup: { progress in
                progress(0.4)
                try await Task.sleep(nanoseconds: 5_000_000)
                progress(1)
                try await Task.sleep(nanoseconds: 20_000_000)
            }), presentWindow: false, showSettings: {})
        startup.prepare()
        await waitFor { state.preparation == .downloading(0.4) }
        XCTAssertFalse(state.canCapture)
        await waitFor { state.preparation == .loading }
        XCTAssertFalse(state.canCapture)
        await waitFor { state.preparation == .ready }
        XCTAssertTrue(state.canCapture)
    }

    func testCompletedButDeniedPermissionsOpenRecoveryAndNeverWarmup() async {
        _ = OnboardingStore(defaults: defaults).finish(ready: true)
        let state = state()
        var warms = 0
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services(snapshot: StartupReadiness(), warmup: { _ in warms += 1 }),
            presentWindow: false, showSettings: {})
        startup.start()
        await waitFor { !startup.checking }
        XCTAssertEqual(warms, 0)
        XCTAssertEqual(startup.step, .permissions)
        XCTAssertGreaterThan(startup.presentationCount, 0)
        XCTAssertFalse(state.canCapture)
    }

    func testPermissionsAndLoginWaitForTheFirstActualLocationSnapshot() {
        let state = state(); state.updateReadiness(granted); state.setPreparation(.ready)
        var requests = 0
        let services = StartupServices(snapshot: { _ in StartupReadiness(installedLocation: false) },
            warmUp: { _ in }, requestMicrophone: { requests += 1 },
            requestAccessibility: { requests += 1 }, setLogin: { _ in requests += 1 })
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services, presentWindow: false, showSettings: {})
        startup.requestMicrophone(); startup.requestAccessibility(); startup.setLogin(true)
        XCTAssertEqual(requests, 0)
    }

    func testTransientBundleDoesNotRequestPermissionsOrRegisterLogin() async {
        let state = state()
        var requests = 0
        let services = StartupServices(snapshot: { _ in StartupReadiness(installedLocation: false) },
            warmUp: { _ in requests += 1 }, requestMicrophone: { requests += 1 },
            requestAccessibility: { requests += 1 }, setLogin: { _ in requests += 1 })
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services, presentWindow: false, showSettings: {})
        startup.start()
        await waitFor { !startup.checking }
        startup.requestMicrophone(); startup.requestAccessibility(); startup.setLogin(true); startup.prepare()
        XCTAssertEqual(requests, 0)
        XCTAssertFalse(startup.finish())
        XCTAssertTrue(InstallationLocation.isTransient(URL(fileURLWithPath: "/Volumes/Plume/Plume.app")))
        XCTAssertTrue(InstallationLocation.isTransient(URL(fileURLWithPath: "/private/var/AppTranslocation/abc/Plume.app")))
        XCTAssertFalse(InstallationLocation.isTransient(URL(fileURLWithPath: "/Users/test/Applications/Plume.app")))
    }

    func testConflictBlocksPreparationAndReopenShowsOnboarding() async {
        let state = state(); var facts = granted; facts.conflictingBundle = true
        let startup = StartupController(state: state, store: OnboardingStore(defaults: defaults),
            services: services(snapshot: facts), presentWindow: false, showSettings: {})
        startup.start(); await waitFor { !startup.checking }
        startup.prepare()
        XCTAssertEqual(state.preparation, .waiting)
        startup.reopen()
        XCTAssertGreaterThan(startup.presentationCount, 1)
    }

    func testModelCatalogDoesNotClaimAnUnloadedSelectionIsActive() {
        let model = ModelRegistry.recommended()!
        let row = ModelCatalog.rows(models: [model], active: nil, isInstalled: { _ in false })[0]
        XCTAssertEqual(row.status, .available)
    }
}

final class SingletonAndAgentTests: XCTestCase {
    func testProcessLifetimeLockRejectsSecondOwnerAndReleasesOnExit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: DaemonSingleton? = DaemonSingleton()
        XCTAssertTrue(try first!.acquire(at: directory))
        let second = DaemonSingleton()
        XCTAssertFalse(try second.acquire(at: directory))
        first = nil
        XCTAssertTrue(try second.acquire(at: directory))
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("daemon.lock").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testAgentPreservesBundleArgumentsPrivacyAndKeepAlive() {
        let path = "/Users/test/Applications/Plume.app/Contents/MacOS/plume"
        let quiet = Install.agentPropertyList(binary: path, logPath: "/dev/null", logFile: false)
        XCTAssertEqual(quiet["ProgramArguments"] as? [String], [path, "run", "--skip-doctor"])
        XCTAssertEqual(quiet["StandardErrorPath"] as? String, "/dev/null")
        XCTAssertEqual(quiet["ProcessType"] as? String, "Interactive")
        XCTAssertEqual((quiet["KeepAlive"] as? [String: Bool])?["SuccessfulExit"], false)
        let logs = Install.agentPropertyList(binary: path, logPath: "/private/test.log", logFile: true)
        XCTAssertEqual(logs["Umask"] as? Int, 0o077)
    }
}
