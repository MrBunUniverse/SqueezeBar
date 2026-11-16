import XCTest
@testable import SqueezeBar
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class SqueezeBarTests: XCTestCase {
    func testExplicitPNGStaysPNGAtLowQuality() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 32 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.clear(CGRect(x: 0, y: 0, width: 32, height: 24))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 8, y: 6, width: 16, height: 12))
        let image = try XCTUnwrap(context.makeImage())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.tiff")
        let output = directory.appendingPathComponent("output.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        var config = CompressionConfiguration()
        config.imageFormatPolicy = .pngLossless
        config.imageQuality = 0.3
        let compressor = AcceleratedImageCompressor()
        XCTAssertEqual(compressor.outputExtension(for: source, config: config), "png")
        try compressor.compressImage(from: source, to: output, config: config)
        XCTAssertEqual(Array(try Data(contentsOf: output).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let decodedSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decodedSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyHasAlpha] as? Bool, true)
    }
    
    func testMediaTypeClassification() {
        let pngURL = URL(fileURLWithPath: "/tmp/sample.png")
        let jpgURL = URL(fileURLWithPath: "/tmp/sample.jpg")
        let movURL = URL(fileURLWithPath: "/tmp/sample.mov")
        let mp4URL = URL(fileURLWithPath: "/tmp/sample.mp4")
        let mp3URL = URL(fileURLWithPath: "/tmp/sample.mp3")
        let wavURL = URL(fileURLWithPath: "/tmp/sample.wav")
        let flacURL = URL(fileURLWithPath: "/tmp/sample.flac")
        let m4aURL = URL(fileURLWithPath: "/tmp/sample.m4a")
        let textURL = URL(fileURLWithPath: "/tmp/sample.txt")
        
        XCTAssertEqual(MediaType.classify(url: pngURL), .image)
        XCTAssertEqual(MediaType.classify(url: jpgURL), .image)
        XCTAssertEqual(MediaType.classify(url: movURL), .video)
        XCTAssertEqual(MediaType.classify(url: mp4URL), .video)
        XCTAssertEqual(MediaType.classify(url: mp3URL), .audio)
        XCTAssertEqual(MediaType.classify(url: wavURL), .audio)
        XCTAssertEqual(MediaType.classify(url: flacURL), .audio)
        XCTAssertEqual(MediaType.classify(url: m4aURL), .audio)
        XCTAssertEqual(MediaType.classify(url: textURL), .unsupported)
    }
    
    func testWebPAndAVIFFormatExtensions() throws {
        let compressor = AcceleratedImageCompressor()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 32 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let image = try XCTUnwrap(context.makeImage())
        let sampleURL = directory.appendingPathComponent("sample.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(sampleURL as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        
        var configWebP = CompressionConfiguration()
        configWebP.imageFormatPolicy = .webpModern
        let webpExt = compressor.outputExtension(for: sampleURL, config: configWebP)
        let webpOut = directory.appendingPathComponent("out.\(webpExt)")
        try compressor.compressImage(from: sampleURL, to: webpOut, config: configWebP)
        let webpSource = try XCTUnwrap(CGImageSourceCreateWithURL(webpOut as CFURL, nil))
        let webpActualType = try XCTUnwrap(CGImageSourceGetType(webpSource) as String?)
        XCTAssertEqual(UTType(webpActualType), compressor.determineTargetUTType(for: sampleURL, config: configWebP))
        XCTAssertEqual(UTType(filenameExtension: webpExt), UTType(webpActualType))
        
        var configAVIF = CompressionConfiguration()
        configAVIF.imageFormatPolicy = .avifModern
        let avifExt = compressor.outputExtension(for: sampleURL, config: configAVIF)
        let avifOut = directory.appendingPathComponent("out_avif.\(avifExt)")
        try compressor.compressImage(from: sampleURL, to: avifOut, config: configAVIF)
        let avifSource = try XCTUnwrap(CGImageSourceCreateWithURL(avifOut as CFURL, nil))
        let avifActualType = try XCTUnwrap(CGImageSourceGetType(avifSource) as String?)
        XCTAssertEqual(UTType(filenameExtension: avifExt), UTType(avifActualType))
    }
    
    func testPreserveOriginalPNGAlphaAndExtensionAgreement() throws {
        let compressor = AcceleratedImageCompressor()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        
        // 1. PNG with alpha at low quality under .preserveOriginal stays PNG with alpha
        let alphaContext = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 32 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        alphaContext.clear(CGRect(x: 0, y: 0, width: 32, height: 24))
        alphaContext.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 0.4))
        alphaContext.fill(CGRect(x: 4, y: 4, width: 16, height: 16))
        let alphaImage = try XCTUnwrap(alphaContext.makeImage())
        let alphaSource = directory.appendingPathComponent("alpha.png")
        let alphaDest = try XCTUnwrap(CGImageDestinationCreateWithURL(alphaSource as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(alphaDest, alphaImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(alphaDest))
        
        var lowQConfig = CompressionConfiguration()
        lowQConfig.imageFormatPolicy = .preserveOriginal
        lowQConfig.imageQuality = 0.40
        
        XCTAssertEqual(compressor.outputExtension(for: alphaSource, config: lowQConfig), "png")
        let alphaOutput = directory.appendingPathComponent("alpha_out.png")
        try compressor.compressImage(from: alphaSource, to: alphaOutput, config: lowQConfig)
        let decodedAlpha = try XCTUnwrap(CGImageSourceCreateWithURL(alphaOutput as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(decodedAlpha) as String?, UTType.png.identifier)
        let alphaProps = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decodedAlpha, 0, nil) as? [CFString: Any])
        XCTAssertEqual(alphaProps[kCGImagePropertyHasAlpha] as? Bool, true)
        
        // 2. Opaque PNG at low quality under .preserveOriginal falls back to JPEG and reports .jpg extension
        let opaqueContext = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 32 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        opaqueContext.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1.0))
        opaqueContext.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let opaqueImage = try XCTUnwrap(opaqueContext.makeImage())
        let opaqueSource = directory.appendingPathComponent("opaque.png")
        let opaqueDest = try XCTUnwrap(CGImageDestinationCreateWithURL(opaqueSource as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(opaqueDest, opaqueImage, [kCGImagePropertyHasAlpha: false] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(opaqueDest))
        
        let opaqueExt = compressor.outputExtension(for: opaqueSource, config: lowQConfig)
        XCTAssertEqual(opaqueExt, "jpg")
        let opaqueOutput = directory.appendingPathComponent("opaque_out.\(opaqueExt)")
        try compressor.compressImage(from: opaqueSource, to: opaqueOutput, config: lowQConfig)
        let decodedOpaque = try XCTUnwrap(CGImageSourceCreateWithURL(opaqueOutput as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(decodedOpaque) as String?, UTType.jpeg.identifier)
        
        // 3. RAW extension (.dng) under .preserveOriginal reports .jpg extension matching JPEG fallback
        let rawURL = directory.appendingPathComponent("photo.dng")
        XCTAssertEqual(compressor.outputExtension(for: rawURL, config: lowQConfig), "jpg")
    }
    
    func testImageCompression() throws {
        // Create a synthetic test bitmap image
        let width = 400
        let height = 300
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create CGContext")
            return
        }
        
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            XCTFail("Failed to create CGImage")
            return
        }
        
        // Save test image to temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("squeezebar_test_\(UUID().uuidString).png")
        let destURL = tempDir.appendingPathComponent("squeezebar_test_\(UUID().uuidString)_min.png")
        
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }
        
        guard let destination = CGImageDestinationCreateWithURL(sourceURL as CFURL, "public.png" as CFString, 1, nil) else {
            XCTFail("Failed creating image destination")
            return
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        
        // Test AcceleratedImageCompressor
        let compressor = AcceleratedImageCompressor()
        let config = CompressionConfiguration(
            formatPolicy: .preserveOriginal,
            qualityPreset: .balanced,
            customQuality: 0.75,
            suffix: "_min"
        )
        
        try compressor.compressImage(from: sourceURL, to: destURL, config: config)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        let destSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
        XCTAssertGreaterThan(destSize, 0)
    }
    
    func testModernFormatConversion() throws {
        // Create test JPEG
        let width = 200
        let height = 200
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.4, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!
        
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("squeezebar_convert_test_\(UUID().uuidString).jpg")
        let destURL = tempDir.appendingPathComponent("squeezebar_convert_test_\(UUID().uuidString)_min.heic")
        
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }
        
        let destination = CGImageDestinationCreateWithURL(sourceURL as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        
        let compressor = AcceleratedImageCompressor()
        let config = CompressionConfiguration(
            formatPolicy: .modernOptimized,
            qualityPreset: .balanced,
            customQuality: 0.70
        )
        
        let targetExt = compressor.outputExtension(for: sourceURL, config: config)
        XCTAssertEqual(targetExt, "heic")
        
        try compressor.compressImage(from: sourceURL, to: destURL, config: config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
    }
    
    func testVideo24FPSToGIFPreservesTotalDuration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        
        let sourceURL = folder.appendingPathComponent("clip24fps.mp4")
        let outputURL = folder.appendingPathComponent("clip24fps.gif")
        
        let width = 128, height = 96
        let fps = 24
        let totalFrames = 48 // 2.0 seconds at 24 fps
        let sourceDurationSeconds = Double(totalFrames) / Double(fps)
        
        let writer = try AVAssetWriter(outputURL: sourceURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = try XCTUnwrap(CGContext(
            data: CVPixelBufferGetBaseAddress(pixels),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        
        let deadline = Date().addingTimeInterval(10)
        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                guard Date() < deadline else {
                    throw HardwareVideoCompressor.VideoCompressorError.encodingFailed("Fixture timed out")
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        
        var config = CompressionConfiguration()
        config.videoCodec = .gif
        config.gifFramerate = .half15
        
        try await HardwareVideoCompressor().compressVideo(from: sourceURL, to: outputURL, config: config)
        
        let gifSource = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let gifFrameCount = CGImageSourceGetCount(gifSource)
        XCTAssertGreaterThan(gifFrameCount, 0)
        
        var totalGIFDuration: Double = 0
        for i in 0..<gifFrameCount {
            let props = CGImageSourceCopyPropertiesAtIndex(gifSource, i, nil) as? [CFString: Any]
            let gifDict = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gifDict?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gifDict?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0
            totalGIFDuration += delay
        }
        
        XCTAssertEqual(totalGIFDuration, sourceDurationSeconds, accuracy: sourceDurationSeconds * 0.10)
    }
}
