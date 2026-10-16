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
    ///   The bytes written always match the file's extension: a PNG never becomes JPEG data behind a .png name.
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
        
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            targetUTType.identifier as CFString,
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
            if let gifProps = frameProps[kCGImagePropertyGIFDictionary] {
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
                    label: "targetSize lossy q=\(calculatedQ)"
                )
            } else if isPNG {
                // PNG is lossless, so the only lever is resolution. Pick JPEG or HEIC output for real lossy savings.
                let scale = min(1.0, max(0.30, sqrt(ratio)))
                return Strategy(
                    maxDimension: preserveResolution ? nil : longEdge * scale,
                    encoderQuality: 1.0,
                    label: "targetSize png downscale"
                )
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
                    label: "png-lossless"
                )
            }
            
            // Balanced (quality 0.65 ..< 0.85): downscale very large images
            if quality >= 0.65 {
                let targetLong: CGFloat = longEdge > 3840 ? 3840 : CGFloat(longEdge)
                return Strategy(
                    maxDimension: targetLong,
                    encoderQuality: 1.0,
                    label: "png-balanced-downscale"
                )
            }
            
            // Max Compression (quality < 0.65): downscale further, still PNG
            let targetLong: CGFloat = longEdge > 2560 ? 2560 : CGFloat(longEdge)
            return Strategy(
                maxDimension: targetLong,
                encoderQuality: 1.0,
                label: "png-maxcompress-downscale"
            )
        }
        
        // --- TIFF / BMP / GIF / other lossless formats ---
        return Strategy(
            maxDimension: quality <= 0.60 ? 2048 : nil,
            encoderQuality: quality,
            label: "other q=\(quality)"
        )
    }
    
    // ==========================================================================
    // MARK: - TARGET TYPE RESOLUTION
    // ==========================================================================
    
    /// Whether this Mac's ImageIO can encode the type (it reads WebP but cannot write it).
    public static func canWrite(_ type: UTType) -> Bool {
        ((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []).contains(type.identifier)
    }
    
    public func determineTargetUTType(for sourceURL: URL, config: CompressionConfiguration) -> UTType {
        let wanted: UTType?
        switch config.imageFormatPolicy {
        case .heicModern:   wanted = .heic
        case .webpModern:   wanted = .webP
        case .avifModern:   wanted = UTType(filenameExtension: "avif")
        case .jpegStandard: wanted = .jpeg
        case .pngLossless:  wanted = .png
        case .preserveOriginal:
            let sourceType = UTType(filenameExtension: sourceURL.pathExtension.lowercased())
            wanted = sourceType == .heif ? .heic : sourceType // ImageIO writes HEIF as public.heic
        }
        if let wanted, wanted.conforms(to: .image), Self.canWrite(wanted) { return wanted }
        // Not writable here (WebP, camera RAW, PSD…): PNG keeps transparency, JPEG for everything else.
        return Self.hasAlpha(sourceURL) ? .png : .jpeg
    }
    
    private static func hasAlpha(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return (props[kCGImagePropertyHasAlpha] as? Bool) ?? false
    }
    
    /// The extension matching what compressImage writes. Keeps the source's own spelling (jpeg, tif) for its format.
    public func outputExtension(for sourceURL: URL, config: CompressionConfiguration) -> String {
        let type = determineTargetUTType(for: sourceURL, config: config)
        let sourceExt = sourceURL.pathExtension.lowercased()
        if UTType(filenameExtension: sourceExt) == type { return sourceExt }
        return type == .jpeg ? "jpg" : (type.preferredFilenameExtension ?? "jpg")
    }
}
