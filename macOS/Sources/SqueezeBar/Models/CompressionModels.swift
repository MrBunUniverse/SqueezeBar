import Foundation
import UniformTypeIdentifiers
import AVFoundation

// MARK: - UI Scaling / Display Density
public enum UIScaleOption: String, Codable, Sendable, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    
    public var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.00
        case .large: return 1.18
        }
    }
    
    public var percentageLabel: String {
        switch self {
        case .small: return "85%"
        case .medium: return "100%"
        case .large: return "118%"
        }
    }
    
    public var description: String {
        switch self {
        case .small: return "Compact density (85%) for 13\" MacBook Air / smaller displays."
        case .medium: return "Standard default scale (100%) optimized for MacBook Pro."
        case .large: return "Expanded size (118%) for 16\" MacBook Pro, Studio Display, or 4K monitors."
        }
    }
    
    public var baseWidth: CGFloat {
        switch self {
        case .small: return 416
        case .medium: return 490
        case .large: return 578
        }
    }
    
    public var baseHeight: CGFloat {
        switch self {
        case .small: return 560
        case .medium: return 660
        case .large: return 778
        }
    }
}

// MARK: - DropBall Animation Style
public enum DropBallAnimationStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case calm = "Calm"
    case standard = "Standard"
    case exaggerated = "Exaggerated"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .calm: return "leaf.fill"
        case .standard: return "drop.fill"
        case .exaggerated: return "sparkles"
        }
    }
    
    public var description: String {
        switch self {
        case .calm: return "Soft, minimal ease with gentle edge tucking"
        case .standard: return "Crisp, balanced liquid glass bounce"
        case .exaggerated: return "Exaggerated fluid spring with juicy jelly bounce"
        }
    }
}

// MARK: - DropBall Glass Style (Templates)
public enum DropBallGlassStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case superClear = "Crystal Clear"
    case balanced = "Balanced"
    case opaque = "High Contrast"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .superClear: return "sparkles"
        case .balanced: return "circle.lefthalf.filled"
        case .opaque: return "circle.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .superClear: return "100% transparent crystal glass with pure optical dispersion"
        case .balanced: return "Frosted liquid glass with gentle ambient depth"
        case .opaque: return "Deep obsidian dark glass for maximum contrast"
        }
    }
    
    public var clarity: Double {
        switch self {
        case .superClear: return 1.00    // 0% dark tint (100% transparent)
        case .balanced: return 0.50      // 42% dark tint
        case .opaque: return 0.05        // 80% solid dark tint
        }
    }
    
    public var frost: Double {
        switch self {
        case .superClear: return 0.00    // Pure crystalline clear
        case .balanced: return 0.12      // Soft milky frosted diffusion
        case .opaque: return 0.28        // Dense frosted body
        }
    }
    
    public var depth: Double {
        switch self {
        case .superClear: return 0.04    // Minimal gradient for maximum refraction
        case .balanced: return 0.22      // Balanced 3D convex depth
        case .opaque: return 0.40        // Smooth dark body
        }
    }
    
    public var sheen: Double {
        switch self {
        case .superClear: return 0.28    // Bright crystalline caustic glare
        case .balanced: return 0.14      // Soft ambient top sheen
        case .opaque: return 0.00        // No edge glare/sheen highlight
        }
    }
    
    public var rim: Double {
        switch self {
        case .superClear: return 0.35    // Razor-sharp luminous rim
        case .balanced: return 0.24      // Natural subtle border
        case .opaque: return 0.00        // No edge highlight border
        }
    }
    
    public var rimWidth: CGFloat {
        switch self {
        case .superClear: return 0.75
        case .balanced: return 1.00
        case .opaque: return 0.00        // Zero width border
        }
    }
}

// MARK: - Accent Color Theme
public enum AccentColorTheme: String, Codable, Sendable, CaseIterable {
    case custom = "Custom"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case graphite = "Graphite"
}

