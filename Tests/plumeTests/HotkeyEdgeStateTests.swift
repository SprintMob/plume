import XCTest
@testable import plume

final class HotkeyEdgeStateTests: XCTestCase {
    func testFirstPressAfterStopAndMissedReleaseIsDelivered() {
        var input = HotkeyEdgeState()
        let originalTap = input.beginSession()
        XCTAssertEqual(input.receive(pressed: true, session: originalTap), .pressed)
        input.endSession()
        // The physical release occurs while no tap is listening.
        let recoveredTap = input.beginSession()
        XCTAssertEqual(input.receive(pressed: true, session: recoveredTap), .pressed)
        XCTAssertEqual(input.receive(pressed: false, session: recoveredTap), .released)
    }

    func testQueuedCallbacksFromStoppedTapCannotReviveItsHeldState() {
        var input = HotkeyEdgeState()
        let originalTap = input.beginSession()
        input.endSession()
        // A previously queued press reaches the main queue after stop.
        XCTAssertNil(input.receive(pressed: true, session: originalTap))
        XCTAssertFalse(input.isPressed)
        let recoveredTap = input.beginSession()
        // The same queued press after restart still belongs to the old tap.
        XCTAssertNil(input.receive(pressed: true, session: originalTap))
        XCTAssertEqual(input.receive(pressed: true, session: recoveredTap), .pressed)
        // Old release/disable callbacks cannot disturb the new held key either.
        XCTAssertNil(input.receive(pressed: false, session: originalTap))
        XCTAssertNil(input.interrupt(session: originalTap))
        XCTAssertTrue(input.isPressed)
        XCTAssertEqual(input.receive(pressed: false, session: recoveredTap), .released)
    }

    func testCurrentTapInterruptionResetsItsEdgeAndDuplicatesRemainSuppressed() {
        var input = HotkeyEdgeState()
        let tap = input.beginSession()
        XCTAssertEqual(input.receive(pressed: true, session: tap), .pressed)
        XCTAssertNil(input.receive(pressed: true, session: tap))
        XCTAssertEqual(input.interrupt(session: tap), .interrupted)
        XCTAssertEqual(input.receive(pressed: true, session: tap), .pressed)
    }
}
