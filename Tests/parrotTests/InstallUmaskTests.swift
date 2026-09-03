import XCTest
@testable import parrot

/// The launch agent's Umask applies to every file and directory the daemon
/// creates, so it has to leave directories usable. A value without the owner
/// execute bit crash-loops the model downloader: it creates
/// `TextDecoder.mlmodelc` at 0600 and then cannot write inside it, warmup fails
/// with EACCES, and KeepAlive relaunches forever.
final class InstallUmaskTests: XCTestCase {
    private var fileMode: Int { 0o666 & ~Install.logUmask }
    private var directoryMode: Int { 0o777 & ~Install.logUmask }

    func testDirectoriesStayTraversable() {
        XCTAssertEqual(
            directoryMode & 0o100, 0o100,
            "owner execute cleared — the daemon cannot write inside directories it creates")
    }

    func testNothingIsReadableByGroupOrOther() {
        XCTAssertEqual(fileMode & 0o077, 0, "log would be readable beyond the owner")
        XCTAssertEqual(directoryMode & 0o077, 0, "directories would be reachable beyond the owner")
    }

    func testLogFilesLandAt0600() {
        XCTAssertEqual(fileMode, 0o600)
    }

    func testDirectoriesLandAt0700() {
        XCTAssertEqual(directoryMode, 0o700)
    }

    /// The value that shipped, kept as a named case so the regression is
    /// explicit rather than implied by the assertions above.
    func testTheShippedValueWouldHaveFailed() {
        XCTAssertEqual(0o777 & ~0o177 & 0o100, 0, "0o177 was expected to clear owner execute")
        XCTAssertNotEqual(Install.logUmask, 0o177)
    }
}