// MARK: - Menu Bar Display Style (Supporter Customization)
public enum MenuBarDisplayStyle: String, Codable, Sendable, CaseIterable {
    case iconOnly = "Standard Icon"
    case liveSavings = "Icon + Live Savings"
    case minimalMonochrome = "Minimalist Dot"
    
    public var iconName: String {
        switch self {
        case .iconOnly: return "arrow.down.right.and.arrow.up.left"
        case .liveSavings: return "chart.bar.xaxis"
        case .minimalMonochrome: return "circle.inset.filled"
        }
    }
}

// MARK: - Completion Sound Theme (Supporter Customization)
public enum SoundEffectTheme: String, Codable, Sendable, CaseIterable {
    case defaultGlass = "Crystal Glass (Default)"
    case arcade8Bit = "8-Bit Arcade"
    case bubblePop = "Bubble Pop"
    case hydraulicPress = "Hydraulic Squeeze"
    case sciFiWarp = "Sci-Fi Warp"
    case heroFanfare = "Hero Fanfare"
    
    public var icon: String {
        switch self {
        case .defaultGlass: return "sparkles"
        case .arcade8Bit: return "gamecontroller.fill"
        case .bubblePop: return "drop.fill"
        case .hydraulicPress: return "wrench.and.screwdriver.fill"
        case .sciFiWarp: return "bolt.horizontal.fill"
        case .heroFanfare: return "horn.fill"
        }
    }
    
    public var systemSoundName: String {
        switch self {
        case .defaultGlass: return "Glass"
        case .arcade8Bit: return "Ping"
        case .bubblePop: return "Pop"
        case .hydraulicPress: return "Blow"
        case .sciFiWarp: return "Submarine"
        case .heroFanfare: return "Hero"
        }
    }
}

// MARK: - Media Type Classification
public enum MediaType: String, Codable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case pdf
    case unsupported
    
    public static func classify(url: URL) -> MediaType {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) {
                return .image
            } else if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            } else if type.conforms(to: .audio) {
                return .audio
            } else if type.conforms(to: .pdf) {
                return .pdf
            }
        }
        
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "bmp", "gif", "avif"]
        let videoExtensions = ["mov", "mp4", "m4v", "mkv", "webm", "avi", "wmv", "flv", "ts"]
        let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "aif", "caf", "alac", "ogg"]
        
        if imageExtensions.contains(ext) {
            return .image
        } else if videoExtensions.contains(ext) {
            return .video
        } else if audioExtensions.contains(ext) {
            return .audio
        } else if ext == "pdf" {
            return .pdf
        }
        
        return .unsupported
    }
}

// MARK: - PDF DPI Option
public enum PDFDPIOption: String, Codable, Sendable, CaseIterable {
    case dpi72 = "72 DPI (Compact)"
    case dpi150 = "150 DPI (Screen)"
    case dpi200 = "200 DPI (Standard)"
    case dpi300 = "300 DPI (Print)"
    
    public var dpiValue: CGFloat {
        switch self {
        case .dpi72: return 72.0
        case .dpi150: return 150.0
        case .dpi200: return 200.0
        case .dpi300: return 300.0
        }
    }
}

// MARK: - Image Format Policy
public enum ImageFormatPolicy: String, Codable, Sendable, CaseIterable {
    case preserveOriginal = "Preserve Original"
    case heicModern = "Modern HEIC"
    case webpModern = "Modern WebP"
    case avifModern = "Modern AVIF"
    case jpegStandard = "Web JPEG"
    
    public var description: String {
        switch self {
        case .preserveOriginal:
            return "Keep original format with resolution and quality optimization"
        case .heicModern:
            return "Hardware-accelerated Apple HEIC encoding (up to 90% size reduction)"
        case .webpModern:
            return "Modern WebP encoding for lightweight web deployment"
        case .avifModern:
            return "Next-generation AVIF encoding with high visual compression"
        case .jpegStandard:
            return "Standard JPEG format for universal web compatibility"
        }
    }
}

