import XCTest
import AVFoundation
import CoreImage
import ImageIO
@testable import SqueezeBar

final class OrientationTests: XCTestCase {
    func testImageOrientationSurvivesScalingConversionAndMetadataStripping() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pattern = try makePattern()
        let context = CIContext()

        for orientation in 1...8 {
            let source = folder.appendingPathComponent("source-\(orientation).jpg")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, "public.jpeg" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, pattern, [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1.0
            ] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let expectedImage = CIImage(cgImage: pattern).oriented(forExifOrientation: Int32(orientation))
            let expected = try XCTUnwrap(context.createCGImage(expectedImage, from: expectedImage.extent))

            for strip in [false, true] {
                for scale in [1.0, 0.5] {
                    for policy in [ImageFormatPolicy.preserveOriginal, .heicModern] {
                        var config = CompressionConfiguration()
                        config.imageQuality = 1
                        config.imageResolutionScale = scale
                        config.stripMetadata = strip
                        config.imageFormatPolicy = policy
                        let ext = AcceleratedImageCompressor().outputExtension(for: source, config: config)
                        let output = folder.appendingPathComponent("output-\(orientation)-\(strip)-\(scale).\(ext)")
                        try AcceleratedImageCompressor().compressImage(from: source, to: output, config: config)
                        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
                        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
                        XCTAssertEqual(image.width, Int(Double(expected.width) * scale))
                        XCTAssertEqual(image.height, Int(Double(expected.height) * scale))
                        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
                        XCTAssertEqual((properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1, 1)
                        try assertColors(image, match: expected)
                    }
                }
            }
        }
    }

    func testVideoAndGIFKeepDisplayOrientationAndAspectRatio() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let landscape = CGSize(width: 160, height: 96)
        let fixtures = [
            (landscape, CGAffineTransform.identity),
            (landscape, CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 96, ty: 0)),
            (landscape, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 160, ty: 96)),
            (landscape, CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 160)),
            (landscape, CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)),
            (CGSize(width: 96, height: 160), CGAffineTransform.identity)
        ]
        for (index, fixture) in fixtures.enumerated() {
            let source = folder.appendingPathComponent("source-\(index).mp4")
            try await makeVideo(at: source, size: fixture.0, transform: fixture.1)
            let expected = try await renderedVideoFrame(at: source)
            for mode in [TargetSizeMode.off, .web2] {
                for codec in [VideoCodecPreference.h264, .hevc] {
                    var config = CompressionConfiguration()
                    config.videoCodec = codec
                    config.videoResolutionScale = 0.5
                    config.targetSizeMode = mode
                    let output = folder.appendingPathComponent("output-\(index)-\(mode)-\(codec).mp4")
                    try await HardwareVideoCompressor().compressVideo(from: source, to: output, config: config)
                    let frame = try await renderedVideoFrame(at: output)
                    XCTAssertEqual(frame.width, expected.width / 2)
                    XCTAssertEqual(frame.height, expected.height / 2)
                    try assertColors(frame, match: expected)
                }
            }
            var config = CompressionConfiguration()
            config.videoCodec = .gif
            config.videoResolutionScale = 0.5
            let output = folder.appendingPathComponent("output-\(index).gif")
            try await HardwareVideoCompressor().compressVideo(from: source, to: output, config: config)
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            XCTAssertEqual(frame.width, expected.width)
            XCTAssertEqual(frame.height, expected.height)
            try assertColors(frame, match: expected)
        }
    }

    private func makePattern(width: Int = 160, height: Int = 96) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 1)]
        for (index, color) in colors.enumerated() {
            context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fill(CGRect(x: (index % 2) * width / 2, y: (index / 2) * height / 2, width: width / 2, height: height / 2))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func makeVideo(at url: URL, size: CGSize, transform: CGAffineTransform) async throws {
        let width = Int(size.width), height = Int(size.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
        context.draw(try makePattern(width: width, height: height), in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let deadline = Date().addingTimeInterval(10)
        for frame in 0..<12 {
            while !input.isReadyForMoreMediaData {
                guard Date() < deadline else { throw HardwareVideoCompressor.VideoCompressorError.encodingFailed("Fixture timed out") }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 12)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func renderedVideoFrame(at url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        return try await generator.image(at: .zero).image
    }

    private func assertColors(_ image: CGImage, match expected: CGImage) throws {
        func colors(_ image: CGImage) throws -> [UInt8] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
            let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: data, count: 16))
        }
        let actual = try colors(image), reference = try colors(expected)
        // Identify the four colored quadrants without treating lossy codec color changes as rotation.
        for pixel in stride(from: 0, to: 16, by: 4) {
            let actualRGB = Array(actual[pixel..<(pixel + 3)])
            let expectedRGB = Array(reference[pixel..<(pixel + 3)])
            if expectedRGB.allSatisfy({ $0 > 180 }) {
                XCTAssertTrue(actualRGB.allSatisfy({ $0 > 180 }), "White quadrant moved")
            } else {
                let dominant = try XCTUnwrap(expectedRGB.indices.max(by: { expectedRGB[$0] < expectedRGB[$1] }))
                XCTAssertGreaterThan(actualRGB[dominant], 150)
                for channel in 0..<3 where channel != dominant {
                    XCTAssertLessThan(actualRGB[channel], 120, "Colored quadrant moved")
                }
            }
        }
    }
}
