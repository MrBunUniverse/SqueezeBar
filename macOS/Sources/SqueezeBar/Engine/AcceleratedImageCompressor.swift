import Foundation
import ImageIO
import UniformTypeIdentifiers
import Accelerate
import CoreGraphics

public struct AcceleratedImageCompressor: Sendable {
    
    public enum ImageCompressorError: LocalizedError {
        case invalidSourceData
        case cannotCreateImageSource
        case cannotCreateDestination
        case cannotFinalizeDestination
        case noImageInSource
        
        public var errorDescription: String? {
            switch self {
            case .invalidSourceData: return String(localized: "Invalid or corrupt image data")
            case .cannotCreateImageSource: return String(localized: "Failed to open image source")
            case .cannotCreateDestination: return String(localized: "Failed to create destination image container")
            case .cannotFinalizeDestination: return String(localized: "Failed to encode and write compressed image")
            case .noImageInSource: return String(localized: "No valid image frame found in file")
            }
        }
    }
    
    public init() {}
    
    // ==========================================================================
    // MARK: - PUBLIC API
    // ==========================================================================
    
    /// Compresses an image file from sourceURL and saves to destinationURL.
    ///
    /// Strategy varies by output format:
    /// - **JPEG / HEIC**: `kCGImageDestinationLossyCompressionQuality` controls quality
    ///   natively.  The slider maps directly to the encoder parameter.
    /// - **PNG** (lossless format):  The ImageIO PNG encoder ignores lossy quality.
    ///   Instead we use two levers that *do* reduce PNG size:
    ///     1. Resolution downscaling (controlled by quality slider)
    ///     2. Strip alpha channel when opaque (saves ~25% raw data)
    ///   At Max Compression we additionally convert the image to JPEG-in-PNG
    ///   (re-encode as JPEG and wrap back — keeping .png extension but lossy).
    public func compressImage(
        from sourceURL: URL,
        to destinationURL: URL,
        config: CompressionConfiguration,
        control: JobControl? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) throws {
        progressHandler?(0.05)
        
        // 1. Open CGImageSource
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions as CFDictionary) else {
            throw ImageCompressorError.cannotCreateImageSource
        }
        
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 0 else {
            throw ImageCompressorError.noImageInSource
        }
        
        progressHandler?(0.15)
        
        // 2. Resolve target format
        let targetUTType = determineTargetUTType(for: sourceURL, config: config)
        let quality = config.imageQuality          // 0.30 … 1.0
        let isLossyFormat = (targetUTType == .jpeg || targetUTType == .heic || targetUTType == .webP || targetUTType.identifier.contains("avif"))
        let isPNG = (targetUTType == .png)
        
        // 3. Choose compression strategy (Manual or Target Size Automated)
        let strategy = compressionStrategy(
            quality: quality,
            targetSizeMB: config.effectiveTargetSizeMB,
            preserveResolution: config.preserveResolutionInTargetMode,
            isPNG: isPNG,
            isLossyFormat: isLossyFormat,
            sourceURL: sourceURL,
            imageSource: imageSource
        )
        
        progressHandler?(0.25)
        