// MARK: - Audio Bitrate Preference
public enum AudioBitratePreference: String, Codable, Sendable, CaseIterable {
    case k16 = "16 kbps (Crushed Meme)"
    case k32 = "32 kbps (Lo-Fi Radio)"
    case k64 = "64 kbps (Voice)"
    case k128 = "128 kbps (Standard)"
    case k192 = "192 kbps (High)"
    case k256 = "256 kbps (Studio)"
    case k320 = "320 kbps (Max)"
    
    public var bitrateInBps: Int {
        switch self {
        case .k16: return 16_000
        case .k32: return 32_000
        case .k64: return 64_000
        case .k128: return 128_000
        case .k192: return 192_000
        case .k256: return 256_000
        case .k320: return 320_000
        }
    }
}

// MARK: - Video Codec Preference
public enum VideoCodecPreference: String, Codable, Sendable, CaseIterable {
    case hevc = "HEVC / H.265"
    case h264 = "H.264 / AVC"
    case gif = "Animated GIF"
    
    public var description: String {
        switch self {
        case .hevc:
            return "Apple Silicon Media Engine Hardware HEVC (high efficiency)"
        case .h264:
            return "Hardware H.264 video encoding (broadest device compatibility)"
        case .gif:
            return "Optimized animated GIF with looping for chat and web sharing"
        }
    }
    
    public var avCodecType: AVVideoCodecType {
        switch self {
        case .hevc: return .hevc
        case .h264: return .h264
        case .gif: return .hevc
        }
    }
}

// MARK: - Video Framerate Options
public enum VideoFramerateOption: String, Codable, Sendable, CaseIterable {
    case original = "Original"
    case fps60 = "60 FPS"
    case fps50 = "50 FPS"
    case fps30 = "30 FPS"
    case fps25 = "25 FPS"
    case fps24 = "24 FPS"
    case fps15 = "15 FPS"
    case fps12 = "12 FPS"
    
    public var targetFPS: Double? {
        switch self {
        case .original: return nil
        case .fps60: return 60.0
        case .fps50: return 50.0
        case .fps30: return 30.0
        case .fps25: return 25.0
        case .fps24: return 24.0
        case .fps15: return 15.0
        case .fps12: return 12.0
        }
    }
}

// MARK: - GIF Framerate Options
public enum GIFFramerateOption: String, Codable, Sendable, CaseIterable {
    case full = "Full FPS"
    case smooth24 = "24 FPS"
    case half15 = "15 FPS (Half)"
    case compact10 = "10 FPS"
    
    public var maxFPS: Double? {
        switch self {
        case .full: return nil
        case .smooth24: return 24.0
        case .half15: return 15.0
        case .compact10: return 10.0
        }
    }
}

// MARK: - Legacy Format Conversion Policy (for compatibility)
public enum FormatPolicy: String, Codable, Sendable, CaseIterable {
    case preserveOriginal = "Preserve Original"
    case modernOptimized = "Modern (WebP / HEVC)"
    
    public var description: String {
        switch self {
        case .preserveOriginal:
            return "Keep same extension & container"
        case .modernOptimized:
            return "Auto-convert images to HEIC and videos to HEVC/MP4"
        }
    }
}

// MARK: - Quality Preset
public enum QualityPreset: String, Codable, Sendable, CaseIterable {
    case maxCompression = "Max Compression"
    case balanced = "Balanced"
    case visuallyLossless = "Visually Lossless"
    
    public var normalizedQuality: Double {
        switch self {
        case .maxCompression: return 0.50
        case .balanced: return 0.75
        case .visuallyLossless: return 0.90
        }
    }
    
    public var videoCRF: Double {
        switch self {
        case .maxCompression: return 30.0
        case .balanced: return 26.0
        case .visuallyLossless: return 20.0
        }
    }
}

// MARK: - Compression Project / Folder Model
public struct CompressionFolder: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var isCollapsed: Bool
    public var colorHex: String?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        isCollapsed: Bool = false,
        colorHex: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isCollapsed = isCollapsed
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

