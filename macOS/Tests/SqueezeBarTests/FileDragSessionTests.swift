import XCTest
@testable import SqueezeBar

final class FileDragSessionTests: XCTestCase {
    func testLeavingDropAreaClosesAfterShortGrace() {
        var session = FileDragSession(openedPresentation: .popover)
        XCTAssertFalse(session.shouldFinish(isInside: false, mousePressed: true, time: 0))
        XCTAssertFalse(session.shouldFinish(isInside: false, mousePressed: true, time: 0.24))
        XCTAssertTrue(session.shouldFinish(isInside: false, mousePressed: true, time: 0.26))
    }

    func testEnteringPopoverCancelsPendingDismissal() {
        var session = FileDragSession(openedPresentation: .popover)
        XCTAssertFalse(session.shouldFinish(isInside: false, mousePressed: true, time: 0))
        XCTAssertFalse(session.shouldFinish(isInside: true, mousePressed: true, time: 0.20))
        XCTAssertFalse(session.shouldFinish(isInside: true, mousePressed: true, time: 10))
        XCTAssertFalse(session.shouldFinish(isInside: false, mousePressed: true, time: 10.01))
        XCTAssertTrue(session.shouldFinish(isInside: false, mousePressed: true, time: 10.27))
    }

    func testMouseReleaseFinishesEvenInsideWindow() {
        var session = FileDragSession(openedPresentation: .floatingWindow)
        XCTAssertFalse(session.shouldFinish(isInside: true, mousePressed: false, time: 0))
        XCTAssertFalse(session.shouldFinish(isInside: true, mousePressed: false, time: 0.05))
        XCTAssertTrue(session.shouldFinish(isInside: true, mousePressed: false, time: 0.13))
    }

    func testDraggingEndedDoesNotWaitForPhysicalMouseButton() {
        var session = FileDragSession(openedPresentation: .popover)
        session.markReleased(at: 0)
        session.markReleased(at: 0.10)
        XCTAssertTrue(session.shouldFinish(isInside: true, mousePressed: true, time: 0.13))
    }
}
