import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import SqueezeBar

/// Real watch-folder runs on temporary folders: files must be squeezed even when more arrive mid-batch,
/// and switching folders must keep the new one watched.
final class FolderWatchTests: XCTestCase {
    private var dirs: [URL] = []

    override func tearDownWithError() throws {
        FolderWatchService.shared.stopMonitoring()
        for dir in dirs { try? FileManager.default.removeItem(at: dir) }
    }

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirs.append(dir)
        return dir
    }

    /// Noise saved at full quality, so the default settings always produce a smaller copy.
    private func writePhoto(_ url: URL) {
        let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(ctx.bytesPerRow * 600) { p[i] = UInt8.random(in: 0...255) }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    func testFileIsSqueezedEvenWhenAnotherArrivesDuringItsWait() async throws {
        let dir = try makeDir()
        FolderWatchService.shared.startMonitoring(path: dir.path)
        writePhoto(dir.appendingPathComponent("a.jpg"))
        try await Task.sleep(nanoseconds: 1_500_000_000) // a.jpg is now in its stability wait
        writePhoto(dir.appendingPathComponent("b.jpg"))
        let gotA = await waitForFile(dir.appendingPathComponent("a_min.jpg"))
        let gotB = await waitForFile(dir.appendingPathComponent("b_min.jpg"))
        XCTAssertTrue(gotA, "the first file must not be dropped when a second one arrives")
        XCTAssertTrue(gotB)
    }

    func testSwitchingFoldersKeepsWatchingTheNewOne() async throws {
        let first = try makeDir(), second = try makeDir()
        FolderWatchService.shared.startMonitoring(path: first.path)
        FolderWatchService.shared.startMonitoring(path: second.path)
        FolderWatchService.shared.startMonitoring(path: second.path) // the settings UI can start twice in a row
        writePhoto(second.appendingPathComponent("c.jpg"))
        let gotC = await waitForFile(second.appendingPathComponent("c_min.jpg"))
        XCTAssertTrue(gotC)
    }

    func testStoppedWatchIgnoresNewFiles() async throws {
        let dir = try makeDir()
        FolderWatchService.shared.startMonitoring(path: dir.path)
        FolderWatchService.shared.stopMonitoring()
        writePhoto(dir.appendingPathComponent("d.jpg"))
        let gotD = await waitForFile(dir.appendingPathComponent("d_min.jpg"), timeout: 4)
        XCTAssertFalse(gotD)
    }
}