        // 4. Build output
        let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0)!
        
        // For PNG at Max Compression, we re-encode internally as JPEG then wrap
        // the bytes with .png extension — this is the only way to get real lossy
        // compression while keeping the .png filename the user expects.
        let actualOutputType: UTType
        if isPNG && strategy.useJPEGFallback && config.imageFormatPolicy != .pngLossless {
            actualOutputType = .jpeg
        } else {
            actualOutputType = targetUTType
        }
        
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            actualOutputType.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw ImageCompressorError.cannotCreateDestination
        }
        
        // 5. Process each frame
        for i in 0..<frameCount {
            if control?.isCancelled == true { throw CancellationError() }
            let frameProgress = 0.25 + (Double(i) / Double(max(frameCount, 1))) * 0.60
            progressHandler?(frameProgress)
            
            let frameProps = (CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) as? [CFString: Any]) ?? [:]
            
            guard var cgImage = CGImageSourceCreateImageAtIndex(imageSource, i, sourceOptions as CFDictionary) else {
                continue
            }

            // Bake EXIF rotation/mirroring into pixels so stripping metadata cannot turn a portrait sideways.
            if ((frameProps[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) != 1 {
                let orientationOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(cgImage.width, cgImage.height)
                ]
                guard let orientedImage = CGImageSourceCreateThumbnailAtIndex(imageSource, i, orientationOptions as CFDictionary) else {
                    throw ImageCompressorError.noImageInSource
                }
                cgImage = orientedImage
            }
            
            // --- Resolution scaling (preserves aspect ratio without cropping) ---
            let sizedImage: CGImage
            let scaleFactor = CGFloat(config.imageResolutionScale)
            if scaleFactor < 0.999 || strategy.maxDimension != nil {
                sizedImage = resizeImage(
                    cgImage: cgImage,
                    scaleFactor: scaleFactor,
                    maxLongEdge: strategy.maxDimension
                ) ?? cgImage
            } else {
                sizedImage = cgImage
            }
            
            // --- Build per-frame destination properties ---
            var opts: [CFString: Any] = [:]
            
            // Lossy quality (effective for JPEG / HEIC; ignored by PNG encoder)
            opts[kCGImageDestinationLossyCompressionQuality] = Float(strategy.encoderQuality)
            
            // Preserve metadata unless user chose to strip
            if !config.stripMetadata {
                for key in [kCGImagePropertyExifDictionary,
                            kCGImagePropertyTIFFDictionary,
                            kCGImagePropertyIPTCDictionary,
                            kCGImagePropertyColorModel] {
                    if let val = frameProps[key] { opts[key] = val }
                }
                if var tiff = opts[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    tiff[kCGImagePropertyTIFFOrientation] = 1
                    opts[kCGImagePropertyTIFFDictionary] = tiff
                }
            }
            opts[kCGImagePropertyOrientation] = 1
            
            // GIF frame timing
            if let gifProps = frameProps[kCGImagePropertyGIFDictionary] {
                opts[kCGImagePropertyGIFDictionary] = gifProps
            }
            
            CGImageDestinationAddImage(destination, sizedImage, opts as CFDictionary)
        }
        
        progressHandler?(0.88)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressorError.cannotFinalizeDestination
        }
        
        // 6. Write atomically
        let finalData = mutableData as Data
        try finalData.write(to: destinationURL, options: .atomic)
        
        progressHandler?(1.0)
    }
    
    // ==========================================================================
    // MARK: - COMPRESSION STRATEGY
    // ==========================================================================
    
    /// Encapsulates all decisions about how to compress a particular image.
    private struct Strategy {
        /// Max longest-edge pixel dimension.  `nil` = keep original resolution.
        let maxDimension: CGFloat?
        
        /// The quality value passed to the ImageIO encoder (0.0-1.0).
        /// For JPEG/HEIC this directly controls compression.
        /// For PNG the encoder ignores it, but we set it anyway.
        let encoderQuality: Double
        
        /// If true and output is PNG, we actually encode as JPEG internally
        /// (the file gets .png extension but JPEG bytes — this is the only way
        /// to get real lossy compression for a "Preserve Original" PNG workflow).
        let useJPEGFallback: Bool
        
        /// Human-readable label for debugging.
        let label: String
    }
    
    private func compressionStrategy(
        quality: Double,
        targetSizeMB: Double?,
        preserveResolution: Bool,
        isPNG: Bool,
        isLossyFormat: Bool,
        sourceURL: URL,
        imageSource: CGImageSource
    ) -> Strategy {
        let sourceAttrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let sourceSize = (sourceAttrs?[.size] as? Int64) ?? 0
        let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let srcWidth = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let srcHeight = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let longEdge = CGFloat(max(srcWidth, srcHeight))
        
        // --- Target Size Automated Mode ---
        if let targetMB = targetSizeMB {
            let targetBytes = targetMB * 1024.0 * 1024.0 * 0.95
            
            if Double(sourceSize) <= targetBytes {
                return Strategy(
                    maxDimension: nil,
                    encoderQuality: 0.95,
                    useJPEGFallback: false,
                    label: "already under target size"
                )
            }
            
            let ratio = targetBytes / Double(max(sourceSize, 1))
            
            if isLossyFormat {
                let calculatedQ: Double
                if preserveResolution {
                    // Aggressive quality reduction to fit target size without changing resolution
                    calculatedQ = min(0.85, max(0.12, ratio * 0.70))
                } else {
                    calculatedQ = min(0.90, max(0.20, sqrt(ratio) * 0.85))
                }
                
                let maxDim: CGFloat?
                if preserveResolution {
                    maxDim = nil // Lock 100% full original resolution
                } else {
                    maxDim = (ratio < 0.20 && longEdge > 2560) ? 2560 : ((ratio < 0.10 && longEdge > 1920) ? 1920 : nil)
                }
                
                return Strategy(
                    maxDimension: maxDim,
                    encoderQuality: calculatedQ,
                    useJPEGFallback: false,
                    label: "targetSize lossy q=\(calculatedQ)"
                )
            } else if isPNG {
                if ratio < 0.60 || preserveResolution {
                    let calculatedQ = min(0.85, max(0.15, ratio * 0.65))
                    let maxDim: CGFloat? = preserveResolution ? nil : ((ratio < 0.30 && longEdge > 2560) ? 2560 : ((ratio < 0.15 && longEdge > 1920) ? 1920 : nil))
                    return Strategy(
                        maxDimension: maxDim,
                        encoderQuality: calculatedQ,
                        useJPEGFallback: true,
                        label: "targetSize png-jpeg q=\(calculatedQ)"
                    )
                } else {
                    let scale = min(1.0, max(0.30, sqrt(ratio)))
                    let maxDim = longEdge * scale
                    return Strategy(
                        maxDimension: maxDim,
                        encoderQuality: 1.0,
                        useJPEGFallback: false,
                        label: "targetSize png downscale"
                    )
                }
            }
        }
        
        // --- Manual Quality Mode ---
        // --- JPEG / HEIC (lossy formats) ---
        if isLossyFormat {
            let maxDim: CGFloat?
            if quality <= 0.50 {
                maxDim = 2048
            } else if quality <= 0.65 {
                maxDim = 3072
            } else {
                maxDim = nil  // keep original resolution
            }
            return Strategy(
                maxDimension: maxDim,
                encoderQuality: quality,
                useJPEGFallback: false,
                label: "lossy-direct q=\(quality)"
            )
        }
        
        // --- PNG (lossless format) ---
        if isPNG {
            // Visually Lossless (quality >= 0.85): keep full resolution, full color
            if quality >= 0.85 {
                return Strategy(
                    maxDimension: nil,
                    encoderQuality: 1.0,
                    useJPEGFallback: false,
                    label: "png-lossless"
                )
            }
            
            // Balanced (quality 0.65 ..< 0.85): downscale very large images
            if quality >= 0.65 {
                let targetLong: CGFloat = longEdge > 3840 ? 3840 : CGFloat(longEdge)
                return Strategy(
                    maxDimension: targetLong,
                    encoderQuality: 1.0,
                    useJPEGFallback: false,
                    label: "png-balanced-downscale"
                )
            }
            
            // Max Compression (quality < 0.65): re-encode as JPEG internally
            let jpegQ = 0.40 + (quality - 0.30) * (0.70 - 0.40) / (0.64 - 0.30)
            let clampedJpegQ = min(max(jpegQ, 0.35), 0.75)
            let targetLong: CGFloat = longEdge > 2560 ? 2560 : CGFloat(longEdge)
            return Strategy(
                maxDimension: targetLong,
                encoderQuality: clampedJpegQ,
                useJPEGFallback: true,
                label: "png-maxcompress-jpeg q=\(clampedJpegQ)"
            )
        }
        
        // --- TIFF / BMP / GIF / other lossless formats ---
        return Strategy(
            maxDimension: quality <= 0.60 ? 2048 : nil,
            encoderQuality: quality,
            useJPEGFallback: false,
            label: "other q=\(quality)"
        )
    }
    
    // ==========================================================================
    // MARK: - HIGH-QUALITY RESIZE (Aspect-Ratio Preserving, Zero Cropping)
    // ==========================================================================
    
    /// Downscales an image by scaleFactor or so that its longest edge is <= maxLongEdge.
    /// Preserves exact aspect ratio with zero cropping using high-quality interpolation.
    private func resizeImage(cgImage: CGImage, scaleFactor: CGFloat = 1.0, maxLongEdge: CGFloat? = nil) -> CGImage? {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let longEdge = max(srcW, srcH)
        
        var effectiveScale = min(max(scaleFactor, 0.10), 1.0)
        if let maxDim = maxLongEdge, longEdge * effectiveScale > maxDim {
            effectiveScale = maxDim / longEdge
        }
        
        guard effectiveScale < 0.999 else { return cgImage }
        
        let dstW = max(1, Int((srcW * effectiveScale).rounded()))
        let dstH = max(1, Int((srcH * effectiveScale).rounded()))
        
        guard dstW > 0, dstH > 0 else { return cgImage }
        
        // Use CGContext with high-quality interpolation
        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let hasAlpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipLast && cgImage.alphaInfo != .noneSkipFirst
        let bitmapInfo = hasAlpha
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,  // let CG choose optimal stride
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        return ctx.makeImage()
    }
    
    // ==========================================================================
    // MARK: - TARGET TYPE RESOLUTION
    // ==========================================================================
    
    public func determineTargetUTType(for sourceURL: URL, config: CompressionConfiguration) -> UTType {
        let ext = sourceURL.pathExtension.lowercased()
        
        switch config.imageFormatPolicy {
        case .heicModern:
            return .heic
        case .webpModern:
            return UTType.webP
        case .avifModern:
            return UTType(tag: "avif", tagClass: .filenameExtension, conformingTo: .image) ?? .heic
        case .jpegStandard:
            return .jpeg
        case .pngLossless:
            return .png
        case .preserveOriginal:
            switch ext {
            case "jpg", "jpeg":  return .jpeg
            case "png":          return .png
            case "heic", "heif": return .heic
            case "webp":         return UTType.webP
            case "avif":         return UTType(tag: "avif", tagClass: .filenameExtension, conformingTo: .image) ?? .heic
            case "gif":          return .gif
            case "tif", "tiff":  return .tiff
            case "bmp":          return .bmp
            default:
                if let utType = UTType(filenameExtension: ext),
                   utType.conforms(to: .image) {
                    let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
                    if supported.contains(utType.identifier) { return utType }
                }
                return .jpeg
            }
        }
    }
    
    public func outputExtension(for sourceURL: URL, config: CompressionConfiguration) -> String {
        let ext = sourceURL.pathExtension.lowercased()
        switch config.imageFormatPolicy {
        case .heicModern:   return "heic"
        case .webpModern:   return "webp"
        case .avifModern:   return "avif"
        case .jpegStandard: return "jpg"
        case .pngLossless:  return "png"
        case .preserveOriginal:
            return ext.isEmpty ? "jpg" : ext
        }
    }
}
