import XCTest
import AppKit
import PDFKit
@testable import SqueezeBar

final class PDFCompressorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// One page of text, then (optionally) one page holding a photo-like image.
    private func makePDF(_ url: URL, withImagePage: Bool) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (String(repeating: "Searchable text stays text. ", count: 80) as NSString)
            .draw(in: box.insetBy(dx: 40, dy: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        ctx.endPDFPage()
        if withImagePage {
            let bitmap = CGContext(data: nil, width: 1200, height: 1600, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let p = bitmap.data!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<(bitmap.bytesPerRow * 1600) { p[i] = UInt8.random(in: 0...255) }
            ctx.beginPDFPage(nil)
            ctx.draw(bitmap.makeImage()!, in: box)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    func testTextPagesKeepTheirTextAndImagePagesAreRecompressed() throws {
        let src = dir.appendingPathComponent("mixed.pdf")
        makePDF(src, withImagePage: true)
        let source = try XCTUnwrap(PDFDocument(url: src))
        XCTAssertFalse(AcceleratedPDFCompressor.pageHasImages(try XCTUnwrap(source.page(at: 0)?.pageRef)))
        XCTAssertTrue(AcceleratedPDFCompressor.pageHasImages(try XCTUnwrap(source.page(at: 1)?.pageRef)))

        let out = dir.appendingPathComponent("mixed_min.pdf")
        try AcceleratedPDFCompressor().compressPDF(from: src, to: out, config: CompressionConfiguration()) { _ in }
        let result = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(result.pageCount, 2)
        XCTAssertTrue(result.page(at: 0)?.string?.contains("Searchable text stays text.") == true)
        let srcSize = try XCTUnwrap(src.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let outSize = try XCTUnwrap(out.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThan(outSize, srcSize)
    }

    func testPasswordProtectedPDFIsRefused() throws {
        let plain = dir.appendingPathComponent("plain.pdf")
        makePDF(plain, withImagePage: false)
        let locked = dir.appendingPathComponent("locked.pdf")
        XCTAssertTrue(try XCTUnwrap(PDFDocument(url: plain)).write(to: locked, withOptions: [.userPasswordOption: "pw", .ownerPasswordOption: "owner"]))
        XCTAssertThrowsError(try AcceleratedPDFCompressor().compressPDF(from: locked, to: dir.appendingPathComponent("locked_min.pdf"), config: CompressionConfiguration()) { _ in }) {
            XCTAssertEqual($0 as? PDFCompressorError, .passwordProtected)
        }
    }
}
