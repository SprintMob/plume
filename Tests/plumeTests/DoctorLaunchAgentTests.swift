import XCTest
@testable import plume

/// `checkLaunchAgentArgs` is what tells a user upgrading from a version that
/// baked --hotkey into the agent why the menu bar appears to be ignored, and
/// what tells a user whose agent survived the move into a .app bundle why the
/// daemon ignores everything they pick.
final class DoctorLaunchAgentTests: XCTestCase {
    private var directory: URL!

    /// A stand-in for Plume.app/Contents/MacOS/plume. The check reads
    /// `ProgramArguments[0]` off the filesystem, so the tests that are about
    /// baked flags need a program path that passes the two checks in front of
    /// them.
    private var bundledBinary: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plume-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let macOS = directory
            .appendingPathComponent("Plume.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("plume")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: executable.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        ))
        bundledBinary = executable.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        bundledBinary = nil
        try super.tearDownWithError()
    }

    /// The filename is the bundle identifier, which is also the launchd label.
    /// Written out rather than read from `Install.label`, because under xctest
    /// `Bundle.main` is the test runner and the label would be its identifier.
    private func writeAgent(arguments: [String]) throws -> URL {
        let url = directory.appendingPathComponent("com.sprintmob.plume.plist")
        let plist: [String: Any] = ["Label": "com.sprintmob.plume", "ProgramArguments": arguments]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    private func isWarning(_ check: Check) -> Bool {
        if case .warn = check.status { return true }
        return false
    }

    private func isFailure(_ check: Check) -> Bool {
        if case .fail = check.status { return true }
        return false
    }

    func testAgentWithoutBakedFlagsPasses() throws {
        let url = try writeAgent(arguments: [bundledBinary, "run", "--skip-doctor"])

        XCTAssertFalse(isWarning(DoctorReport.checkLaunchAgentArgs(at: url)))
        XCTAssertFalse(isFailure(DoctorReport.checkLaunchAgentArgs(at: url)))
    }

    func testBakedHotkeyWarns() throws {
        let url = try writeAgent(
            arguments: [bundledBinary, "run", "--skip-doctor", "--hotkey", "fn"])

        let check = DoctorReport.checkLaunchAgentArgs(at: url)
        XCTAssertTrue(isWarning(check))
        XCTAssertEqual(check.remediation, "re-run `plume install --launch-at-login`")
    }

    func testBothBakedFlagsAreNamed() throws {
        let url = try writeAgent(arguments: [
            bundledBinary, "run", "--skip-doctor",
            "--hotkey", "fn", "--inject-mode", "paste",
        ])

        guard case .warn(let detail) = DoctorReport.checkLaunchAgentArgs(at: url).status else {
            return XCTFail("expected a warning")
        }
        XCTAssertTrue(detail.contains("--hotkey"), detail)
        XCTAssertTrue(detail.contains("--inject-mode"), detail)
    }

    /// `--no-overlay` and `--mute-output` joined the check when they became
    /// remembered choices: a hand-edited agent carrying either overrides the
    /// settings window the same way a baked `--hotkey` overrides the menu bar.
    func testBakedOverlayAndMuteFlagsWarn() throws {
        let url = try writeAgent(arguments: [
            bundledBinary, "run", "--skip-doctor", "--no-overlay", "--mute-output",
        ])

        guard case .warn(let detail) = DoctorReport.checkLaunchAgentArgs(at: url).status else {
            return XCTFail("expected a warning")
        }
        XCTAssertTrue(detail.contains("--no-overlay"), detail)
        XCTAssertTrue(detail.contains("--mute-output"), detail)
    }

    /// One flag reads as itself, several read as a sentence.
    func testTheWarningNamesEveryStaleFlagReadably() throws {
        let one = try writeAgent(arguments: [bundledBinary, "run", "--hotkey", "fn"])
        guard case .warn(let single) = DoctorReport.checkLaunchAgentArgs(at: one).status else {
            return XCTFail("expected a warning")
        }
        XCTAssertTrue(single.hasPrefix("--hotkey baked in"), single)

        let three = try writeAgent(arguments: [
            bundledBinary, "run", "--hotkey", "fn", "--inject-mode", "paste", "--mute-output",
        ])
        guard case .warn(let many) = DoctorReport.checkLaunchAgentArgs(at: three).status else {
            return XCTFail("expected a warning")
        }
        XCTAssertTrue(many.hasPrefix("--hotkey, --inject-mode and --mute-output baked in"), many)
    }

    // MARK: - What the .app bundle added

    /// Before the bundle, an agent naming a deleted binary was completely
    /// invisible to doctor. Moving the daemon into a .app is exactly the kind
    /// of change that deletes the binary an old agent points at.
    func testAgentPointingAtAMissingBinaryFails() throws {
        let url = try writeAgent(
            arguments: ["/usr/local/bin/plume-that-is-not-there", "run", "--skip-doctor"])

        let check = DoctorReport.checkLaunchAgentArgs(at: url)
        XCTAssertTrue(isFailure(check))
        guard case .fail(let detail) = check.status else { return XCTFail("expected a failure") }
        XCTAssertTrue(detail.contains("not there"), detail)
    }

    /// An unbundled daemon takes its preferences domain from the process name
    /// instead of CFBundleIdentifier, so it reads a domain nothing writes and
    /// silently ignores every remembered choice.
    func testAgentPointingOutsideABundleFails() throws {
        let loose = directory.appendingPathComponent("plume")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: loose.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        ))
        let url = try writeAgent(arguments: [loose.path, "run", "--skip-doctor"])

        let check = DoctorReport.checkLaunchAgentArgs(at: url)
        XCTAssertTrue(isFailure(check))
        guard case .fail(let detail) = check.status else { return XCTFail("expected a failure") }
        XCTAssertTrue(detail.contains("remembered choice"), detail)
    }

    /// An agent that names nothing runnable is reported as that, not as a note
    /// about flag precedence, which would be beside the point.
    func testAMissingBinaryIsReportedAheadOfBakedFlags() throws {
        let url = try writeAgent(
            arguments: ["/nowhere/plume", "run", "--hotkey", "fn"])

        guard case .fail(let detail) = DoctorReport.checkLaunchAgentArgs(at: url).status else {
            return XCTFail("expected a failure")
        }
        XCTAssertFalse(detail.contains("--hotkey"), detail)
    }

    /// No agent installed is the common case, not a problem to report.
    func testMissingAgentPasses() {
        let url = directory.appendingPathComponent("nothing-here.plist")

        XCTAssertFalse(isWarning(DoctorReport.checkLaunchAgentArgs(at: url)))
    }

    func testUnreadableAgentPasses() throws {
        let url = directory.appendingPathComponent("garbage.plist")
        try Data("not a plist".utf8).write(to: url)

        XCTAssertFalse(isWarning(DoctorReport.checkLaunchAgentArgs(at: url)))
    }
}
