import XCTest
@testable import plume

/// The migration runs against a temporary home, which is the whole point of
/// `Migration.Paths` being injectable. What is *not* exercised here is step 1
/// and step 7, the launchctl bootout and the agent re-registration: both shell
/// out to /bin/launchctl against the real session, and a test that registered a
/// launch agent on the machine running it would be worse than no test.
final class MigrationTests: XCTestCase {
    private var home: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plume-migration-\(UUID().uuidString)", isDirectory: true)
        for directory in ["Application Support", "Caches", "Logs", "Preferences", "LaunchAgents"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent("Library/\(directory)", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        suiteName = "plume.migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: home)
        home = nil
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    private func paths() -> Migration.Paths {
        Migration.Paths.standard(home: home)
    }

    /// launchctl and the agent re-registration are stubbed out: this suite
    /// must not touch the launchd session of the machine running it.
    private func migration() -> Migration {
        Migration(
            paths: paths(),
            defaults: defaults,
            launchctl: { _ in },
            registerAgent: { logFile in
                Install.Agent(
                    plistPath: "/dev/null",
                    binary: "/dev/null",
                    logPath: logFile ? "log" : "/dev/null"
                )
            }
        )
    }

    private func makeLegacyModels(_ contents: String = "weights") throws {
        let root = paths().legacyModels
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: root.appendingPathComponent("model.bin"))
    }

    private func writeLegacyPreferences(_ dict: [String: Any]) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: paths().legacyPreferences)
    }

    // MARK: - What gets carried

    /// Losing `modelID` means re-downloading gigabytes of weights because one
    /// string went missing, so the key list is asserted rather than trusted.
    func testEveryStoreKeyIsCarried() {
        XCTAssertEqual(
            Set(Migration.Keys.all),
            [
                "hotkey", "injectMode", "overlay", "muteOutput", "sessionHistory",
                "modelID", "previousModelID", "inputDeviceUID",
            ]
        )
    }

    /// It has to be more than SettingsStore's five: ModelStore and
    /// InputDeviceStore write to the same domain and are just as lost.
    func testTheKeyListReachesPastSettingsStore() {
        XCTAssertTrue(Migration.Keys.all.count > SettingsStore.migratableKeys.count)
        XCTAssertTrue(Migration.Keys.all.contains("modelID"))
        XCTAssertTrue(Migration.Keys.all.contains("inputDeviceUID"))
    }

    // MARK: - Nothing to do

    func testACleanMachineNeedsNoMigration() {
        XCTAssertFalse(migration().isNeeded)
    }

    func testAnyLegacyLeftoverMakesItNeeded() throws {
        try makeLegacyModels()

        XCTAssertTrue(migration().isNeeded)
    }

    // MARK: - Preconditions

    /// Merging two model roots is a question about data, not a rename.
    func testTwoModelRootsAbortBeforeAnythingMoves() throws {
        try makeLegacyModels()
        try FileManager.default.createDirectory(at: paths().models, withIntermediateDirectories: true)

        let problems = migration().preflight()
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("Merging two model roots"), problems[0])
        // And nothing was touched by asking.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: paths().legacyModels.appendingPathComponent("model.bin").path))
    }

    func testAParrotInstallOnOneVolumePassesPreflight() throws {
        try makeLegacyModels()

        XCTAssertEqual(migration().preflight(), [])
    }

    // MARK: - The moves

    func testTheWeightsMoveRatherThanBeingRedownloaded() throws {
        try makeLegacyModels("the actual weights")

        _ = try migration().run()

        let moved = paths().models.appendingPathComponent("model.bin")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "the actual weights")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths().legacyModels.path))
    }

    func testTheLogMovesAndKeepsMode0600() throws {
        let fm = FileManager.default
        XCTAssertTrue(fm.createFile(
            atPath: paths().legacyLog.path,
            contents: Data("timing only\n".utf8),
            attributes: [.posixPermissions: 0o600]
        ))

        _ = try migration().run()

        XCTAssertTrue(fm.fileExists(atPath: paths().log.path))
        let mode = (try fm.attributesOfItem(atPath: paths().log.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o600)
    }

    /// last-capture.wav is a debug artefact, not user data. It must never be
    /// the reason a migration stops.
    func testTheCaptureCacheMoves() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths().legacyCaches, withIntermediateDirectories: true)
        try Data("riff".utf8).write(to: paths().legacyCaches.appendingPathComponent("last-capture.wav"))

        _ = try migration().run()

        XCTAssertTrue(fm.fileExists(
            atPath: paths().caches.appendingPathComponent("last-capture.wav").path))
    }

    // MARK: - The remembered choices

    func testEveryRememberedChoiceIsCarriedOver() throws {
        try writeLegacyPreferences([
            "hotkey": "right-option",
            "injectMode": "type-unicode",
            "overlay": false,
            "muteOutput": true,
            "sessionHistory": false,
            "modelID": "whisper-large-v3-turbo",
            "previousModelID": "whisper-base.en",
            "inputDeviceUID": "AppleUSBAudioEngine:Blue:Yeti",
        ])

        _ = try migration().run()

        XCTAssertEqual(defaults.string(forKey: "hotkey"), "right-option")
        XCTAssertEqual(defaults.string(forKey: "injectMode"), "type-unicode")
        XCTAssertEqual(defaults.object(forKey: "overlay") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "muteOutput") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "sessionHistory") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "modelID"), "whisper-large-v3-turbo")
        XCTAssertEqual(defaults.string(forKey: "previousModelID"), "whisper-base.en")
        XCTAssertEqual(defaults.string(forKey: "inputDeviceUID"), "AppleUSBAudioEngine:Blue:Yeti")
    }

    /// The guard that makes a retry after a partial failure safe: a key already
    /// chosen under the new domain is never overwritten by a stale one.
    func testAChoiceAlreadyMadeUnderTheNewDomainWins() throws {
        defaults.set("fn", forKey: "hotkey")
        try writeLegacyPreferences(["hotkey": "right-option", "modelID": "whisper-base.en"])

        _ = try migration().run()

        XCTAssertEqual(defaults.string(forKey: "hotkey"), "fn")
        XCTAssertEqual(defaults.string(forKey: "modelID"), "whisper-base.en")
    }

    func testRunningItTwiceChangesNothingTheSecondTime() throws {
        try writeLegacyPreferences(["hotkey": "right-option"])
        _ = try migration().run()
        defaults.set("left-command", forKey: "hotkey")

        _ = try migration().run()

        XCTAssertEqual(defaults.string(forKey: "hotkey"), "left-command")
    }

    /// Not deleted, on purpose: a few hundred bytes, and the only way to replay
    /// this if the new install is thrown away.
    func testTheLegacyPreferencesFileIsLeftInPlace() throws {
        try writeLegacyPreferences(["hotkey": "right-option"])

        _ = try migration().run()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths().legacyPreferences.path))
    }

    /// Keys that are not ours are not the migration's business.
    func testUnknownKeysAreNotCarried() throws {
        try writeLegacyPreferences(["hotkey": "fn", "SomeOtherAppKey": "value"])

        _ = try migration().run()

        XCTAssertNil(defaults.object(forKey: "SomeOtherAppKey"))
    }

    // MARK: - Doctor's half of the split

    func testDoctorWarnsWhileTheLegacyAgentIsStillRegistered() throws {
        let url = home.appendingPathComponent("Library/LaunchAgents/\(Install.legacyLabel).plist")
        try Data("<plist/>".utf8).write(to: url)

        let check = DoctorReport.checkLegacyLaunchAgent(at: url)
        guard case .warn = check.status else { return XCTFail("expected a warning") }
        XCTAssertEqual(check.remediation, "run `plume install --migrate`")
    }

    func testDoctorIsQuietWithoutALegacyAgent() {
        let url = home.appendingPathComponent("Library/LaunchAgents/nothing.plist")

        guard case .ok = DoctorReport.checkLegacyLaunchAgent(at: url).status else {
            return XCTFail("expected ok")
        }
    }
}
