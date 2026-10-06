import Foundation

// User-facing names for the enums below. The raw values are persisted in UserDefaults and must never change,
// so the translatable text lives here instead. Each literal is picked up by the string catalog.
extension UIScaleOption {
    public var displayName: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }
}

extension AccentColorTheme {
    public var displayName: String {
        switch self {
        case .custom: return String(localized: "Custom")
        case .blue: return String(localized: "Blue")
        case .purple: return String(localized: "Purple")
        case .pink: return String(localized: "Pink")
        case .red: return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .graphite: return String(localized: "Graphite")
        }
    }
}

extension SoundEffectTheme {
    public var displayName: String {
        switch self {
        case .defaultGlass: return String(localized: "Crystal Glass (Default)")
        case .arcade8Bit: return String(localized: "8-Bit Arcade")
        case .bubblePop: return String(localized: "Bubble Pop")
        case .hydraulicPress: return String(localized: "Hydraulic Squeeze")
        case .sciFiWarp: return String(localized: "Sci-Fi Warp")
        case .heroFanfare: return String(localized: "Hero Fanfare")
        }
    }
}

extension PDFDPIOption {
    public var displayName: String {
        switch self {
        case .dpi72: return String(localized: "72 DPI (Compact)")
        case .dpi150: return String(localized: "150 DPI (Screen)")
        case .dpi200: return String(localized: "200 DPI (Standard)")
        case .dpi300: return String(localized: "300 DPI (Print)")
        }
    }
}

extension ImageFormatPolicy {
    public var displayName: String {
        switch self {
        case .preserveOriginal: return String(localized: "Preserve Original")
        case .heicModern: return String(localized: "Modern HEIC")
        case .webpModern: return String(localized: "Modern WebP")
        case .avifModern: return String(localized: "Modern AVIF")
        case .pngLossless: return String(localized: "PNG")
        case .jpegStandard: return String(localized: "Web JPEG")
        }
    }
}

extension AudioBitratePreference {
    public var displayName: String {
        switch self {
        case .k16: return String(localized: "16 kbps (Crushed Meme)")
        case .k32: return String(localized: "32 kbps (Lo-Fi Radio)")
        case .k64: return String(localized: "64 kbps (Voice)")
        case .k128: return String(localized: "128 kbps (Standard)")
        case .k192: return String(localized: "192 kbps (High)")
        case .k256: return String(localized: "256 kbps (Studio)")
        case .k320: return String(localized: "320 kbps (Max)")
        }
    }
}

extension VideoCodecPreference {
    public var displayName: String {
        switch self {
        case .hevc: return String(localized: "HEVC / H.265")
        case .h264: return String(localized: "H.264 / AVC")
        case .gif: return String(localized: "Animated GIF")
        }
    }
}

extension VideoFramerateOption {
    public var displayName: String {
        switch self {
        case .original: return String(localized: "Original")
        case .fps60: return String(localized: "60 FPS")
        case .fps50: return String(localized: "50 FPS")
        case .fps30: return String(localized: "30 FPS")
        case .fps25: return String(localized: "25 FPS")
        case .fps24: return String(localized: "24 FPS")
        case .fps15: return String(localized: "15 FPS")
        case .fps12: return String(localized: "12 FPS")
        }
    }
}

extension GIFFramerateOption {
    public var displayName: String {
        switch self {
        case .full: return String(localized: "Full FPS")
        case .smooth24: return String(localized: "24 FPS")
        case .half15: return String(localized: "15 FPS (Half)")
        case .compact10: return String(localized: "10 FPS")
        }
    }
}

extension QualityPreset {
    public var displayName: String {
        switch self {
        case .maxCompression: return String(localized: "Max Compression")
        case .balanced: return String(localized: "Balanced")
        case .visuallyLossless: return String(localized: "Visually Lossless")
        }
    }
}

extension TargetSizeMode {
    public var displayName: String {
        switch self {
        case .off: return String(localized: "Manual Mode")
        case .discord50: return String(localized: "50 MB (Nitro / Slack)")
        case .discord25: return String(localized: "25 MB (Discord)")
        case .email10: return String(localized: "10 MB (Email)")
        case .web2: return String(localized: "2 MB (Fast Web)")
        case .custom: return String(localized: "Custom MB Limit")
        }
    }
}

extension SoundEffectTheme {
    /// One-word label for the compact sound grid.
    public var shortName: String {
        switch self {
        case .defaultGlass: return String(localized: "Crystal")
        case .arcade8Bit: return String(localized: "8-Bit")
        case .bubblePop: return String(localized: "Bubble")
        case .hydraulicPress: return String(localized: "Hydraulic")
        case .sciFiWarp: return String(localized: "Sci-Fi")
        case .heroFanfare: return String(localized: "Hero")
        }
    }
}

extension AudioBitratePreference {
    /// Bitrate without the descriptive suffix, for compact pills.
    public var shortName: String {
        switch self {
        case .k16: return String(localized: "16 kbps")
        case .k32: return String(localized: "32 kbps")
        case .k64: return String(localized: "64 kbps")
        case .k128: return String(localized: "128 kbps")
        case .k192: return String(localized: "192 kbps")
        case .k256: return String(localized: "256 kbps")
        case .k320: return String(localized: "320 kbps")
        }
    }
}

extension ImageFormatPolicy {
    /// Format name for pills; the long name is used when the pill is selected.
    public var shortName: String {
        switch self {
        case .preserveOriginal: return String(localized: "Orig.")
        case .heicModern: return "HEIC"
        case .webpModern: return "WebP"
        case .avifModern: return "AVIF"
        case .pngLossless: return "PNG"
        case .jpegStandard: return "JPEG"
        }
    }

    public var selectedName: String {
        switch self {
        case .preserveOriginal, .jpegStandard: return displayName
        default: return shortName
        }
    }
}

extension VideoFramerateOption {
    public var shortName: String {
        switch self {
        case .original: return String(localized: "Orig.")
        case .fps60: return "60"
        case .fps50: return "50"
        case .fps30: return "30"
        case .fps25: return "25"
        case .fps24: return "24"
        case .fps15: return "15"
        case .fps12: return "12"
        }
    }
}
