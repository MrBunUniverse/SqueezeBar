import Foundation
import SwiftUI
import Combine
import AppKit
import ServiceManagement

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // MARK: - Folders & Project Organization
    @Published public var customFolders: [CompressionFolder] = [] {
        didSet {
            saveFolders()
        }
    }
    
    // MARK: - User Settings Keys
    private enum Keys {
        static let customFolders = "squeezebar.customFolders"
        static let imageFormatPolicy = "squeezebar.imageFormatPolicy"
        static let imageQualityPreset = "squeezebar.imageQualityPreset"
        static let imageQualitySlider = "squeezebar.imageQualitySlider"
        static let imageResolutionScale = "squeezebar.imageResolutionScale"
        
        static let videoCodec = "squeezebar.videoCodec"
        static let videoFramerate = "squeezebar.videoFramerate"
        static let videoQualityPreset = "squeezebar.videoQualityPreset"
        static let videoQualitySlider = "squeezebar.videoQualitySlider"
        static let videoResolutionScale = "squeezebar.videoResolutionScale"
        static let videoRemoveAudio = "squeezebar.videoRemoveAudio"
        static let gifFramerate = "squeezebar.gifFramerate"
        
        static let audioBitrate = "squeezebar.audioBitrate"
        
        static let pdfDPI = "squeezebar.pdfDPI"
        static let pdfImageQuality = "squeezebar.pdfImageQuality"
        static let pdfGrayscale = "squeezebar.pdfGrayscale"
        static let pdfStripMetadata = "squeezebar.pdfStripMetadata"
        
        static let targetSizeMode = "squeezebar.targetSizeMode"
        static let customTargetSizeMB = "squeezebar.customTargetSizeMB"
        static let preserveResolutionInTargetMode = "squeezebar.preserveResolutionInTargetMode"
        static let preserveAudioQualityInTargetMode = "squeezebar.preserveAudioQualityInTargetMode"
        
        static let watchFolderPath = "squeezebar.watchFolderPath"
        static let isWatchFolderEnabled = "squeezebar.isWatchFolderEnabled"
        
        static let outputSuffix = "squeezebar.outputSuffix"
        static let stripMetadata = "squeezebar.stripMetadata"
        static let hapticEnabled = "squeezebar.hapticEnabled"
        static let soundEnabled = "squeezebar.soundEnabled"
        static let historyList = "squeezebar.historyList"
        static let totalBytesSaved = "squeezebar.totalBytesSaved"
        static let totalOriginalBytes = "squeezebar.totalOriginalBytes"
        static let totalFilesProcessed = "squeezebar.totalFilesProcessed"
        static let accentTheme = "squeezebar.accentTheme"
        static let customAccentHex = "squeezebar.customAccentHex"
        static let isProUser = "squeezebar.isProUser"
        static let customOutputFolder = "squeezebar.customOutputFolder"
        static let exportToSubfolder = "squeezebar.exportToSubfolder"
        static let subfolderName = "squeezebar.subfolderName"
        static let finderServiceEnabled = "squeezebar.finderServiceEnabled"
        static let menuBarDisplayStyle = "squeezebar.menuBarDisplayStyle"
        static let soundTheme = "squeezebar.soundTheme"
        static let uiScale = "squeezebar.uiScale"
        static let floatingBallEnabled = "squeezebar.floatingBallEnabled"
        static let dropBallAnimationStyle = "squeezebar.dropBallAnimationStyle"
        static let dropBallGlassStyle = "squeezebar.dropBallGlassStyle"
        static let dropBallFrost = "squeezebar.dropBallFrost"
        static let dropBallClarity = "squeezebar.dropBallClarity"
        static let dropBallDepth = "squeezebar.dropBallDepth"
        static let dropBallSheen = "squeezebar.dropBallSheen"
        static let dropBallRim = "squeezebar.dropBallRim"
    }
    
    // MARK: - Desktop Floating Drop Ball
    @Published public var floatingBallEnabled: Bool {
        didSet {
            UserDefaults.standard.set(floatingBallEnabled, forKey: Keys.floatingBallEnabled)
            DispatchQueue.main.async {
                FloatingBallController.shared.updateVisibility()
            }
        }
    }
    
    // MARK: - DropBall Animation Style (Calm / Standard / Exaggerated)
    @Published public var dropBallAnimationStyle: DropBallAnimationStyle {
        didSet {
            UserDefaults.standard.set(dropBallAnimationStyle.rawValue, forKey: Keys.dropBallAnimationStyle)
        }
    }
    
    // MARK: - DropBall Glass Style Template (Crystal Clear / Balanced / High Contrast)
    @Published public var dropBallGlassStyle: DropBallGlassStyle {
        didSet {
            UserDefaults.standard.set(dropBallGlassStyle.rawValue, forKey: Keys.dropBallGlassStyle)
            self.dropBallClarity = dropBallGlassStyle.clarity
            self.dropBallFrost = dropBallGlassStyle.frost
            self.dropBallDepth = dropBallGlassStyle.depth
            self.dropBallSheen = dropBallGlassStyle.sheen
            self.dropBallRim = dropBallGlassStyle.rim
        }
    }
    
    // MARK: - DropBall Liquid Glass Shaders Configuration
    @Published public var dropBallClarity: Double {
        didSet { UserDefaults.standard.set(dropBallClarity, forKey: Keys.dropBallClarity) }
    }
    @Published public var dropBallFrost: Double {
        didSet { UserDefaults.standard.set(dropBallFrost, forKey: Keys.dropBallFrost) }
    }
    @Published public var dropBallDepth: Double {
        didSet { UserDefaults.standard.set(dropBallDepth, forKey: Keys.dropBallDepth) }
    }
    @Published public var dropBallSheen: Double {
        didSet { UserDefaults.standard.set(dropBallSheen, forKey: Keys.dropBallSheen) }
    }
    @Published public var dropBallRim: Double {
        didSet { UserDefaults.standard.set(dropBallRim, forKey: Keys.dropBallRim) }
    }
    
    public func resetDropBallShadersToDefault() {
        dropBallGlassStyle = .superClear
    }
    
    // MARK: - UI Scaling / Display Density Option
    @Published public var uiScale: UIScaleOption {
        didSet {
            UserDefaults.standard.set(uiScale.rawValue, forKey: Keys.uiScale)
            DispatchQueue.main.async {
                StatusBarController.sharedInstance?.updatePopoverDimensionsForScale(self.uiScale)
                FloatingDropWindowController.shared.updateWindowDimensionsForScale(self.uiScale)
            }
        }
    }
    
    // MARK: - Pro / Basic Tier State
    @Published public var isProUser: Bool {
        didSet {
            UserDefaults.standard.set(isProUser, forKey: Keys.isProUser)
        }
    }
    
    // MARK: - Menu Bar Display Style (Supporter Perk)
    @Published public var menuBarDisplayStyle: MenuBarDisplayStyle {
        didSet {
            UserDefaults.standard.set(menuBarDisplayStyle.rawValue, forKey: Keys.menuBarDisplayStyle)
        }
    }
    
    // MARK: - Completion Sound Theme (Supporter Perk)
    @Published public var soundTheme: SoundEffectTheme {
        didSet {
            UserDefaults.standard.set(soundTheme.rawValue, forKey: Keys.soundTheme)
        }
    }
    
    // MARK: - Appearance & Accent Color Theme
    @Published public var accentTheme: AccentColorTheme {
        didSet {
            UserDefaults.standard.set(accentTheme.rawValue, forKey: Keys.accentTheme)
        }
    }
    
    @Published public var customAccentHex: String {
        didSet {
            UserDefaults.standard.set(customAccentHex, forKey: Keys.customAccentHex)
        }
    }
    
    public var accentColor: Color {
        switch accentTheme {
        case .custom:
            return AppState.colorFromHex(customAccentHex) ?? Color(red: 0.1, green: 0.5, blue: 1.0)
        case .blue:
            return Color.blue
        case .purple:
            return Color(red: 0.65, green: 0.32, blue: 0.88)
        case .pink:
            return Color(red: 0.98, green: 0.32, blue: 0.58)
        case .red:
            return Color(red: 0.95, green: 0.28, blue: 0.28)
        case .orange:
            return Color(red: 0.98, green: 0.55, blue: 0.18)
        case .yellow:
            return Color(red: 0.98, green: 0.78, blue: 0.12)
        case .green:
            return Color(red: 0.32, green: 0.82, blue: 0.42)
        case .graphite:
            return Color(red: 0.58, green: 0.60, blue: 0.64)
        }
    }
    
    /// Text color to display ON TOP of the accent color (e.g. inside active pills/buttons)
    /// Automatically switches to deep black/dark charcoal on light/white/yellow accents, and pure white on dark accents.
    public var contrastTextColor: Color {
        let nsColor = NSColor(accentColor).usingColorSpace(.sRGB) ?? NSColor.blue
        // WCAG relative luminance formula
        let luminance = 0.2126 * nsColor.redComponent + 0.7152 * nsColor.greenComponent + 0.0722 * nsColor.blueComponent
        return luminance > 0.55 ? Color(white: 0.10) : Color.white
    }
    
    public static func colorFromHex(_ hex: String) -> Color? {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else {
            return nil
        }
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    public static func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.blue
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
    
    // MARK: - Image Settings
    @Published public var imageFormatPolicy: ImageFormatPolicy {
        didSet {
            UserDefaults.standard.set(imageFormatPolicy.rawValue, forKey: Keys.imageFormatPolicy)
        }
    }
    
    @Published public var imageQualityPreset: QualityPreset {
        didSet {
            UserDefaults.standard.set(imageQualityPreset.rawValue, forKey: Keys.imageQualityPreset)
            imageQualitySlider = imageQualityPreset.normalizedQuality
        }
    }
    
    @Published public var imageQualitySlider: Double {
        didSet {
            UserDefaults.standard.set(imageQualitySlider, forKey: Keys.imageQualitySlider)
        }
    }
    
    @Published public var imageResolutionScale: Double {
        didSet {
            UserDefaults.standard.set(imageResolutionScale, forKey: Keys.imageResolutionScale)
        }
    }
    
    // MARK: - Video Settings
    @Published public var videoCodec: VideoCodecPreference {
        didSet {
            UserDefaults.standard.set(videoCodec.rawValue, forKey: Keys.videoCodec)
        }
    }
    
    @Published public var videoFramerate: VideoFramerateOption {
        didSet {
            UserDefaults.standard.set(videoFramerate.rawValue, forKey: Keys.videoFramerate)
        }
    }
    
    @Published public var videoQualityPreset: QualityPreset {
        didSet {
            UserDefaults.standard.set(videoQualityPreset.rawValue, forKey: Keys.videoQualityPreset)
            videoQualitySlider = videoQualityPreset.normalizedQuality
        }
    }
    
    @Published public var videoQualitySlider: Double {
        didSet {
            UserDefaults.standard.set(videoQualitySlider, forKey: Keys.videoQualitySlider)
        }
    }
    
    @Published public var videoResolutionScale: Double {
        didSet {
            UserDefaults.standard.set(videoResolutionScale, forKey: Keys.videoResolutionScale)
        }
    }
    
    @Published public var videoRemoveAudio: Bool {
        didSet {
            UserDefaults.standard.set(videoRemoveAudio, forKey: Keys.videoRemoveAudio)
        }
    }
    
    @Published public var gifFramerate: GIFFramerateOption {
        didSet {
            UserDefaults.standard.set(gifFramerate.rawValue, forKey: Keys.gifFramerate)
        }
    }
    
    // MARK: - Audio Settings
    @Published public var audioBitrate: AudioBitratePreference {
        didSet {
            UserDefaults.standard.set(audioBitrate.rawValue, forKey: Keys.audioBitrate)
        }
    }
    
    // MARK: - PDF Settings
    @Published public var pdfDPI: PDFDPIOption {
        didSet {
            UserDefaults.standard.set(pdfDPI.rawValue, forKey: Keys.pdfDPI)
        }
    }
    
    @Published public var pdfImageQuality: Double {
        didSet {
            UserDefaults.standard.set(pdfImageQuality, forKey: Keys.pdfImageQuality)
        }
    }
    
    @Published public var pdfGrayscale: Bool {
        didSet {
            UserDefaults.standard.set(pdfGrayscale, forKey: Keys.pdfGrayscale)
        }
    }
    
    @Published public var pdfStripMetadata: Bool {
        didSet {
            UserDefaults.standard.set(pdfStripMetadata, forKey: Keys.pdfStripMetadata)
        }
    }
    
    // MARK: - Watch Folder Settings
    @Published public var watchFolderPath: String? {
        didSet {
            UserDefaults.standard.set(watchFolderPath, forKey: Keys.watchFolderPath)
        }
    }
    
    @Published public var isWatchFolderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWatchFolderEnabled, forKey: Keys.isWatchFolderEnabled)
        }
    }
    
    // MARK: - Automation & Target Size
    @Published public var targetSizeMode: TargetSizeMode {
        didSet {
            UserDefaults.standard.set(targetSizeMode.rawValue, forKey: Keys.targetSizeMode)
            applyTargetSizePreset(targetSizeMode)
        }
    }
    
    @Published public var customTargetSizeMB: Double {
        didSet {
            UserDefaults.standard.set(customTargetSizeMB, forKey: Keys.customTargetSizeMB)
            if targetSizeMode == .custom {
                applyCustomTargetSize(customTargetSizeMB)
            }
        }
    }
    
    @Published public var preserveResolutionInTargetMode: Bool {
        didSet {
            UserDefaults.standard.set(preserveResolutionInTargetMode, forKey: Keys.preserveResolutionInTargetMode)
            if preserveResolutionInTargetMode {
                imageResolutionScale = 1.0
                videoResolutionScale = 1.0
            }
        }
    }
    
    @Published public var preserveAudioQualityInTargetMode: Bool {
        didSet {
            UserDefaults.standard.set(preserveAudioQualityInTargetMode, forKey: Keys.preserveAudioQualityInTargetMode)
        }
    }
    
    public func applyTargetSizePreset(_ mode: TargetSizeMode) {
        switch mode {
        case .web2:
            // 2 MB: Aggressive compression
            imageQualitySlider = 0.65
            videoQualitySlider = 0.50
            pdfDPI = .dpi72
            pdfImageQuality = 0.55
            if !preserveResolutionInTargetMode {
                imageResolutionScale = 0.75
                videoResolutionScale = 0.50
            }
        case .email10:
            // 10 MB: Balanced compression
            imageQualitySlider = 0.75
            videoQualitySlider = 0.65
            pdfDPI = .dpi150
            pdfImageQuality = 0.65
            if !preserveResolutionInTargetMode {
                imageResolutionScale = 0.85
                videoResolutionScale = 0.75
            }
        case .discord25:
            // 25 MB: High quality target
            imageQualitySlider = 0.85
            videoQualitySlider = 0.80
            pdfDPI = .dpi150
            pdfImageQuality = 0.75
            if !preserveResolutionInTargetMode {
                imageResolutionScale = 1.0
                videoResolutionScale = 1.0
            }
        case .discord50:
            // 50 MB: Visually lossless / large target
            imageQualitySlider = 0.90
            videoQualitySlider = 0.85
            pdfDPI = .dpi200
            pdfImageQuality = 0.85
            if !preserveResolutionInTargetMode {
                imageResolutionScale = 1.0
                videoResolutionScale = 1.0
            }
        case .custom:
            applyCustomTargetSize(customTargetSizeMB)
        case .off:
            // Manual: Keep current user settings
            break
        }
    }
    
    public func applyCustomTargetSize(_ mb: Double) {
        if mb <= 5.0 {
            imageQualitySlider = 0.60
            videoQualitySlider = 0.45
            if !preserveResolutionInTargetMode {
                imageResolutionScale = 0.50
                videoResolutionScale = 0.50
            }
        } else if mb <= 15.0 {
            imageQualitySlider = 0.75
            videoQualitySlider = 0.65
            if !preserveResolutionInTargetMode {
                imageResolutionScale = 0.75
                videoResolutionScale = 0.75
            }
        } else {
            imageQualitySlider = 0.85
            videoQualitySlider = 0.80
            if !preserveResolutionInTargetMode {
                imageResolutionScale = 1.0
                videoResolutionScale = 1.0
            }
        }
    }
    
    // MARK: - Staged Queue Management
    @Published public var stagedQueue: [StagedQueueItem] = []
    
    @MainActor
    public func addFilesToQueue(_ urls: [URL]) {
        let baseConfig = currentConfiguration()
        var addedCount = 0
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let resolved = MediaCompressionEngine.shared.gatherMediaFiles(from: [url])
                for subURL in resolved {
                    let mediaType = MediaType.classify(url: subURL)
                    guard mediaType != MediaType.unsupported else { continue }
                    let size = (try? subURL.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                    let item = StagedQueueItem(fileURL: subURL, originalSize: size, mediaType: mediaType, baseConfig: baseConfig)
                    stagedQueue.append(item)
                    addedCount += 1
                }
            } else {
                let mediaType = MediaType.classify(url: url)
                guard mediaType != MediaType.unsupported else { continue }
                let size = (try? url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                let item = StagedQueueItem(fileURL: url, originalSize: size, mediaType: mediaType, baseConfig: baseConfig)
                stagedQueue.append(item)
                addedCount += 1
            }
        }
        
        if addedCount > 0 && hapticEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
    
    @MainActor
    public func removeFromQueue(id: UUID) {
        stagedQueue.removeAll { $0.id == id }
    }
    
    @MainActor
    public func clearQueue() {
        stagedQueue.removeAll()
    }
    
    @MainActor
    public func squeezeStagedQueue(targetFolderId: UUID? = nil) {
        guard !stagedQueue.isEmpty else { return }
        let itemsToProcess = stagedQueue
        stagedQueue.removeAll()
        
        Task {
            await MediaCompressionEngine.shared.processStagedItems(itemsToProcess, targetFolderId: targetFolderId)
        }
    }
    
    // MARK: - General Settings
    @Published public var outputSuffix: String {
        didSet {
            UserDefaults.standard.set(outputSuffix, forKey: Keys.outputSuffix)
        }
    }
    
    @Published public var customOutputFolder: String? {
        didSet {
            UserDefaults.standard.set(customOutputFolder, forKey: Keys.customOutputFolder)
        }
    }
    
    @Published public var exportToSubfolder: Bool {
        didSet {
            UserDefaults.standard.set(exportToSubfolder, forKey: Keys.exportToSubfolder)
        }
    }
    
    @Published public var subfolderName: String {
        didSet {
            UserDefaults.standard.set(subfolderName, forKey: Keys.subfolderName)
        }
    }
    
    @Published public var stripMetadata: Bool {
        didSet {
            UserDefaults.standard.set(stripMetadata, forKey: Keys.stripMetadata)
        }
    }
    
    @Published public var hapticEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticEnabled, forKey: Keys.hapticEnabled)
        }
    }
    
    @Published public var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: Keys.soundEnabled)
        }
    }
    
    // MARK: - Finder Quick Action (Right-Click Context Menu)
    @Published public var finderServiceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(finderServiceEnabled, forKey: Keys.finderServiceEnabled)
        }
    }
    
    // MARK: - Launch at macOS Boot / Login
    @Published public var launchAtLogin: Bool = false
    
    public func updateLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
    
    public func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            } catch {
                print("Failed to update Launch at Login: \(error)")
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }
    
    @Published public var isPinned: Bool = false
    @Published public var isDetached: Bool = false
    @Published public var inspectedResult: CompressionResult? = nil
    @Published public var supporterBannerNotice: String? = nil
    
    // MARK: - Runtime State
    @Published public var isProcessing: Bool = false
    @Published public var overallProgress: Double = 0.0
    @Published public var activeJobs: [CompressionJob] = []
    @Published public var recentResults: [CompressionResult] = []
    @Published public var showSuccessBadge: Bool = false
    
    // MARK: - Cumulative Stats
    @Published public var totalBytesSaved: Int64
    @Published public var totalOriginalBytes: Int64
    @Published public var totalFilesProcessed: Int
    
    public var overallPercentageSaved: Double {
        guard totalOriginalBytes > 0 else { return 0.0 }
        return (Double(totalBytesSaved) / Double(totalOriginalBytes)) * 100.0
    }
    
    public var formattedTotalSaved: String {
        ByteCountFormatter.string(fromByteCount: totalBytesSaved, countStyle: .file)
    }
    
    // MARK: - Initialization
    private init() {
        // Load Image Settings
        let savedImgFormat = UserDefaults.standard.string(forKey: Keys.imageFormatPolicy) ?? ""
        self.imageFormatPolicy = ImageFormatPolicy(rawValue: savedImgFormat) ?? .preserveOriginal
        
        let savedImgPreset = UserDefaults.standard.string(forKey: Keys.imageQualityPreset) ?? ""
        self.imageQualityPreset = QualityPreset(rawValue: savedImgPreset) ?? .visuallyLossless
        
        let savedImgQuality = UserDefaults.standard.double(forKey: Keys.imageQualitySlider)
        self.imageQualitySlider = savedImgQuality > 0 ? savedImgQuality : 0.85
        
        let savedImgRes = UserDefaults.standard.double(forKey: Keys.imageResolutionScale)
        self.imageResolutionScale = savedImgRes > 0 ? savedImgRes : 1.0
        
        // Load Video Settings
        let savedVidCodec = UserDefaults.standard.string(forKey: Keys.videoCodec) ?? ""
        self.videoCodec = VideoCodecPreference(rawValue: savedVidCodec) ?? .hevc
        
        let savedVidFPS = UserDefaults.standard.string(forKey: Keys.videoFramerate) ?? ""
        self.videoFramerate = VideoFramerateOption(rawValue: savedVidFPS) ?? .original
        
        let savedVidPreset = UserDefaults.standard.string(forKey: Keys.videoQualityPreset) ?? ""
        self.videoQualityPreset = QualityPreset(rawValue: savedVidPreset) ?? .visuallyLossless
        
        let savedVidQuality = UserDefaults.standard.double(forKey: Keys.videoQualitySlider)
        self.videoQualitySlider = savedVidQuality > 0 ? savedVidQuality : 0.80
        
        let savedVidRes = UserDefaults.standard.double(forKey: Keys.videoResolutionScale)
        self.videoResolutionScale = savedVidRes > 0 ? savedVidRes : 1.0
        
        self.videoRemoveAudio = UserDefaults.standard.bool(forKey: Keys.videoRemoveAudio)
        
        let savedGIFFPS = UserDefaults.standard.string(forKey: Keys.gifFramerate) ?? ""
        self.gifFramerate = GIFFramerateOption(rawValue: savedGIFFPS) ?? .half15
        
        // Load Audio Settings
        let savedAudioBitrate = UserDefaults.standard.string(forKey: Keys.audioBitrate) ?? ""
        self.audioBitrate = AudioBitratePreference(rawValue: savedAudioBitrate) ?? .k128
        
        // Load PDF Settings
        let savedPDFDPI = UserDefaults.standard.string(forKey: Keys.pdfDPI) ?? ""
        self.pdfDPI = PDFDPIOption(rawValue: savedPDFDPI) ?? .dpi150
        
        let savedPDFQuality = UserDefaults.standard.double(forKey: Keys.pdfImageQuality)
        self.pdfImageQuality = savedPDFQuality > 0 ? savedPDFQuality : 0.70
        
        self.pdfGrayscale = UserDefaults.standard.bool(forKey: Keys.pdfGrayscale)
        self.pdfStripMetadata = UserDefaults.standard.object(forKey: Keys.pdfStripMetadata) as? Bool ?? true
        
        // Load Watch Folder Settings
        self.watchFolderPath = UserDefaults.standard.string(forKey: Keys.watchFolderPath)
        self.isWatchFolderEnabled = UserDefaults.standard.bool(forKey: Keys.isWatchFolderEnabled)
        
        // Load Automation & Target Size
        let savedTargetMode = UserDefaults.standard.string(forKey: Keys.targetSizeMode) ?? ""
        self.targetSizeMode = TargetSizeMode(rawValue: savedTargetMode) ?? .off
        
        let savedCustomSize = UserDefaults.standard.double(forKey: Keys.customTargetSizeMB)
        self.customTargetSizeMB = savedCustomSize > 0 ? savedCustomSize : 25.0
        
        self.preserveResolutionInTargetMode = UserDefaults.standard.bool(forKey: Keys.preserveResolutionInTargetMode)
        self.preserveAudioQualityInTargetMode = UserDefaults.standard.bool(forKey: Keys.preserveAudioQualityInTargetMode)
        
        // Load General Settings
        let savedTheme = UserDefaults.standard.string(forKey: Keys.accentTheme) ?? ""
        self.accentTheme = AccentColorTheme(rawValue: savedTheme) ?? .blue
        
        let savedBarStyle = UserDefaults.standard.string(forKey: Keys.menuBarDisplayStyle) ?? ""
        self.menuBarDisplayStyle = MenuBarDisplayStyle(rawValue: savedBarStyle) ?? .iconOnly
        
        let savedSoundTheme = UserDefaults.standard.string(forKey: Keys.soundTheme) ?? ""
        self.soundTheme = SoundEffectTheme(rawValue: savedSoundTheme) ?? .defaultGlass
        
        let savedCustomHex = UserDefaults.standard.string(forKey: Keys.customAccentHex) ?? ""
        self.customAccentHex = savedCustomHex.isEmpty ? "007AFF" : savedCustomHex
        
        self.outputSuffix = UserDefaults.standard.string(forKey: Keys.outputSuffix) ?? "_min"
        self.customOutputFolder = UserDefaults.standard.string(forKey: Keys.customOutputFolder)
        self.exportToSubfolder = UserDefaults.standard.bool(forKey: Keys.exportToSubfolder)
        self.subfolderName = UserDefaults.standard.string(forKey: Keys.subfolderName) ?? "Squeezed"
        self.finderServiceEnabled = UserDefaults.standard.object(forKey: Keys.finderServiceEnabled) as? Bool ?? true
        self.stripMetadata = UserDefaults.standard.object(forKey: Keys.stripMetadata) as? Bool ?? true     
        
        if UserDefaults.standard.object(forKey: Keys.floatingBallEnabled) == nil {
            self.floatingBallEnabled = true
        } else {
            self.floatingBallEnabled = UserDefaults.standard.bool(forKey: Keys.floatingBallEnabled)
        }
        
        if let rawStyle = UserDefaults.standard.string(forKey: Keys.dropBallAnimationStyle),
           let style = DropBallAnimationStyle(rawValue: rawStyle) {
            self.dropBallAnimationStyle = style
        } else {
            self.dropBallAnimationStyle = .exaggerated
        }
        
        let initialGlassStyle: DropBallGlassStyle
        if let rawGlassStyle = UserDefaults.standard.string(forKey: Keys.dropBallGlassStyle),
           let glassStyle = DropBallGlassStyle(rawValue: rawGlassStyle) {
            initialGlassStyle = glassStyle
        } else {
            initialGlassStyle = .superClear
        }
        self.dropBallGlassStyle = initialGlassStyle
        self.dropBallClarity = initialGlassStyle.clarity
        self.dropBallFrost = initialGlassStyle.frost
        self.dropBallDepth = initialGlassStyle.depth
        self.dropBallSheen = initialGlassStyle.sheen
        self.dropBallRim = initialGlassStyle.rim
        
        if let rawScale = UserDefaults.standard.string(forKey: Keys.uiScale),
           let scale = UIScaleOption(rawValue: rawScale) {
            self.uiScale = scale
        } else {
            self.uiScale = .medium
        }
        
        if UserDefaults.standard.object(forKey: Keys.hapticEnabled) == nil {
            self.hapticEnabled = true
        } else {
            self.hapticEnabled = UserDefaults.standard.bool(forKey: Keys.hapticEnabled)
        }
        
        if UserDefaults.standard.object(forKey: Keys.soundEnabled) == nil {
            self.soundEnabled = true
        } else {
            self.soundEnabled = UserDefaults.standard.bool(forKey: Keys.soundEnabled)
        }
        
        if UserDefaults.standard.object(forKey: Keys.isProUser) == nil {
            self.isProUser = true
        } else {
            self.isProUser = UserDefaults.standard.bool(forKey: Keys.isProUser)
        }
        
        self.totalBytesSaved = Int64(UserDefaults.standard.integer(forKey: Keys.totalBytesSaved))
        self.totalOriginalBytes = Int64(UserDefaults.standard.integer(forKey: Keys.totalOriginalBytes))
        self.totalFilesProcessed = UserDefaults.standard.integer(forKey: Keys.totalFilesProcessed)
        
        updateLaunchAtLoginStatus()
        loadFolders()
        loadHistory()
    }
    
    // MARK: - Folder & Project Management
    public func addFolder(name: String, icon: String = "folder.fill") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = CompressionFolder(name: trimmed, icon: icon)
        customFolders.append(folder)
    }
    
    public func renameFolder(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = customFolders.firstIndex(where: { $0.id == id }) {
            customFolders[idx].name = trimmed
        }
    }
    
    public func deleteFolder(id: UUID) {
        // Unassign all items in this folder
        for i in 0..<recentResults.count {
            if recentResults[i].folderId == id {
                recentResults[i].folderId = nil
            }
        }
        customFolders.removeAll { $0.id == id }
        saveHistory()
    }
    
    public func updateFolderColor(id: UUID, colorHex: String?) {
        if let idx = customFolders.firstIndex(where: { $0.id == id }) {
            customFolders[idx].colorHex = colorHex
        }
    }
    
    public func toggleFolderCollapse(id: UUID) {
        if let idx = customFolders.firstIndex(where: { $0.id == id }) {
            customFolders[idx].isCollapsed.toggle()
        }
    }
    
    public func assignResultsToFolder(resultIds: Set<UUID>, folderId: UUID?) {
        for i in 0..<recentResults.count {
            if resultIds.contains(recentResults[i].id) {
                recentResults[i].folderId = folderId
            }
        }
        saveHistory()
    }
    
    // MARK: - Batch Operations (Delete, Format Rename)
    public func batchDeleteResults(ids: Set<UUID>) {
        recentResults.removeAll { ids.contains($0.id) }
        saveHistory()
    }
    
    public func batchRenameResults(ids: Set<UUID>, pattern: String) {
        // Pattern format: e.g. "Homerenovation_#", "Project_{index}", or "CustomPrefix_#"
        // If pattern contains '#' or '{index}' or '{i}', replace with sequential index 1, 2, 3...
        var index = 1
        let fm = FileManager.default
        
        for i in 0..<recentResults.count {
            guard ids.contains(recentResults[i].id) else { continue }
            let originalItem = recentResults[i]
            let ext = originalItem.outputURL.pathExtension
            let directory = originalItem.outputURL.deletingLastPathComponent()
            
            var newBaseName = pattern
            if newBaseName.contains("#") {
                newBaseName = newBaseName.replacingOccurrences(of: "#", with: "\(index)")
            } else if newBaseName.contains("{index}") {
                newBaseName = newBaseName.replacingOccurrences(of: "{index}", with: "\(index)")
            } else if newBaseName.contains("{i}") {
                newBaseName = newBaseName.replacingOccurrences(of: "{i}", with: "\(index)")
            } else if ids.count > 1 {
                // If no token was provided but multiple files selected, append _#
                newBaseName = "\(newBaseName)_\(index)"
            }
            
            let finalName = ext.isEmpty ? newBaseName : "\(newBaseName).\(ext)"
            let targetURL = directory.appendingPathComponent(finalName)
            
            // Perform file system rename if file exists
            if fm.fileExists(atPath: originalItem.outputURL.path) && originalItem.outputURL.path != targetURL.path {
                try? fm.moveItem(at: originalItem.outputURL, to: targetURL)
                recentResults[i].outputURL = targetURL
            }
            
            index += 1
        }
        saveHistory()
    }
    
    private func saveFolders() {
        if let data = try? JSONEncoder().encode(customFolders) {
            UserDefaults.standard.set(data, forKey: Keys.customFolders)
        }
    }
    
    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: Keys.customFolders),
           let list = try? JSONDecoder().decode([CompressionFolder].self, from: data) {
            self.customFolders = list
        }
    }
    
    // MARK: - Configuration Getter
    public func currentConfiguration() -> CompressionConfiguration {
        CompressionConfiguration(
            imageQuality: imageQualitySlider,
            imageResolutionScale: imageResolutionScale,
            imageFormatPolicy: imageFormatPolicy,
            videoQuality: videoQualitySlider,
            videoResolutionScale: videoResolutionScale,
            videoCodec: videoCodec,
            videoFramerate: videoFramerate,
            videoRemoveAudio: videoRemoveAudio,
            gifFramerate: gifFramerate,
            audioBitrate: audioBitrate,
            pdfDPI: pdfDPI,
            pdfImageQuality: pdfImageQuality,
            pdfGrayscale: pdfGrayscale,
            pdfStripMetadata: pdfStripMetadata,
            targetSizeMode: targetSizeMode,
            customTargetSizeMB: customTargetSizeMB,
            preserveResolutionInTargetMode: preserveResolutionInTargetMode,
            preserveAudioQualityInTargetMode: preserveAudioQualityInTargetMode,
            suffix: outputSuffix.isEmpty ? "_min" : outputSuffix,
            customOutputFolder: customOutputFolder,
            exportToSubfolder: exportToSubfolder,
            subfolderName: subfolderName.isEmpty ? "Squeezed" : subfolderName,
            stripMetadata: stripMetadata
        )
    }
    
    // MARK: - Clipboard Squeeze Action
    @MainActor
    public func squeezeClipboard() {
        let pasteboard = NSPasteboard.general
        
        // 1. Check for file URLs first
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            Task {
                await MediaCompressionEngine.shared.processDroppedURLs(urls)
            }
            return
        }
        
        // 2. Check for image data (e.g. screenshot copied to clipboard)
        if let imgData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let tempSource = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard_temp_\(UUID().uuidString).png")
            let config = currentConfiguration()
            let tempDest = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard_squeezed_\(UUID().uuidString).\(AcceleratedImageCompressor().outputExtension(for: tempSource, config: config))")
            
            do {
                try imgData.write(to: tempSource)
                let originalSize = Int64(imgData.count)
                let startTime = Date()
                
                try AcceleratedImageCompressor().compressImage(from: tempSource, to: tempDest, config: config)
                let compressedData = try Data(contentsOf: tempDest)
                let compressedSize = Int64(compressedData.count)
                
                // Write compressed data back to clipboard
                pasteboard.clearContents()
                if let compressedImage = NSImage(data: compressedData) {
                    pasteboard.writeObjects([compressedImage, tempDest as NSURL])
                }
                
                let duration = Date().timeIntervalSince(startTime)
                let result = CompressionResult(
                    originalURL: tempSource,
                    outputURL: tempDest,
                    originalSize: originalSize,
                    compressedSize: compressedSize,
                    duration: duration,
                    mediaType: .image
                )
                
                recordResult(result)
                triggerSuccessBadge()
            } catch {
                print("Clipboard squeeze failed: \(error)")
            }
        }
    }
    
    // MARK: - Job Management
    public func addJob(_ job: CompressionJob) {
        activeJobs.append(job)
        updateProcessingState()
    }
    
    public func updateJob(id: UUID, progress: Double, statusText: String) {
        if let idx = activeJobs.firstIndex(where: { $0.id == id }) {
            activeJobs[idx].progress = progress
            activeJobs[idx].statusText = statusText
            updateProcessingState()
        }
    }
    
    public func finishJob(id: UUID, result: CompressionResult?, error: String?) {
        if let idx = activeJobs.firstIndex(where: { $0.id == id }) {
            activeJobs[idx].isFinished = true
            activeJobs[idx].error = error
            if let result = result {
                activeJobs[idx].statusText = "Saved \(result.formattedSaved) (-\(Int(result.percentSaved))%)"
                activeJobs[idx].progress = 1.0
                recordResult(result)
            } else {
                activeJobs[idx].statusText = error ?? "Failed"
            }
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.activeJobs.removeAll { $0.id == id }
            self.updateProcessingState()
        }
        
        updateProcessingState()
    }
    
    public func cancelJob(id: UUID) {
        if let idx = activeJobs.firstIndex(where: { $0.id == id }) {
            activeJobs[idx].isFinished = true
            activeJobs[idx].error = "Cancelled"
            activeJobs[idx].statusText = "Cancelled"
        }
        updateProcessingState()
        
        Task {
            await MediaCompressionEngine.shared.cancelJob(id: id)
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.activeJobs.removeAll { $0.id == id }
            self.updateProcessingState()
        }
    }
    
    public func cancelAllJobs() {
        for idx in activeJobs.indices {
            if !activeJobs[idx].isFinished {
                activeJobs[idx].isFinished = true
                activeJobs[idx].error = "Cancelled"
                activeJobs[idx].statusText = "Cancelled"
            }
        }
        updateProcessingState()
        
        Task {
            await MediaCompressionEngine.shared.cancelAllJobs()
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.activeJobs.removeAll { $0.isFinished }
            self.updateProcessingState()
        }
    }
    
    private func updateProcessingState() {
        let unfinished = activeJobs.filter { !$0.isFinished }
        isProcessing = !unfinished.isEmpty
        if unfinished.isEmpty {
            overallProgress = 0.0
        } else {
            let total = unfinished.reduce(0.0) { $0 + $1.progress }
            overallProgress = total / Double(unfinished.count)
        }
    }
    
    public func triggerSuccessBadge() {
        showSuccessBadge = true
        
        // Play pleasing completion sound
        if soundEnabled {
            let soundName = soundTheme.systemSoundName
            NSSound(named: soundName)?.play()
        }
        
        if hapticEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self.showSuccessBadge = false
        }
    }
    
    // MARK: - History & Persistence
    public func recordResult(_ result: CompressionResult) {
        recentResults.insert(result, at: 0)
        if recentResults.count > 50 {
            recentResults.removeLast()
        }
        
        totalBytesSaved += result.bytesSaved
        totalOriginalBytes += result.originalSize
        totalFilesProcessed += 1
        
        UserDefaults.standard.set(totalBytesSaved, forKey: Keys.totalBytesSaved)
        UserDefaults.standard.set(totalOriginalBytes, forKey: Keys.totalOriginalBytes)
        UserDefaults.standard.set(totalFilesProcessed, forKey: Keys.totalFilesProcessed)
        
        saveHistory()
    }
    
    public func clearHistory() {
        recentResults.removeAll()
        saveHistory()
    }
    
    public func resetAllStats() {
        totalBytesSaved = 0
        totalOriginalBytes = 0
        totalFilesProcessed = 0
        recentResults.removeAll()
        UserDefaults.standard.removeObject(forKey: Keys.totalBytesSaved)
        UserDefaults.standard.removeObject(forKey: Keys.totalOriginalBytes)
        UserDefaults.standard.removeObject(forKey: Keys.totalFilesProcessed)
        UserDefaults.standard.removeObject(forKey: Keys.historyList)
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentResults) {
            UserDefaults.standard.set(data, forKey: Keys.historyList)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: Keys.historyList),
           let list = try? JSONDecoder().decode([CompressionResult].self, from: data) {
            self.recentResults = list
        }
    }
    
    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
