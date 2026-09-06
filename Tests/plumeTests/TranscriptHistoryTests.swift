import XCTest
@testable import plume

/// The history is the one place a transcript outlives its dictation, so what it
/// keeps — and for how long — is worth pinning down. `grouped` and `filtered`
/// take a calendar and a clock so the day labels can be tested without waiting
/// for midnight.
@MainActor
final class TranscriptHistoryTests: XCTestCase {
    private var calendar: Calendar!
    /// Noon, so a day's arithmetic never lands on a DST boundary.
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12))!
    }

    private func daysBefore(_ days: Int, hour: Int = 12) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
            .addingTimeInterval(TimeInterval((hour - 12) * 3600))
    }

    private func entry(_ text: String, daysAgo: Int = 0, hour: Int = 12) -> TranscriptHistory.Entry {
        TranscriptHistory.Entry(text: text, at: daysBefore(daysAgo, hour: hour), latency: 0.4)
    }

    // MARK: - Recording

    func testNewestFirst() {
        let history = TranscriptHistory()

        history.record("first", latency: 0.1)
        history.record("second", latency: 0.2)

        XCTAssertEqual(history.entries.map(\.text), ["second", "first"])
    }

    func testTheCapIsEnforcedFromTheOldestEnd() {
        let history = TranscriptHistory(capacity: 3)

        for i in 1...5 {
            history.record("\(i)", latency: 0)
        }

        XCTAssertEqual(history.entries.map(\.text), ["5", "4", "3"])
    }

    /// A recording that held no speech is kept, not dropped: the section
    /// renders it, so the user learns the dictation happened and produced
    /// nothing rather than wondering where it went.
    func testAnEmptyTranscriptIsStillRecorded() {
        let history = TranscriptHistory()

        history.record("", latency: 0.3)

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.text, "")
    }

    func testClearEmptiesIt() {
        let history = TranscriptHistory()
        history.record("something", latency: 0)

        history.clear()

        XCTAssertTrue(history.entries.isEmpty)
    }

    // MARK: - Grouping

    func testGroupsByDayInTheOrderTheEntriesArrive() {
        let entries = [
            entry("today late", daysAgo: 0, hour: 16),
            entry("today early", daysAgo: 0, hour: 9),
            entry("yesterday", daysAgo: 1),
            entry("last week", daysAgo: 7),
        ]

        let days = TranscriptHistory.grouped(entries, calendar: calendar, now: now)

        XCTAssertEqual(days.map(\.label), ["Today", "Yesterday", "7 days ago"])
        XCTAssertEqual(days[0].entries.map(\.text), ["today late", "today early"])
        XCTAssertEqual(days[2].entries.map(\.text), ["last week"])
    }

    /// Two dictations either side of midnight are two days, however few minutes
    /// apart they were.
    func testMidnightSplitsADay() {
        let entries = [
            entry("just after", daysAgo: 0, hour: 0),
            entry("just before", daysAgo: 1, hour: 23),
        ]

        let days = TranscriptHistory.grouped(entries, calendar: calendar, now: now)

        XCTAssertEqual(days.map(\.label), ["Today", "Yesterday"])
    }

    func testNoEntriesGroupToNoDays() {
        XCTAssertTrue(TranscriptHistory.grouped([], calendar: calendar, now: now).isEmpty)
    }

    // MARK: - Filtering

    func testAnEmptyQueryMatchesEverything() {
        let entries = [entry("one"), entry("two")]

        XCTAssertEqual(TranscriptHistory.filtered(entries, query: "  ").count, 2)
    }

    func testMatchingIgnoresCaseAndAccents() {
        let entries = [entry("Merci de procéder au règlement")]

        XCTAssertEqual(TranscriptHistory.filtered(entries, query: "reglement").count, 1)
        XCTAssertEqual(TranscriptHistory.filtered(entries, query: "MERCI").count, 1)
        XCTAssertEqual(TranscriptHistory.filtered(entries, query: "facture").count, 0)
    }
}
