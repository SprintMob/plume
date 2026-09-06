import XCTest
@testable import plume

final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "plume.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testFlagWinsOverTheRememberedChoice() {
        store.hotkey = .leftOption
        store.injectMode = .typeUnicode

        XCTAssertEqual(store.resolvedHotkey(flag: .rightShift), .rightShift)
        XCTAssertEqual(store.resolvedInjectMode(flag: .paste), .paste)
    }

    func testRememberedChoiceWinsOverTheDefault() {
        store.hotkey = .rightOption
        store.injectMode = .typeUnicode

        XCTAssertEqual(store.resolvedHotkey(flag: nil), .rightOption)
        XCTAssertEqual(store.resolvedInjectMode(flag: nil), .typeUnicode)
    }

    func testFallsBackToTheDefaultWhenNothingIsRemembered() {
        XCTAssertNil(store.hotkey)
        XCTAssertNil(store.injectMode)
        XCTAssertEqual(store.resolvedHotkey(flag: nil), .fn)
        XCTAssertEqual(store.resolvedInjectMode(flag: nil), .paste)
    }

    /// A value written by a build that spelled the case differently must not
    /// take the launch down with it — the same tolerance ModelStore gives a
    /// model id that has left the registry.
    func testUnparseableStoredValueFallsThroughToTheDefault() {
        defaults.set("middle-option", forKey: "hotkey")
        defaults.set("telepathy", forKey: "injectMode")

        XCTAssertNil(store.hotkey)
        XCTAssertNil(store.injectMode)
        XCTAssertEqual(store.resolvedHotkey(flag: nil), .fn)
        XCTAssertEqual(store.resolvedInjectMode(flag: nil), .paste)
    }

    func testSettingNilForgetsTheChoice() {
        store.hotkey = .leftControl
        store.injectMode = .typeUnicode
        XCTAssertEqual(store.hotkey, .leftControl)

        store.hotkey = nil
        store.injectMode = nil

        XCTAssertNil(defaults.string(forKey: "hotkey"))
        XCTAssertNil(defaults.string(forKey: "injectMode"))
        XCTAssertEqual(store.resolvedHotkey(flag: nil), .fn)
    }

    // MARK: - The three that turned from flags into remembered choices

    /// `--no-overlay` and `--mute-output` each reach in one direction only:
    /// there is no `--overlay`, so a flag can silence the pill for a run but
    /// never force it back on over a remembered "off".
    func testTheFlagsOnlyReachOneWay() {
        store.overlay = true
        store.muteOutput = false

        XCTAssertFalse(store.resolvedOverlay(disabledByFlag: true))
        XCTAssertTrue(store.resolvedMuteOutput(forcedByFlag: true))

        XCTAssertTrue(store.resolvedOverlay(disabledByFlag: false))
        XCTAssertFalse(store.resolvedMuteOutput(forcedByFlag: false))
    }

    func testTheRememberedBoolWinsOverTheDefault() {
        store.overlay = false
        store.muteOutput = true
        store.sessionHistory = false

        XCTAssertFalse(store.resolvedOverlay(disabledByFlag: false))
        XCTAssertTrue(store.resolvedMuteOutput(forcedByFlag: false))
        XCTAssertFalse(store.resolvedSessionHistory())
    }

    func testTheBoolDefaultsAreOverlayOnMuteOffHistoryOn() {
        XCTAssertNil(store.overlay)
        XCTAssertNil(store.muteOutput)
        XCTAssertNil(store.sessionHistory)

        XCTAssertTrue(store.resolvedOverlay(disabledByFlag: false))
        XCTAssertFalse(store.resolvedMuteOutput(forcedByFlag: false))
        XCTAssertTrue(store.resolvedSessionHistory())
    }

    /// The reason these read through `object(forKey:)`: `bool(forKey:)` answers
    /// `false` for a key nobody has written, which would make a remembered
    /// "overlay off" indistinguishable from "never chosen" — and the default is
    /// on.
    func testChoosingOffIsNotTheSameAsNeverChoosing() {
        store.overlay = false
        XCTAssertEqual(store.overlay, false)

        store.overlay = nil

        XCTAssertNil(store.overlay)
        XCTAssertTrue(store.resolvedOverlay(disabledByFlag: false))
    }

    func testRoundTripsThroughASeparateInstance() {
        store.hotkey = .rightCommand

        XCTAssertEqual(SettingsStore(defaults: defaults).resolvedHotkey(flag: nil), .rightCommand)
    }
}
