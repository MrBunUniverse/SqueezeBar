import XCTest
@testable import SqueezeBar

final class DestinationNamingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-naming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testPlainNameGetsSuffix() {
        let src = dir.appendingPathComponent("clip.mp4")
        let out = MediaCompressionEngine.uniqueDestinationURL(folder: dir, baseName: "clip", suffix: "_min", extension: "mp4", sourceURL: src)
        XCTAssertEqual(out.lastPathComponent, "clip_min.mp4")
    }

    func testExistingFileIsNotOverwritten() throws {
        let src = dir.appendingPathComponent("clip.mp4")
        try Data().write(to: dir.appendingPathComponent("clip_min.mp4"))
        let out = MediaCompressionEngine.uniqueDestinationURL(folder: dir, baseName: "clip", suffix: "_min", extension: "mp4", sourceURL: src)
        XCTAssertEqual(out.lastPathComponent, "clip_min (1).mp4")
    }

    func testReservedPathIsSkipped() {
        let src = dir.appendingPathComponent("clip.mp4")
        let reserved = dir.appendingPathComponent("clip_min.mp4").path
        let out = MediaCompressionEngine.uniqueDestinationURL(folder: dir, baseName: "clip", suffix: "_min", extension: "mp4", sourceURL: src, reservedPaths: [reserved])
        XCTAssertEqual(out.lastPathComponent, "clip_min (1).mp4")
    }

    /// Regression: an empty-looking suffix used to return the source path itself.
    func testDestinationNeverEqualsSource() throws {
        let src = dir.appendingPathComponent("clip.mp4")
        try Data().write(to: src)
        let out = MediaCompressionEngine.uniqueDestinationURL(folder: dir, baseName: "clip", suffix: "", extension: "mp4", sourceURL: src)
        XCTAssertNotEqual(out.standardizedFileURL.path, src.standardizedFileURL.path)
        XCTAssertEqual(out.lastPathComponent, "clip (1).mp4")
    }

    func testVideoCompressorRefusesToOverwriteSource() async throws {
        let src = dir.appendingPathComponent("clip.mp4")
        let payload = Data("original".utf8)
        try payload.write(to: src)
        let config = await MainActor.run { AppState.shared.currentConfiguration() }
        do {
            try await HardwareVideoCompressor().compressVideo(from: src, to: src, config: config)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: src), payload)
    }

    func testAudioCompressorRefusesToOverwriteSource() async throws {
        let src = dir.appendingPathComponent("clip.m4a")
        let payload = Data("original".utf8)
        try payload.write(to: src)
        let config = await MainActor.run { AppState.shared.currentConfiguration() }
        do {
            try await HardwareAudioCompressor().compressAudio(from: src, to: src, config: config)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: src), payload)
    }
}

@MainActor
final class BatchRenameTests: XCTestCase {
    private var dir: URL!
    private let historyKey = "squeezebar.historyList"
    private var savedHistory: Data?
    private var savedResults: [CompressionResult] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savedHistory = UserDefaults.standard.data(forKey: historyKey)
        savedResults = AppState.shared.recentResults
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        AppState.shared.recentResults = savedResults
        if let savedHistory { UserDefaults.standard.set(savedHistory, forKey: historyKey) }
        else { UserDefaults.standard.removeObject(forKey: historyKey) }
    }

    private func makeResult(_ name: String) throws -> CompressionResult {
        let url = dir.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return CompressionResult(originalURL: url, outputURL: url, originalSize: 10, compressedSize: 5, duration: 0, mediaType: .image)
    }

    func testRenameMovesFileAndUpdatesHistory() throws {
        let r = try makeResult("a_min.jpg")
        AppState.shared.recentResults = [r]
        AppState.shared.batchRenameResults(ids: [r.id], pattern: "Trip_#")
        let new = dir.appendingPathComponent("Trip_1.jpg")
        XCTAssertEqual(AppState.shared.recentResults[0].outputURL, new)
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a_min.jpg").path))
    }

    func testRenameDoesNotOverwriteExistingFileAndKeepsHistoryValid() throws {
        let r = try makeResult("a_min.jpg")
        let blocker = dir.appendingPathComponent("Trip_1.jpg")
        try Data("keep me".utf8).write(to: blocker)
        AppState.shared.recentResults = [r]
        AppState.shared.batchRenameResults(ids: [r.id], pattern: "Trip_#")
        XCTAssertEqual(try Data(contentsOf: blocker), Data("keep me".utf8))
        XCTAssertEqual(AppState.shared.recentResults[0].outputURL, r.outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.outputURL.path))
    }
}
