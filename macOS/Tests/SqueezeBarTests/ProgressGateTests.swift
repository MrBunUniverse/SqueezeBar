import XCTest
@testable import SqueezeBar

final class ProgressGateTests: XCTestCase {
    func testFirstAndFinalAlwaysPass() {
        let gate = ProgressGate()
        XCTAssertTrue(gate.shouldReport(0.0, now: 100))
        // Too soon for the time gate, but the final value must still get through.
        XCTAssertFalse(gate.shouldReport(0.5, now: 100.001))
        XCTAssertTrue(gate.shouldReport(1.0, now: 100.002))
        XCTAssertFalse(gate.shouldReport(1.0, now: 105), "same percent is never repeated")
        XCTAssertTrue(gate.shouldReport(0.0, now: 105.001), "a restart at 0% always passes")
    }

    func testAtMostOneReportPerInterval() {
        let gate = ProgressGate()
        var reports: [Double] = []
        // A fast job: 1000 per-frame callbacks over 2 s, ending just short of 100%.
        for i in 0..<1000 {
            let now = 50 + Double(i) * 0.002
            if gate.shouldReport(Double(i) / 1001, now: now) { reports.append(now) }
        }
        XCTAssertEqual(reports.first, 50)
        XCTAssertLessThanOrEqual(reports.count, Int(2 / ProgressGate.minInterval) + 1)
        XCTAssertGreaterThanOrEqual(reports.count, 15, "still reports steadily")
        for (a, b) in zip(reports, reports.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, ProgressGate.minInterval - 1e-9)
        }
    }

    func testSlowJobStillReportsEveryPercent() {
        let gate = ProgressGate()
        let passed = (0...100).filter { gate.shouldReport((Double($0) + 0.5) / 100, now: Double($0)) }
        XCTAssertEqual(passed.count, 101, "one report per percent, 0 through 100")
    }

    func testWaveLevelRestsBetweenSweeps() {
        // Peak when the wave centre sits on the bar; bars the wave has left are back at rest.
        XCTAssertEqual(SqueezeWaveMark.level(forBar: 2, phase: 0.75 * 3 / 6), 1, accuracy: 1e-9)
        for phase in [0.75, 0.9, 1.0] {
            for bar in 0..<4 { XCTAssertEqual(SqueezeWaveMark.level(forBar: bar, phase: phase), 0) }
        }
        for bar in 0..<SqueezeClampShape.barCount {
            for k in 0...180 {
                let level = SqueezeWaveMark.level(forBar: bar, phase: Double(k) / 180)
                XCTAssertTrue((0...1).contains(level))
            }
        }
    }
}