// MARK: - Compression Result
public struct CompressionResult: Identifiable, Codable, Sendable {
    public let id: UUID
    public let originalURL: URL
    public var outputURL: URL
    public let originalSize: Int64
    public let compressedSize: Int64
    public let duration: TimeInterval
    public let mediaType: MediaType
    public let timestamp: Date
    public let originalDimensions: String?
    public let outputDimensions: String?
    public var folderId: UUID?
    
    public init(
        id: UUID = UUID(),
        originalURL: URL,
        outputURL: URL,
        originalSize: Int64,
        compressedSize: Int64,
        duration: TimeInterval,
        mediaType: MediaType,
        timestamp: Date = Date(),
        originalDimensions: String? = nil,
        outputDimensions: String? = nil,
        folderId: UUID? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.compressedSize = compressedSize
        self.duration = duration
        self.mediaType = mediaType
        self.timestamp = timestamp
        self.originalDimensions = originalDimensions
        self.outputDimensions = outputDimensions
        self.folderId = folderId
    }
    
    public var bytesSaved: Int64 {
        max(0, originalSize - compressedSize)
    }
    
    public var percentSaved: Double {
        guard originalSize > 0 else { return 0.0 }
        let diff = Double(originalSize - compressedSize)
        return max(0.0, (diff / Double(originalSize)) * 100.0)
    }
    
    public var fileName: String {
        originalURL.lastPathComponent
    }
    
    public var outputFileName: String {
        outputURL.lastPathComponent
    }
    
    public var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }
    
    public var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }
    
    public var formattedSaved: String {
        ByteCountFormatter.string(fromByteCount: bytesSaved, countStyle: .file)
    }
}

// MARK: - Job Item
public struct CompressionJob: Identifiable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let mediaType: MediaType
    public var progress: Double
    public var statusText: String
    public var isFinished: Bool
    public var error: String?
    
    public init(
        id: UUID = UUID(),
        fileURL: URL,
        mediaType: MediaType,
        progress: Double = 0.0,
        statusText: String = "Queued",
        isFinished: Bool = false,
        error: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.mediaType = mediaType
        self.progress = progress
        self.statusText = statusText
        self.isFinished = isFinished
        self.error = error
    }
}

// MARK: - Target Size Automation Mode
public enum TargetSizeMode: String, Codable, Sendable, CaseIterable {
    case off = "Manual Mode"
    case discord50 = "50 MB (Nitro / Slack)"
    case discord25 = "25 MB (Discord)"
    case email10 = "10 MB (Email)"
    case web2 = "2 MB (Fast Web)"
    case custom = "Custom MB Limit"
    
    public var targetMegabytes: Double? {
        switch self {
        case .off: return nil
        case .discord50: return 50.0
        case .discord25: return 25.0
        case .email10: return 10.0
        case .web2: return 2.0
        case .custom: return nil
        }
    }
}

// MARK: - Comprehensive Compression Configuration
public struct CompressionConfiguration: Sendable {
    public var imageQuality: Double
    public var imageResolutionScale: Double
    public var imageFormatPolicy: ImageFormatPolicy
    public var videoQuality: Double
    public var videoResolutionScale: Double
    public var videoCodec: VideoCodecPreference
    public var videoFramerate: VideoFramerateOption
    public var videoRemoveAudio: Bool
    public var gifFramerate: GIFFramerateOption
    public var audioBitrate: AudioBitratePreference
    public var pdfDPI: PDFDPIOption
    public var pdfImageQuality: Double
    public var pdfGrayscale: Bool
    public var pdfStripMetadata: Bool
    public var targetSizeMode: TargetSizeMode
    public var customTargetSizeMB: Double
    public var preserveResolutionInTargetMode: Bool
    public var preserveAudioQualityInTargetMode: Bool
    public var suffix: String
    public var customOutputFolder: String?
    public var exportToSubfolder: Bool
    public var subfolderName: String
    public var stripMetadata: Bool
    
    public var effectiveTargetSizeMB: Double? {
        if targetSizeMode == .off {
            return nil
        }
        return targetSizeMode.targetMegabytes ?? customTargetSizeMB
    }
    
