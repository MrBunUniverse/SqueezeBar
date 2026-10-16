import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import SqueezeBar

/// End-to-end engine runs: what lands on disk and what the UI is told.
@MainActor
final class EngineOutcomeTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    /// Random pixels saved at low quality: re-encoding at a higher quality can only make it bigger.
    private func writeNoisyJPEG(_ url: URL) {
        let ctx = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(ctx.bytesPerRow * 400) { p[i] = UInt8.random(in: 0...255) }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.2] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testOutputThatIsNotSmallerIsDiscarded() async throws {
        let src = dir.appendingPathComponent("noise.jpg")
        writeNoisyJPEG(src)
        let resultsBefore = AppState.shared.recentResults.count
        await MediaCompressionEngine.shared.processDroppedURLs([src])
        XCTAssertEqual(try contents(), ["noise.jpg"], "no bigger copy and no partial file left behind")
        XCTAssertEqual(AppState.shared.recentResults.count, resultsBefore)
        XCTAssertFalse(AppState.shared.failedJobs.contains { $0.fileName == "noise.jpg" }, "not reported as a failure")
    }

    func testFailedJobLeavesNoFilesAndIsReportedOnce() async throws {
        let src = dir.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: src)
        await MediaCompressionEngine.shared.processDroppedURLs([src])
        XCTAssertEqual(try contents(), ["broken.jpg"])
        XCTAssertTrue(AppState.shared.failedJobs.contains { $0.fileName == "broken.jpg" })
        let downloads = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path)
        XCTAssertFalse(downloads.contains { $0.hasPrefix("broken_min") }, "no retry into Downloads")
    }
}
