import XCTest
import AVFoundation
@testable import SqueezeBar

final class LowBitrateAudioTests: XCTestCase {
    func testLowBitratePresetsProducePlayableM4A() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 20)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(buffer.frameLength) {
                let t = Double(frame) / 44100
                let voice = sin(2 * .pi * 180 * t) * (0.5 + 0.5 * sin(2 * .pi * 3 * t))
                let music = sin(2 * .pi * 740 * t) + sin(2 * .pi * 2100 * t)
                buffer.floatChannelData![channel][frame] = Float(0.3 * voice + 0.15 * music)
            }
        }
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
        }
        for preset in [AudioBitratePreference.k8] {
            var config = CompressionConfiguration()
            config.audioBitrate = preset
            config.targetSizeMode = .off
            let compressor = HardwareAudioCompressor()
            let ext = compressor.outputExtension(for: source, config: config)
            XCTAssertEqual(ext, "m4a")
            let output = directory.appendingPathComponent("output.\(ext)")
            try await compressor.compressAudio(from: source, to: output, config: config)
            let asset = AVURLAsset(url: output)
            let playable = try await asset.load(.isPlayable)
            XCTAssertTrue(playable)
            let duration = try await asset.load(.duration).seconds
            let data = try Data(contentsOf: output)
            XCTAssertEqual(String(data: data[4..<8], encoding: .ascii), "ftyp")
            XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "M4A ")
            let bitrate = Double(data.count) * 8 / duration
            XCTAssertEqual(bitrate, Double(preset.bitrateInBps), accuracy: Double(preset.bitrateInBps) * 0.25)
            let decoded = try AVAudioFile(forReading: output)
            XCTAssertEqual(decoded.fileFormat.channelCount, 1)
            XCTAssertEqual(decoded.fileFormat.sampleRate, 11025)
            print("Low bitrate \(preset.rawValue): \(bitrate) bps, playable=\(playable)")
        }
    }
}
