import XCTest
@testable import parrot

final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "parrot.tests.\(UUID().uuidString)"
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

    func testRoundTripsThroughASeparateInstance() {
        store.hotkey = .rightCommand

        XCTAssertEqual(SettingsStore(defaults: defaults).resolvedHotkey(flag: nil), .rightCommand)
    }
}
