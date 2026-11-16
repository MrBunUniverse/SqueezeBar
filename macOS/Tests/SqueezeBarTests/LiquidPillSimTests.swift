import XCTest
@testable import SqueezeBar

final class LiquidPillSimTests: XCTestCase {
    private func rect(_ x: CGFloat, width: CGFloat = 96) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: 28)
    }

    private func advance(_ sim: LiquidPillSim, from start: Double, duration: Double) {
        for frame in 1...Int(duration * 120) {
            sim.advance(to: start + Double(frame) / 120)
        }
    }

    func testSingleMoveSettles() {
        let sim = LiquidPillSim()
        sim.update(target: rect(0), drag: nil, at: 0)
        sim.update(target: rect(300), drag: nil, at: 0)
        advance(sim, from: 0, duration: 1.5)
        XCTAssertTrue(sim.isSettled)
    }

    func testRapidReselectionSettles() {
        let sim = LiquidPillSim()
        sim.update(target: rect(0), drag: nil, at: 0)
        for index in 0..<10 {
            let time = Double(index) / 10
            sim.update(target: rect(index.isMultiple(of: 2) ? 300 : 0), drag: nil, at: time)
            advance(sim, from: time, duration: 0.1)
        }
        advance(sim, from: 1, duration: 1.5)
        XCTAssertTrue(sim.isSettled)
    }

    func testReselectionAtMaximumStretchSettles() {
        let probe = LiquidPillSim()
        probe.update(target: rect(0), drag: nil, at: 0)
        probe.update(target: rect(300), drag: nil, at: 0)
        var peakTime = 0.0
        var peakWidth: CGFloat = 0
        for frame in 1...60 {
            let time = Double(frame) / 120
            probe.advance(to: time)
            let width = probe.shape.maxX - probe.shape.minX
            if width > peakWidth { peakWidth = width; peakTime = time }
        }
        XCTAssertGreaterThan(peakWidth, 96)
        let sim = LiquidPillSim()
        sim.update(target: rect(0), drag: nil, at: 0)
        sim.update(target: rect(300), drag: nil, at: 0)
        advance(sim, from: 0, duration: peakTime)
        sim.update(target: rect(0), drag: nil, at: peakTime)
        advance(sim, from: peakTime, duration: 1.5)
        XCTAssertTrue(sim.isSettled)
    }

    func testSizeOnlyUpdateDoesNotWake() {
        let sim = LiquidPillSim()
        sim.update(target: rect(0), drag: nil, at: 0)
        let resized = rect(-12, width: 120)
        sim.update(target: resized, drag: nil, at: 1)
        XCTAssertTrue(sim.isSettled)
        XCTAssertEqual(sim.shape.minX, resized.minX)
        XCTAssertEqual(sim.shape.maxX, resized.maxX)
    }

    func testHiddenFlightSnapsToCurrentSelection() {
        let sim = LiquidPillSim()
        sim.update(target: rect(0), drag: nil, at: 0)
        sim.update(target: rect(300), drag: nil, at: 0)
        advance(sim, from: 0, duration: 0.1)
        sim.snap(to: rect(150), at: 2)
        XCTAssertTrue(sim.isSettled)
        XCTAssertEqual(sim.shape.minX, 150)
        XCTAssertEqual(sim.shape.maxX, 246)
        XCTAssertEqual(sim.shape.squash, 0)
        XCTAssertEqual(sim.shape.pinch, 0)
        sim.update(target: rect(300), drag: nil, at: 2)
        XCTAssertFalse(sim.isSettled)
        advance(sim, from: 2, duration: 1.5)
        XCTAssertTrue(sim.isSettled)
    }

    func testSingleMoveTrajectory() {
        let sim = LiquidPillSim()
        sim.update(target: rect(0), drag: nil, at: 0)
        sim.update(target: rect(300), drag: nil, at: 0)
        let expected: [Int: [CGFloat]] = [
            6: [43.190479148607324, 213.54898455197014, -0.057628420517142925],
            12: [160.044235682534, 339.4085441133307, -0.16858308530989702],
            24: [230.07601470149189, 401.15322630052776, -0.1719721897485776],
            48: [314.31464112290155, 395.736670917319, 0.07191648590582386],
            96: [299.67728970414385, 395.99977307867493, -0.0016822866744322389],
            120: [300.0, 396.0, 0.0]
        ]
        for frame in 1...120 {
            sim.advance(to: Double(frame) / 120)
            if let sample = expected[frame] {
                XCTAssertEqual(sim.shape.minX, sample[0], accuracy: 1e-10)
                XCTAssertEqual(sim.shape.maxX, sample[1], accuracy: 1e-10)
                XCTAssertEqual(sim.shape.squash, sample[2], accuracy: 1e-10)
            }
        }
    }
}
