import Foundation
import AppKit
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum PDFCompressorError: LocalizedError, Sendable {
    case invalidDocument
    case cannotCreatePage
    case cannotWriteDestination
    
    public var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return String(localized: "Unable to open or parse the PDF document.")
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
            guard let page = sourceDoc.page(at: index) else { continue }
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
                continue
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
                continue
            }
            
            // JPEG Recompression of page image
            let imgData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                imgData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                continue
            }
            
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: targetQuality as CFNumber
            ]
            CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
            CGImageDestinationFinalize(dest)
            
            guard let compressedImage = NSImage(data: imgData as Data),
                  let newPage = PDFPage(image: compressedImage) else {
                continue
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
}
