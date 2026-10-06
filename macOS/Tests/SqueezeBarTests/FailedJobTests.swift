import XCTest
@testable import SqueezeBar

@MainActor
final class FailedJobTests: XCTestCase {
    override func setUp() async throws {
        AppState.shared.clearFailures()
    }

    func testFailedJobIsKeptAndCancelledJobIsNot() {
        let state = AppState.shared
        let failing = CompressionJob(fileURL: URL(fileURLWithPath: "/tmp/broken.png"), mediaType: .image)
        let cancelled = CompressionJob(fileURL: URL(fileURLWithPath: "/tmp/stopped.png"), mediaType: .image)
        state.addJob(failing)
        state.addJob(cancelled)

        state.finishJob(id: failing.id, result: nil, error: "Invalid or corrupt image data")
        state.finishJob(id: cancelled.id, result: nil, error: "Cancelled")

        XCTAssertEqual(state.failedJobs.count, 1)
        XCTAssertEqual(state.failedJobs.first?.fileName, "broken.png")
        XCTAssertEqual(state.failedJobs.first?.message, "Invalid or corrupt image data")
        XCTAssertTrue(state.showFailureBadge)

        state.dismissFailure(id: state.failedJobs[0].id)
        XCTAssertTrue(state.failedJobs.isEmpty)
    }
}
