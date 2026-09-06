import XCTest
@testable import plume

/// What the models table says about each model. The rule is pure, and
/// `isInstalled` is injected, so none of this touches the model store on disk.
final class ModelCatalogTests: XCTestCase {
    private func model(_ id: String, recommended: Bool = false) -> TranscriptionModel {
        TranscriptionModel(
            id: id,
            displayName: id,
            engine: .whisperKit,
            engineID: id,
            sizeMB: 100,
            languages: ["en"],
            recommended: recommended)
    }

    private lazy var loaded = model("loaded")
    private lazy var onDisk = model("on-disk")
    private lazy var remote = model("remote")

    private func rows(
        pending: TranscriptionModel? = nil,
        progress: Double? = nil,
        failed: TranscriptionModel? = nil
    ) -> [String: ModelCatalog.Status] {
        let rows = ModelCatalog.rows(
            models: [loaded, onDisk, remote],
            active: loaded,
            pending: pending,
            progress: progress,
            failed: failed,
            isInstalled: { $0.id == self.onDisk.id || $0.id == self.loaded.id })
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.status) })
    }

    func testAtRestEachModelReportsWhereItIs() {
        let status = rows()

        XCTAssertEqual(status["loaded"], .active)
        XCTAssertEqual(status["on-disk"], .installed)
        XCTAssertEqual(status["remote"], .available)
    }

    /// The point of the pending state: the model being fetched shows its
    /// progress while the model still loaded keeps saying it is active. Before
    /// this, a click looked ignored for as long as the download took.
    func testTheModelInUseStaysActiveWhileAnotherDownloads() {
        let status = rows(pending: remote, progress: 0.42)

        XCTAssertEqual(status["remote"], .downloading(0.42))
        XCTAssertEqual(status["loaded"], .active)
    }

    /// Neither engine reports the load that follows the download, so a finished
    /// fetch has no number left to show.
    func testAFinishedDownloadReadsAsLoading() {
        XCTAssertEqual(rows(pending: remote, progress: 1.0)["remote"], .loading)
        XCTAssertEqual(rows(pending: remote, progress: nil)["remote"], .loading)
    }

    func testAFailedSwitchIsNamedOnItsOwnRow() {
        let status = rows(failed: remote)

        XCTAssertEqual(status["remote"], .failed)
        XCTAssertEqual(status["loaded"], .active)
    }

    /// One switch at a time, and the model in use is already here — the same
    /// rule the menu bar applies to its own items.
    func testOnlyTheRowsWorthClickingAreSelectable() {
        let all = ModelCatalog.rows(
            models: [loaded, onDisk, remote],
            active: loaded,
            pending: remote,
            progress: 0.5,
            isInstalled: { _ in false })

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.isSelectable) }),
            ["loaded": false, "on-disk": true, "remote": false])
    }

    func testTheRegistrysTwoLanguageShapesReadAsWords() {
        XCTAssertEqual(ModelCatalog.describeLanguages(["multi"]), "Multilingual")
        XCTAssertEqual(ModelCatalog.describeLanguages(["en"]), "English")
    }
}
