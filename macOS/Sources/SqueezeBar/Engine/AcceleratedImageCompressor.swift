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
        
        // 2. Resolve target format and compression strategy
        let (actualOutputType, strategy) = resolvedEncodingPlan(
            for: sourceURL,
            imageSource: imageSource,
            config: config
        )
        
        progressHandler?(0.25)
        
        // 3. Build output
        let isSingleFrameOutput = (actualOutputType == .jpeg || actualOutputType == .heic || actualOutputType == .png || actualOutputType == .bmp)
        let outputFrameCount = isSingleFrameOutput ? 1 : frameCount
        let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0)!
        
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            actualOutputType.identifier as CFString,
            outputFrameCount,
            nil
        ) else {
            throw ImageCompressorError.cannotCreateDestination
        }
        
        if actualOutputType == .gif,
           let sourceProps = CGImageSourceCopyProperties(imageSource, nil) as? [CFString: Any],
           let gifContainerProps = sourceProps[kCGImagePropertyGIFDictionary] {
            CGImageDestinationSetProperties(
                destination,
                [kCGImagePropertyGIFDictionary: gifContainerProps] as CFDictionary
            )
        }
        
        // 5. Process each frame
        for i in 0..<outputFrameCount {
            if control?.isCancelled == true { throw CancellationError() }
            let frameProgress = 0.25 + (Double(i) / Double(max(outputFrameCount, 1))) * 0.60
            progressHandler?(frameProgress)
            
            let frameProps = (CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) as? [CFString: Any]) ?? [:]
            
            // Decode once, at the output size: ImageIO applies EXIF rotation and downscales in the same pass.
            let sourceLongEdge = CGFloat(max((frameProps[kCGImagePropertyPixelWidth] as? Int) ?? 0, (frameProps[kCGImagePropertyPixelHeight] as? Int) ?? 0))
            let scaleFactor = CGFloat(config.imageResolutionScale)
            var targetLongEdge = sourceLongEdge
            if scaleFactor < 0.999 || strategy.maxDimension != nil {
                targetLongEdge = min(sourceLongEdge * min(max(scaleFactor, 0.10), 1.0), strategy.maxDimension ?? .greatestFiniteMagnitude)
            }
            // Bake EXIF rotation/mirroring into pixels so stripping metadata cannot turn a portrait sideways.
            let needsRotation = ((frameProps[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) != 1
            let cgImage: CGImage
            if needsRotation || Int(targetLongEdge.rounded()) < Int(sourceLongEdge.rounded()) {
                let thumbnailOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, Int(targetLongEdge.rounded()))
                ]
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, i, thumbnailOptions as CFDictionary) else {
                    throw ImageCompressorError.noImageInSource
                }
                cgImage = thumbnail
            } else {
                guard let image = CGImageSourceCreateImageAtIndex(imageSource, i, sourceOptions as CFDictionary) else {
                    continue
                }
                cgImage = image
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
            if actualOutputType == .gif, let gifProps = frameProps[kCGImagePropertyGIFDictionary] {
                opts[kCGImagePropertyGIFDictionary] = gifProps
            }
            
            CGImageDestinationAddImage(destination, cgImage, opts as CFDictionary)
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
        
        /// If true and output is an opaque PNG under Preserve Original, we encode as JPEG
        /// and emit a .jpg extension so format and extension stay in sync.
        let useJPEGFallback: Bool
        
        /// Human-readable label for debugging.
        let label: String
    }
    
    private func resolvedEncodingPlan(
        for sourceURL: URL,
        imageSource: CGImageSource?,
        config: CompressionConfiguration
    ) -> (actualOutputType: UTType, strategy: Strategy) {
        let targetUTType = determineTargetUTType(for: sourceURL, config: config)
        let quality = config.imageQuality          // 0.30 … 1.0
        let isLossyFormat = (targetUTType == .jpeg || targetUTType == .heic || targetUTType == .webP || targetUTType.identifier.contains("avif"))
        let isPNG = (targetUTType == .png)
        
        let openedSource = imageSource ?? CGImageSourceCreateWithURL(sourceURL as CFURL, nil)
        let hasAlpha = Self.sourceHasAlpha(openedSource)
        
        let strategy = compressionStrategy(
            quality: quality,
            targetSizeMB: config.effectiveTargetSizeMB,
            preserveResolution: config.preserveResolutionInTargetMode,
            isPNG: isPNG,
            hasAlpha: hasAlpha,
            isLossyFormat: isLossyFormat,
            sourceURL: sourceURL,
            imageSource: openedSource
        )
        
        let actualOutputType: UTType
        if isPNG && strategy.useJPEGFallback && !hasAlpha && config.imageFormatPolicy != .pngLossless {
            actualOutputType = .jpeg
        } else {
            actualOutputType = targetUTType
        }
        
        return (actualOutputType, strategy)
    }
    
    private static func sourceHasAlpha(_ imageSource: CGImageSource?) -> Bool {
        guard let imageSource else { return false }
        let frameCount = max(CGImageSourceGetCount(imageSource), 1)
        for i in 0..<frameCount {
            if let props = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) as? [CFString: Any],
               let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool {
                if hasAlpha { return true }
                continue
            }
            if let cgImage = CGImageSourceCreateImageAtIndex(imageSource, i, nil) {
                let alpha = cgImage.alphaInfo
                if alpha != .none && alpha != .noneSkipLast && alpha != .noneSkipFirst {
                    return true
                }
            }
        }
        return false
    }
    
    private func compressionStrategy(
        quality: Double,
        targetSizeMB: Double?,
        preserveResolution: Bool,
        isPNG: Bool,
        hasAlpha: Bool,
        isLossyFormat: Bool,
        sourceURL: URL,
        imageSource: CGImageSource?
    ) -> Strategy {
        let sourceAttrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let sourceSize = (sourceAttrs?[.size] as? Int64) ?? 0
        let props = imageSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let srcWidth = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let srcHeight = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let longEdge = CGFloat(max(srcWidth, srcHeight))
        
        // --- Target Size Automated Mode ---
        if let targetMB = targetSizeMB {
            let targetBytes = targetMB * 1024.0 * 1024.0 * 0.95
            
            if sourceSize > 0 && Double(sourceSize) <= targetBytes {
                return Strategy(
                    maxDimension: nil,
                    encoderQuality: 0.95,
                    useJPEGFallback: false,
                    label: "already under target size"
                )
            }
            
            let ratio = sourceSize > 0 ? (targetBytes / Double(sourceSize)) : 0.50
            
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
                if !hasAlpha && (ratio < 0.60 || preserveResolution) {
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
                    let maxDim: CGFloat? = preserveResolution ? nil : (longEdge > 0 ? longEdge * scale : nil)
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
                let targetLong: CGFloat? = longEdge > 3840 ? 3840 : (longEdge > 0 ? CGFloat(longEdge) : nil)
                return Strategy(
                    maxDimension: targetLong,
                    encoderQuality: 1.0,
                    useJPEGFallback: false,
                    label: "png-balanced-downscale"
                )
            }
            
            // Max Compression (quality < 0.65): re-encode as JPEG only when opaque
            let targetLong: CGFloat? = longEdge > 2560 ? 2560 : (longEdge > 0 ? CGFloat(longEdge) : nil)
            if hasAlpha {
                return Strategy(
                    maxDimension: targetLong,
                    encoderQuality: 1.0,
                    useJPEGFallback: false,
                    label: "png-maxcompress-alpha-downscale"
                )
            }
            let jpegQ = 0.40 + (quality - 0.30) * (0.70 - 0.40) / (0.64 - 0.30)
            let clampedJpegQ = min(max(jpegQ, 0.35), 0.75)
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
    // MARK: - TARGET TYPE RESOLUTION
    // ==========================================================================
    
    private static func writableDestinationType(_ preferred: UTType, supported: Set<String>) -> UTType {
        if supported.contains(preferred.identifier) {
            return preferred
        }
        if supported.contains(UTType.heic.identifier) {
            return .heic
        }
        return .jpeg
    }
    
    public func determineTargetUTType(for sourceURL: URL, config: CompressionConfiguration) -> UTType {
        let ext = sourceURL.pathExtension.lowercased()
        let supported = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let avifType = UTType(tag: "avif", tagClass: .filenameExtension, conformingTo: .image) ?? .heic
        
        let candidate: UTType
        switch config.imageFormatPolicy {
        case .heicModern:
            candidate = .heic
        case .webpModern:
            candidate = .webP
        case .avifModern:
            candidate = avifType
        case .jpegStandard:
            candidate = .jpeg
        case .pngLossless:
            candidate = .png
        case .preserveOriginal:
            switch ext {
            case "jpg", "jpeg":  candidate = .jpeg
            case "png":          candidate = .png
            case "heic", "heif": candidate = .heic
            case "webp":         candidate = .webP
            case "avif":         candidate = avifType
            case "gif":          candidate = .gif
            case "tif", "tiff":  candidate = .tiff
            case "bmp":          candidate = .bmp
            default:
                if let utType = UTType(filenameExtension: ext),
                   utType.conforms(to: .image),
                   supported.contains(utType.identifier) {
                    return utType
                }
                return .jpeg
            }
        }
        
        return Self.writableDestinationType(candidate, supported: supported)
    }
    
    public func outputExtension(for sourceURL: URL, config: CompressionConfiguration) -> String {
        let (actualOutputType, _) = resolvedEncodingPlan(
            for: sourceURL,
            imageSource: nil,
            config: config
        )
        let ext = sourceURL.pathExtension.lowercased()
        
        switch actualOutputType {
        case .jpeg:
            return (config.imageFormatPolicy == .preserveOriginal && ext == "jpeg") ? "jpeg" : "jpg"
        case .png:
            return "png"
        case .heic:
            return (config.imageFormatPolicy == .preserveOriginal && ext == "heif") ? "heif" : "heic"
        case .webP:
            return "webp"
        case .gif:
            return "gif"
        case .tiff:
            return (config.imageFormatPolicy == .preserveOriginal && ext == "tif") ? "tif" : "tiff"
        case .bmp:
            return "bmp"
        default:
            if actualOutputType.identifier.contains("avif") {
                return "avif"
            }
            return actualOutputType.preferredFilenameExtension ?? (ext.isEmpty ? "jpg" : ext)
        }
    }
}