    // Legacy support initializer
    public init(
        formatPolicy: FormatPolicy = .preserveOriginal,
        qualityPreset: QualityPreset = .visuallyLossless,
        customQuality: Double = 0.85,
        suffix: String = "_min",
        customOutputFolder: String? = nil,
        exportToSubfolder: Bool = false,
        subfolderName: String = "Squeezed",
        stripMetadata: Bool = false
    ) {
        self.imageQuality = customQuality
        self.imageResolutionScale = 1.0
        self.imageFormatPolicy = (formatPolicy == .modernOptimized) ? .heicModern : .preserveOriginal
        self.videoQuality = customQuality
        self.videoResolutionScale = 1.0
        self.videoCodec = (formatPolicy == .modernOptimized) ? .hevc : .hevc
        self.videoFramerate = .original
        self.videoRemoveAudio = false
        self.gifFramerate = .half15
        self.audioBitrate = .k128
        self.pdfDPI = .dpi150
        self.pdfImageQuality = 0.70
        self.pdfGrayscale = false
        self.pdfStripMetadata = true
        self.targetSizeMode = .off
        self.customTargetSizeMB = 25.0
        self.preserveResolutionInTargetMode = false
        self.preserveAudioQualityInTargetMode = false
        self.suffix = suffix
        self.customOutputFolder = customOutputFolder
        self.exportToSubfolder = exportToSubfolder
        self.subfolderName = subfolderName
        self.stripMetadata = stripMetadata
    }
    
    public init(
        imageQuality: Double = 0.85,
        imageResolutionScale: Double = 1.0,
        imageFormatPolicy: ImageFormatPolicy = .preserveOriginal,
        videoQuality: Double = 0.80,
        videoResolutionScale: Double = 1.0,
        videoCodec: VideoCodecPreference = .hevc,
        videoFramerate: VideoFramerateOption = .original,
        videoRemoveAudio: Bool = false,
        gifFramerate: GIFFramerateOption = .half15,
        audioBitrate: AudioBitratePreference = .k128,
        pdfDPI: PDFDPIOption = .dpi150,
        pdfImageQuality: Double = 0.70,
        pdfGrayscale: Bool = false,
        pdfStripMetadata: Bool = true,
        targetSizeMode: TargetSizeMode = .off,
        customTargetSizeMB: Double = 25.0,
        preserveResolutionInTargetMode: Bool = false,
        preserveAudioQualityInTargetMode: Bool = false,
        suffix: String = "_min",
        customOutputFolder: String? = nil,
        exportToSubfolder: Bool = false,
        subfolderName: String = "Squeezed",
        stripMetadata: Bool = false
    ) {
        self.imageQuality = imageQuality
        self.imageResolutionScale = imageResolutionScale
        self.imageFormatPolicy = imageFormatPolicy
        self.videoQuality = videoQuality
        self.videoResolutionScale = videoResolutionScale
        self.videoCodec = videoCodec
        self.videoFramerate = videoFramerate
        self.videoRemoveAudio = videoRemoveAudio
        self.gifFramerate = gifFramerate
        self.audioBitrate = audioBitrate
        self.pdfDPI = pdfDPI
        self.pdfImageQuality = pdfImageQuality
        self.pdfGrayscale = pdfGrayscale
        self.pdfStripMetadata = pdfStripMetadata
        self.targetSizeMode = targetSizeMode
        self.customTargetSizeMB = customTargetSizeMB
        self.preserveResolutionInTargetMode = preserveResolutionInTargetMode
        self.preserveAudioQualityInTargetMode = preserveAudioQualityInTargetMode
        self.suffix = suffix
        self.customOutputFolder = customOutputFolder
        self.exportToSubfolder = exportToSubfolder
        self.subfolderName = subfolderName
        self.stripMetadata = stripMetadata
    }
    
    // Convenience property for legacy call sites
    public var formatPolicy: FormatPolicy {
        return imageFormatPolicy == .preserveOriginal ? .preserveOriginal : .modernOptimized
    }
    
    public var customQuality: Double {
        return imageQuality
    }
}
