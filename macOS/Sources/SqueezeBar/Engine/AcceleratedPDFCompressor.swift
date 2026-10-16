import Foundation
import AppKit
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum PDFCompressorError: LocalizedError, Sendable {
    case invalidDocument
    case passwordProtected
    case cannotCreatePage
    case cannotWriteDestination
    
    public var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return String(localized: "Unable to open or parse the PDF document.")
        case .passwordProtected:
            return String(localized: "This PDF is password-protected. Remove the password, then try again.")
        case .cannotCreatePage:
            return String(localized: "Failed to render or compress PDF pages.")
        case .cannotWriteDestination:
            return String(localized: "Failed to save the compressed PDF to destination.")
        }
    }
}

public struct AcceleratedPDFCompressor: Sendable {
    public init() {}
    
    public func outputExtension(for url: URL, config: CompressionConfiguration) -> String {
        return "pdf"
    }
    
    public func compressPDF(
        from sourceURL: URL,
        to destinationURL: URL,
        config: CompressionConfiguration,
        control: JobControl? = nil,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) throws {
        guard let sourceDoc = PDFDocument(url: sourceURL), sourceDoc.pageCount > 0 else {
            throw PDFCompressorError.invalidDocument
        }
        // A locked PDF renders as blank pages; refuse rather than save an empty, unprotected copy.
        guard !sourceDoc.isLocked else {
            throw PDFCompressorError.passwordProtected
        }
        
        let totalPages = sourceDoc.pageCount
        var targetDPI = config.pdfDPI.dpiValue
        var targetQuality = config.pdfImageQuality
        
        // Smart Target Size Adaptation
        if let targetMB = config.effectiveTargetSizeMB {
            let srcSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
            let targetBytes = targetMB * 1024.0 * 1024.0
            
            if Double(srcSize) > targetBytes {
                let budgetPerPage = targetBytes / Double(totalPages)
                if budgetPerPage < 60_000 {
                    // Under 60KB per page: tight budget
                    targetDPI = min(targetDPI, 72.0)
                    targetQuality = min(targetQuality, 0.50)
                } else if budgetPerPage < 180_000 {
                    // Under 180KB per page: moderate budget
                    targetDPI = min(targetDPI, 120.0)
                    targetQuality = min(targetQuality, 0.65)
                } else if budgetPerPage < 400_000 {
                    targetDPI = min(targetDPI, 150.0)
                    targetQuality = min(targetQuality, 0.75)
                }
            }
        }
        
        let outputDoc = PDFDocument()
        
        for index in 0..<totalPages {
            if control?.isCancelled == true { throw CancellationError() }
            guard let page = sourceDoc.page(at: index) else { throw PDFCompressorError.cannotCreatePage }
            
            // Text and vector pages are copied as they are: rendering them to JPEG loses the text and usually grows the file.
            if let cgPage = page.pageRef, !Self.pageHasImages(cgPage) {
                guard let copy = page.copy() as? PDFPage else { throw PDFCompressorError.cannotCreatePage }
                outputDoc.insert(copy, at: outputDoc.pageCount)
                progressHandler(Double(index + 1) / Double(totalPages))
                continue
            }
            
            let mediaBounds = page.bounds(for: .mediaBox)
            let pageRotation = page.rotation
            
            let scale = max(0.5, targetDPI / 72.0)
            let pixelW = max(1, Int((mediaBounds.width * scale).rounded()))
            let pixelH = max(1, Int((mediaBounds.height * scale).rounded()))
            
            // Render Page to Bitmap
            let colorSpace: CGColorSpace
            let bitmapInfo: UInt32
            if config.pdfGrayscale {
                colorSpace = CGColorSpaceCreateDeviceGray()
                bitmapInfo = CGImageAlphaInfo.none.rawValue
            } else {
                colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            }
            
            guard let context = CGContext(
                data: nil,
                width: pixelW,
                height: pixelH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                throw PDFCompressorError.cannotCreatePage
            }
            
            context.interpolationQuality = .high
            
            // Fill background white
            if config.pdfGrayscale {
                context.setFillColor(gray: 1.0, alpha: 1.0)
            } else {
                context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            }
            context.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
            
            // Apply scale
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            
            guard let cgImage = context.makeImage() else {
                throw PDFCompressorError.cannotCreatePage
            }
            
            // JPEG Recompression of page image
            let imgData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                imgData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw PDFCompressorError.cannotCreatePage
            }
            
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: targetQuality as CFNumber
            ]
            CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
            CGImageDestinationFinalize(dest)
            
            guard let compressedImage = NSImage(data: imgData as Data),
                  let newPage = PDFPage(image: compressedImage) else {
                throw PDFCompressorError.cannotCreatePage
            }
            
            newPage.setBounds(mediaBounds, for: .mediaBox)
            if pageRotation != 0 {
                newPage.rotation = pageRotation
            }
            
            outputDoc.insert(newPage, at: outputDoc.pageCount)
            
            let progress = Double(index + 1) / Double(totalPages)
            progressHandler(progress)
        }
        
        // Metadata Policy
        if !config.pdfStripMetadata {
            outputDoc.documentAttributes = sourceDoc.documentAttributes
        } else {
            outputDoc.documentAttributes = [
                PDFDocumentAttribute.producerAttribute: "SqueezeBar PDF Optimizer"
            ]
        }
        
        guard outputDoc.pageCount > 0 else {
            throw PDFCompressorError.cannotCreatePage
        }
        
        let success = outputDoc.write(to: destinationURL)
        if !success {
            throw PDFCompressorError.cannotWriteDestination
        }
    }
    
    /// Whether the page draws a raster image (an Image XObject, directly or inside a Form XObject).
    /// ponytail: inline images (BI…EI in the content stream) aren't seen, so such pages are kept as they are.
    static func pageHasImages(_ page: CGPDFPage) -> Bool {
        // Resources can be inherited from the page tree, so walk up through Parent.
        var node = page.dictionary
        while let current = node {
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources {
                return resourcesHaveImages(resources, depth: 0)
            }
            var parent: CGPDFDictionaryRef?
            node = CGPDFDictionaryGetDictionary(current, "Parent", &parent) ? parent : nil
        }
        return false
    }
    
    private static func resourcesHaveImages(_ resources: CGPDFDictionaryRef, depth: Int) -> Bool {
        var xobjects: CGPDFDictionaryRef?
        guard depth < 4, CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return false }
        var found = false
        CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype else { return true }
            switch String(cString: subtype) {
            case "Image":
                found = true
            case "Form":
                var formResources: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dict, "Resources", &formResources), let formResources {
                    found = resourcesHaveImages(formResources, depth: depth + 1)
                }
            default:
                break
            }
            return !found
        }, nil)
        return found
    }
}
