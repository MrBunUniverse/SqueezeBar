import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import SqueezeBar

/// The bytes written must always match the output file's extension.
final class ImageFormatTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-format-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeTransparentPNG(_ url: URL, width: Int = 1600, height: Int = 1200) {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(ctx.bytesPerRow * height) { p[i] = i % 4 == 3 ? 128 : UInt8.random(in: 0...127) }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func written(_ url: URL) -> (type: String?, alpha: Bool) {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        return (CGImageSourceGetType(src) as String?, (props?[kCGImagePropertyHasAlpha] as? Bool) ?? false)
    }

    func testPNGInTargetSizeModeStaysPNGWithTransparency() throws {
        let src = dir.appendingPathComponent("shot.png")
        writeTransparentPNG(src)
        var config = CompressionConfiguration()
        config.targetSizeMode = .web2
        let compressor = AcceleratedImageCompressor()
        let out = dir.appendingPathComponent("shot_min.\(compressor.outputExtension(for: src, config: config))")
        try compressor.compressImage(from: src, to: out, config: config)
        XCTAssertEqual(out.pathExtension, "png")
        XCTAssertEqual(written(out).type, UTType.png.identifier)
        XCTAssertTrue(written(out).alpha)
    }

    func testUnwritableSourceFormatsGetAMatchingExtension() {
        let compressor = AcceleratedImageCompressor()
        let config = CompressionConfiguration()
        for ext in ["cr2", "dng", "nef", "arw"] {
            let url = URL(fileURLWithPath: "/tmp/photo.\(ext)")
            XCTAssertEqual(compressor.outputExtension(for: url, config: config), "jpg", ext)
            XCTAssertEqual(compressor.determineTargetUTType(for: url, config: config), .jpeg, ext)
        }
        XCTAssertEqual(compressor.outputExtension(for: URL(fileURLWithPath: "/tmp/a.jpeg"), config: config), "jpeg")
        XCTAssertEqual(compressor.outputExtension(for: URL(fileURLWithPath: "/tmp/a.heif"), config: config), "heic")
    }

    func testWebPChoiceFallsBackToPNGForTransparentImages() throws {
        try XCTSkipIf(AcceleratedImageCompressor.canWrite(.webP), "this Mac can write WebP")
        XCTAssertFalse(ImageFormatPolicy.available.contains(.webpModern))
        let src = dir.appendingPathComponent("logo.png")
        writeTransparentPNG(src, width: 200, height: 200)
        var config = CompressionConfiguration()
        config.imageFormatPolicy = .webpModern
        let compressor = AcceleratedImageCompressor()
        let out = dir.appendingPathComponent("logo_min.\(compressor.outputExtension(for: src, config: config))")
        try compressor.compressImage(from: src, to: out, config: config)
        XCTAssertEqual(out.pathExtension, "png")
        XCTAssertEqual(written(out).type, UTType.png.identifier)
    }
}
