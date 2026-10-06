import XCTest
@testable import SqueezeBar

final class JobControlTests: XCTestCase {
    func testCheckpointPassesWhenNotPaused() {
        XCTAssertTrue(JobControl().checkpoint())
    }

    func testPausedCheckpointBlocksUntilResume() {
        let control = JobControl()
        control.pause()
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result = false
        DispatchQueue.global().async {
            result = control.checkpoint()
            done.signal()
        }
        // Still blocked while paused.
        XCTAssertEqual(done.wait(timeout: .now() + 0.3), .timedOut)
        control.resume()
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(result)
    }

    func testCancelWakesPausedCheckpointAndReportsCancelled() {
        let control = JobControl()
        control.pause()
        let finished = expectation(description: "checkpoint returned")
        nonisolated(unsafe) var result = true
        DispatchQueue.global().async {
            result = control.checkpoint()
            finished.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1)
        control.cancel()
        wait(for: [finished], timeout: 2)
        XCTAssertFalse(result)
        XCTAssertTrue(control.isCancelled)
        XCTAssertFalse(control.isPaused)
    }

    func testCannotPauseAfterCancel() {
        let control = JobControl()
        control.cancel()
        control.pause()
        XCTAssertFalse(control.isPaused)
        XCTAssertFalse(control.checkpoint())
    }
}
