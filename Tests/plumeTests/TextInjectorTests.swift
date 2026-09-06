import AppKit
import XCTest

@testable import plume

/// The pasteboard guarantee: a non-empty transcript that reaches `TextInjector`
/// is on the pasteboard when the call returns, in both modes and whether or not
/// anything was injected.
///
/// Both seams are replaced. A privately-named pasteboard, so a test run does not
/// wipe the developer's own clipboard; and a recording poster, so nothing is ever
/// posted into the session — anyone running this suite has granted their terminal
/// accessibility permission, and a real post would land in whatever window has
/// the focus.
@MainActor
final class TextInjectorTests: XCTestCase {
    private final class Recorder {
        var strokes: [TextInjector.KeyStroke] = []
    }

    private var pasteboard: NSPasteboard!
    private var recorder: Recorder!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: .init("plume.tests.\(UUID().uuidString)"))
        recorder = Recorder()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        recorder = nil
        pasteboard = nil
        super.tearDown()
    }

    private var contents: String? { pasteboard.string(forType: .string) }

    private func post(_ stroke: TextInjector.KeyStroke) { recorder.strokes.append(stroke) }

    private func inject(_ text: String, mode: TextInjector.Mode) {
        TextInjector.inject(text, mode: mode, to: pasteboard, post: post)
    }

    private func typed() -> String {
        let units = recorder.strokes.reduce(into: [UniChar]()) { acc, stroke in
            if case .unicode(let chunk) = stroke { acc += chunk }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    private func prime(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - The guarantee

    func testPasteModeLeavesTheTranscriptOnThePasteboard() {
        inject("bonjour", mode: .paste)

        XCTAssertEqual(contents, "bonjour")
        XCTAssertEqual(recorder.strokes, [.commandV])
    }

    /// type-unicode used to leave the pasteboard alone, so a dictation into an
    /// app that silently drops synthesized unicode was lost outright. The mode
    /// now picks the delivery, not whether the guarantee holds.
    func testTypeUnicodeAlsoLeavesTheTranscriptOnThePasteboard() {
        inject("bonjour", mode: .typeUnicode)

        XCTAssertEqual(contents, "bonjour")
        XCTAssertEqual(typed(), "bonjour")
        XCTAssertFalse(recorder.strokes.contains(.commandV))
    }

    func testTheFallbackPathCopiesWithoutTouchingTheKeyboard() {
        TextInjector.copyToPasteboard("bonjour", to: pasteboard)

        XCTAssertEqual(contents, "bonjour")
        XCTAssertTrue(recorder.strokes.isEmpty)
    }

    // MARK: - What is deliberately overwritten

    func testWhateverWasCopiedIsReplaced() {
        prime("the user's own text")

        inject("bonjour", mode: .paste)

        XCTAssertEqual(contents, "bonjour")
    }

    /// The regression the settle-delay restore used to cause: 0.25s after a paste
    /// it put the old contents back, wiping the transcript that had just been
    /// delivered. Nothing is scheduled any more, so this waits past that window
    /// and finds the transcript still there.
    func testNothingIsPutBackAfterTheDelivery() {
        prime("the user's own text")
        inject("bonjour", mode: .paste)

        let settled = expectation(description: "past the old 0.25s settle delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(contents, "bonjour")
    }

    /// A dictation that produced nothing must not cost the user their clipboard.
    /// The daemon copies before it checks for empty text, so this guard is what
    /// holds that line.
    func testAnEmptyTranscriptLeavesThePasteboardAlone() {
        prime("the user's own text")

        TextInjector.copyToPasteboard("", to: pasteboard)
        inject("", mode: .paste)

        XCTAssertEqual(contents, "the user's own text")
        XCTAssertTrue(recorder.strokes.isEmpty)
    }

    // MARK: - One dictation, one clipboard entry

    /// The daemon copies before the probe and `inject` copies again. A clipboard
    /// manager must see one entry for that, not two identical ones.
    func testTheDeliveryDoesNotRewriteWhatTheDictationAlreadyCopied() {
        TextInjector.copyToPasteboard("bonjour", to: pasteboard)
        let afterFirstWrite = pasteboard.changeCount

        inject("bonjour", mode: .paste)

        XCTAssertEqual(pasteboard.changeCount, afterFirstWrite)
        XCTAssertEqual(contents, "bonjour")
        XCTAssertEqual(recorder.strokes, [.commandV])
    }

    /// Unless something took the pasteboard in between — which is exactly the
    /// case the transcript fallback's Copy button is for.
    func testARewriteHappensWhenSomethingElseTookThePasteboard() {
        TextInjector.copyToPasteboard("bonjour", to: pasteboard)
        prime("something else entirely")

        TextInjector.copyToPasteboard("bonjour", to: pasteboard)

        XCTAssertEqual(contents, "bonjour")
    }

    // MARK: - Chunking

    /// `keyboardSetUnicodeString` takes about 20 UTF-16 units per event, and
    /// units are what it counts.
    func testChunkingSplitsAtTheEventLimit() {
        XCTAssertEqual(TextInjector.chunks(of: String(repeating: "a", count: 45)).map(\.count),
                       [20, 20, 5])
        XCTAssertTrue(TextInjector.chunks(of: "").isEmpty)
        XCTAssertEqual(TextInjector.chunks(of: "short"), [Array("short".utf16)])
    }
}
