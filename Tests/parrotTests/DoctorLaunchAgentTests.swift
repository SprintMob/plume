import XCTest
@testable import parrot

/// `checkLaunchAgentArgs` is what tells a user upgrading from a version that
/// baked --hotkey into the agent why the menu bar appears to be ignored.
final class DoctorLaunchAgentTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parrot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private func writeAgent(arguments: [String]) throws -> URL {
        let url = directory.appendingPathComponent("com.digimata.parrot.plist")
        let plist: [String: Any] = ["Label": "com.digimata.parrot", "ProgramArguments": arguments]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    private func isWarning(_ check: Check) -> Bool {
        if case .warn = check.status { return true }
        return false
    }

    func testAgentWithoutBakedFlagsPasses() throws {
        let url = try writeAgent(arguments: ["/usr/local/bin/parrot", "run", "--skip-doctor"])

        XCTAssertFalse(isWarning(DoctorReport.checkLaunchAgentArgs(at: url)))
    }

    func testBakedHotkeyWarns() throws {
        let url = try writeAgent(
            arguments: ["/usr/local/bin/parrot", "run", "--skip-doctor", "--hotkey", "fn"])

        let check = DoctorReport.checkLaunchAgentArgs(at: url)
        XCTAssertTrue(isWarning(check))
        XCTAssertEqual(check.remediation, "re-run `parrot install --launch-at-login`")
    }

    func testBothBakedFlagsAreNamed() throws {
        let url = try writeAgent(arguments: [
            "/usr/local/bin/parrot", "run", "--skip-doctor",
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
            "/usr/local/bin/parrot", "run", "--skip-doctor", "--no-overlay", "--mute-output",
        ])

        guard case .warn(let detail) = DoctorReport.checkLaunchAgentArgs(at: url).status else {
            return XCTFail("expected a warning")
        }
        XCTAssertTrue(detail.contains("--no-overlay"), detail)
        XCTAssertTrue(detail.contains("--mute-output"), detail)
    }

    /// One flag reads as itself, several read as a sentence.
    func testTheWarningNamesEveryStaleFlagReadably() throws {
        let one = try writeAgent(arguments: ["parrot", "run", "--hotkey", "fn"])
        guard case .warn(let single) = DoctorReport.checkLaunchAgentArgs(at: one).status else {
            return XCTFail("expected a warning")
        }
        XCTAssertTrue(single.hasPrefix("--hotkey baked in"), single)

        let three = try writeAgent(arguments: [
            "parrot", "run", "--hotkey", "fn", "--inject-mode", "paste", "--mute-output",
        ])
        guard case .warn(let many) = DoctorReport.checkLaunchAgentArgs(at: three).status else {
            return XCTFail("expected a warning")
        }
        XCTAssertTrue(many.hasPrefix("--hotkey, --inject-mode and --mute-output baked in"), many)
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
