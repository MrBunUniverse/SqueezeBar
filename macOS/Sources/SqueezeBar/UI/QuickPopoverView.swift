import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing
import ImageIO
import AVFoundation
import PDFKit

public struct QuickPopoverView: View {
    @EnvironmentObject var state: AppState
    public var isDetachedWindow: Bool = false
    @State private var selectedTab: PopoverTab = .activity
    @State private var isWindowDropTargeted: Bool = false
    @State private var activeFormatCategory: MediaFormatCategory = .images
    @State private var isFormatDrawerExpanded: Bool = false
    
    // Project Folders & Batch Edit State
    @State private var isEditMode: Bool = false
    @State private var selectedResultIds: Set<UUID> = []
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var isBatchRenaming: Bool = false
    @State private var renamePattern: String = ""
    @State private var isMovingToFolder: Bool = false
    @State private var showClearConfirmation: Bool = false
    
    // Supporter Modal State
    @State private var showProModal: Bool = false
    @State private var proModalFeatureTitle: String = "Additional Features"
    @State private var proModalFeatureDesc: String = "Unlock unlimited batch processing and custom styling."
    
    @Namespace private var presetGliderNamespace
    @Namespace private var mainTabGliderNamespace
    @Namespace private var targetLimitGliderNamespace
    @Namespace private var imgQualityGliderNamespace
    @Namespace private var imgResGliderNamespace
    @Namespace private var imgFormatGliderNamespace
    @Namespace private var vidQualityGliderNamespace
    @Namespace private var vidResGliderNamespace
    @Namespace private var vidCodecGliderNamespace
    @Namespace private var vidFpsGliderNamespace
    @Namespace private var gifFpsGliderNamespace
    @Namespace private var audioBitrateGliderNamespace
    @Namespace private var pdfDpiGliderNamespace
    @Namespace private var pdfQualityGliderNamespace
    @Namespace private var uiScaleGliderNamespace
    @Namespace private var dropBallGliderNamespace
    @Namespace private var dropBallGlassGliderNamespace
    
    // Liquid Glass Collective Hover States (Apple-like Focus Bounce)
    @State private var hoveredTab: PopoverTab? = nil
    @State private var hoveredProfileTile: String? = nil
    @State private var hoveredQuickPresetMode: TargetSizeMode? = nil
    @State private var hoveredTargetLimitMode: TargetSizeMode? = nil
    @State private var hoveredUIScaleOption: UIScaleOption? = nil
    @State private var hoveredDropBallAnimStyle: DropBallAnimationStyle? = nil
    @State private var hoveredDropBallGlassStyle: DropBallGlassStyle? = nil
    
    enum PopoverTab: String, CaseIterable {
        case activity = "Activity"
        case settings = "Settings"
    }
    
    enum MediaFormatCategory: String, CaseIterable {
        case images = "Images"
        case videos = "Video"
        case audio = "Audio"
        case pdf = "PDF"
    }
    
    public init(isDetachedWindow: Bool = false) {
        self.isDetachedWindow = isDetachedWindow
    }
    
    public var body: some View {
        let scale = state.uiScale.scaleFactor
        
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let contentWidth = availableWidth / scale
            let contentHeight = availableHeight / scale
            
            innerMainContent
                .frame(width: contentWidth, height: contentHeight)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .frame(minWidth: state.uiScale.baseWidth - 20, maxWidth: .infinity, minHeight: state.uiScale.baseHeight - 40, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView(
                    material: isDetachedWindow ? .hudWindow : .popover,
                    blendingMode: isDetachedWindow ? .withinWindow : .behindWindow
                )
                
                if isWindowDropTargeted {
                    RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0)
                        .strokeBorder(state.accentColor, lineWidth: 2)
                        .background(state.accentColor.opacity(0.08))
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0))
        .ignoresSafeArea()
        .onDrop(of: [.fileURL], isTargeted: $isWindowDropTargeted) { providers in
            extractAndProcess(providers: providers)
        }
        .sheet(item: $state.inspectedResult) { result in
            BeforeAfterInspectorView(result: result) {
                state.inspectedResult = nil
            }
        }
        .background(
            Group {
                Button("") {
                    state.squeezeClipboard()
                }
                .keyboardShortcut("v", modifiers: [.command])
                
                Button("") {
                    FloatingDropWindowController.shared.toggleWindow()
                }
                .keyboardShortcut("d", modifiers: [.command])
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
    }
    
    private var innerMainContent: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView
            
            Divider()
                .opacity(0.3)
            
            // Tab Selector
            tabSelectorView
            
            // Tab Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {
                    if selectedTab == .activity {
                        statsSummaryCard
                        
                        // Active Format Configuration Deck (Sliders, Quality, Resolution, Target Size, Codecs)
                        activeFormatSettingsDeck
                        
                        if !state.activeJobs.isEmpty {
                            activeQueueSection
                        }
                        
                        recentHistorySection
                    } else {
                        settingsSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            
            Divider()
                .opacity(0.3)
            
            // Bottom Action Bar
            footerView
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        let isDetached = isDetachedWindow || state.isDetached
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SqueezeBar")
                    .font(.system(size: 13.5, weight: .bold, design: .serif))
                
                Text("Universal Media Optimizer")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isDetached {
                // Circular Dock button (Only shown in detached floating window)
                Button {
                    FloatingDropWindowController.shared.dockToMenuBar()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .help("Dock to Menu Bar")
            } else {
                // Circular Undock button (Only shown in Menu Bar popover)
                Button {
                    StatusBarController.sharedInstance?.closePopover(sender: nil)
                    FloatingDropWindowController.shared.showFloatingWindow()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .help("Undock as Floating Window")
            }
            
            if state.isProcessing {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.60)
                        .frame(width: 12, height: 12)
                    Text("Optimizing...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(state.accentColor)
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            state.cancelAllJobs()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel All Compression")
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(state.accentColor.opacity(0.12)))
            } else if state.showSuccessBadge {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("Complete")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.green.opacity(0.12)))
            }
        }
        .padding(.leading, isDetached ? 96 : 20)
        .padding(.trailing, 18)
        .padding(.top, isDetached ? 16 : 14)
        .padding(.bottom, 12)
    }
    
    // MARK: - Tab Selector (Long Activity Pill + Circle Settings Button)
    private var tabSelectorView: some View {
        HStack(spacing: 5) {
            // Long Activity Tab Pill
            let isActivitySelected = selectedTab == .activity
            let isActivityHovered = hoveredTab == .activity
            
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    selectedTab = .activity
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(isActivitySelected ? state.accentColor : .secondary.opacity(0.8))
                    Text("Activity")
                        .font(.system(size: 11.5, weight: isActivitySelected ? .semibold : .medium))
                        .foregroundColor(isActivitySelected ? .white : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6.5)
                .background(
                    ZStack {
                        if isActivitySelected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.19), Color.white.opacity(0.09)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.75
                                        )
                                )
                                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 1.5)
                        }
                    }
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .scaleEffect(isActivityHovered ? 1.012 : 1.0)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredTab)
            .onHover { hovering in
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                    if hovering {
                        hoveredTab = .activity
                    } else if hoveredTab == .activity {
                        hoveredTab = nil
                    }
                }
            }
            
            // Circle Settings Button
            let isSettingsSelected = selectedTab == .settings
            let isSettingsHovered = hoveredTab == .settings
            
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    selectedTab = .settings
                    FloatingDropWindowController.shared.ensureMinimumDimensions(width: 490, height: 660)
                    StatusBarController.sharedInstance?.ensurePopoverDimensions(width: 490, height: 660)
                }
            } label: {
                ZStack {
                    if isSettingsSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.40), Color.white.opacity(0.10)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.75
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 1.5)
                    }
                    
                    Image(systemName: isSettingsSelected ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSettingsSelected ? state.accentColor : .secondary)
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .scaleEffect(isSettingsHovered ? 1.06 : 1.0)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredTab)
            .onHover { hovering in
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                    if hovering {
                        hoveredTab = .settings
                    } else if hoveredTab == .settings {
                        hoveredTab = nil
                    }
                }
            }
            .help("App & Theme Settings")
        }
        .padding(3.5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.24))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
    
    // MARK: - Quick Presets Bar (Pill Gliders with Sliding Spring Matched Geometry & Cursor Glow)
    private var quickPresetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TargetSizeMode.allCases, id: \.self) { mode in
                    let isHovered = hoveredQuickPresetMode == mode
                    let isOtherHovered = hoveredQuickPresetMode != nil && !isHovered
                    
                    InteractivePresetPill(
                        mode: mode,
                        isSelected: state.targetSizeMode == mode,
                        accentColor: state.accentColor,
                        contrastTextColor: state.contrastTextColor,
                        namespace: presetGliderNamespace
                    ) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            state.targetSizeMode = mode
                        }
                    }
                    .scaleEffect(isHovered ? 1.02 : 1.0)
                    .opacity(isOtherHovered ? 0.88 : 1.0)
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredQuickPresetMode)
                    .onHover { hovering in
                        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                            if hovering {
                                hoveredQuickPresetMode = mode
                            } else if hoveredQuickPresetMode == mode {
                                hoveredQuickPresetMode = nil
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
        }
    }
    
    // MARK: - Live Format Selector Cards (Images, Video, Audio, PDF)
    private var statsSummaryCard: some View {
        HStack(spacing: 5) {
            imageProfileTile
            videoProfileTile
            audioProfileTile
            pdfProfileTile
        }
    }
    
    // Profile tile scaling and opacity helpers for Apple-like collective focus bounce
    private func profileTileScale(for id: String) -> CGFloat {
        guard let hovered = hoveredProfileTile else { return 1.0 }
        return hovered == id ? 1.015 : 0.992
    }
    
    private func profileTileOpacity(for id: String) -> Double {
        guard let hovered = hoveredProfileTile else { return 1.0 }
        return hovered == id ? 1.0 : 0.90
    }
    
    // MARK: - Live Interactive Format Selector Cards
    private var imageProfileTile: some View {
        let qualityPct = Int(state.imageQualitySlider * 100)
        let scaleText = state.imageResolutionScale >= 1.0 ? "100%" : "\(Int(state.imageResolutionScale * 100))%"
        let isSelected = activeFormatCategory == .images
        let isExpanded = isSelected && isFormatDrawerExpanded
        
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isSelected && isFormatDrawerExpanded {
                    isFormatDrawerExpanded = false
                } else {
                    activeFormatCategory = .images
                    isFormatDrawerExpanded = true
                }
            }
        } label: {
            LiveProfileGlowCard(accentColor: state.accentColor, isSelected: isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .primary.opacity(0.85))
                        Text("Images")
                            .font(.system(size: 9.5, weight: .bold, design: .serif))
                            .foregroundColor(isExpanded ? .primary : .secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .secondary.opacity(0.6))
                    }
                    
                    Text(state.imageFormatPolicy.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(qualityPct)% Quality • \(scaleText) Scale")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(profileTileScale(for: "image"))
        .opacity(profileTileOpacity(for: "image"))
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredProfileTile)
        .onHover { hovering in
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                if hovering {
                    hoveredProfileTile = "image"
                } else if hoveredProfileTile == "image" {
                    hoveredProfileTile = nil
                }
            }
        }
        .help("Click to toggle Image compression sliders & format settings")
    }
    
    private var videoProfileTile: some View {
        let codecText = state.videoCodec == .hevc ? "HEVC" : (state.videoCodec == .h264 ? "H.264" : "GIF")
        let fpsText = state.videoFramerate.rawValue
        let qualityPct = Int(state.videoQualitySlider * 100)
        let scaleText = state.videoResolutionScale >= 1.0 ? "100%" : "\(Int(state.videoResolutionScale * 100))%"
        let isSelected = activeFormatCategory == .videos
        let isExpanded = isSelected && isFormatDrawerExpanded
        
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isSelected && isFormatDrawerExpanded {
                    isFormatDrawerExpanded = false
                } else {
                    activeFormatCategory = .videos
                    isFormatDrawerExpanded = true
                }
            }
        } label: {
            LiveProfileGlowCard(accentColor: state.accentColor, isSelected: isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "film")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .primary.opacity(0.85))
                        Text("Video")
                            .font(.system(size: 9.5, weight: .bold, design: .serif))
                            .foregroundColor(isExpanded ? .primary : .secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .secondary.opacity(0.6))
                    }
                    
                    Text("\(codecText) • \(fpsText)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(qualityPct)% Quality • \(scaleText) Scale")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(profileTileScale(for: "video"))
        .opacity(profileTileOpacity(for: "video"))
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredProfileTile)
        .onHover { hovering in
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                if hovering {
                    hoveredProfileTile = "video"
                } else if hoveredProfileTile == "video" {
                    hoveredProfileTile = nil
                }
            }
        }
        .help("Click to toggle Video compression sliders & codec settings")
    }
    
    private var audioProfileTile: some View {
        let bitrateLabel = state.audioBitrate.rawValue.components(separatedBy: " ").first ?? "128 kbps"
        let exifText = state.stripMetadata ? "Strip EXIF: ON" : "Preserve EXIF"
        let isSelected = activeFormatCategory == .audio
        let isExpanded = isSelected && isFormatDrawerExpanded
        
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isSelected && isFormatDrawerExpanded {
                    isFormatDrawerExpanded = false
                } else {
                    activeFormatCategory = .audio
                    isFormatDrawerExpanded = true
                }
            }
        } label: {
            LiveProfileGlowCard(accentColor: state.accentColor, isSelected: isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .primary.opacity(0.85))
                        Text("Audio")
                            .font(.system(size: 9.5, weight: .bold, design: .serif))
                            .foregroundColor(isExpanded ? .primary : .secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .secondary.opacity(0.6))
                    }
                    
                    Text(bitrateLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(exifText)
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(profileTileScale(for: "audio"))
        .opacity(profileTileOpacity(for: "audio"))
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredProfileTile)
        .onHover { hovering in
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                if hovering {
                    hoveredProfileTile = "audio"
                } else if hoveredProfileTile == "audio" {
                    hoveredProfileTile = nil
                }
            }
        }
        .help("Click to toggle Audio Bitrate & export settings")
    }
    
    private var pdfProfileTile: some View {
        let dpiText = "\(Int(state.pdfDPI.dpiValue)) DPI"
        let qualityText = "\(Int(state.pdfImageQuality * 100))% Q"
        let grayText = state.pdfGrayscale ? " • B&W" : ""
        let isSelected = activeFormatCategory == .pdf
        let isExpanded = isSelected && isFormatDrawerExpanded
        
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isSelected && isFormatDrawerExpanded {
                    isFormatDrawerExpanded = false
                } else {
                    activeFormatCategory = .pdf
                    isFormatDrawerExpanded = true
                }
            }
        } label: {
            LiveProfileGlowCard(accentColor: state.accentColor, isSelected: isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .primary.opacity(0.85))
                        Text("PDF")
                            .font(.system(size: 9.5, weight: .bold, design: .serif))
                            .foregroundColor(isExpanded ? .primary : .secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(isExpanded ? state.accentColor : .secondary.opacity(0.6))
                    }
                    
                    Text("\(dpiText)\(grayText)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(qualityText) • Optimized")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(profileTileScale(for: "pdf"))
        .opacity(profileTileOpacity(for: "pdf"))
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredProfileTile)
        .onHover { hovering in
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                if hovering {
                    hoveredProfileTile = "pdf"
                } else if hoveredProfileTile == "pdf" {
                    hoveredProfileTile = nil
                }
            }
        }
        .help("Click to toggle PDF document compression & DPI settings")
    }
    
    // MARK: - Active Queue Section
    private var activeQueueSection: some View {
        let unfinished = state.activeJobs.filter { !$0.isFinished }
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CURRENT QUEUE")
                    .font(.system(size: 9.5, weight: .bold, design: .serif))
                    .foregroundColor(.secondary)
                Spacer()
                
                if !unfinished.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            state.cancelAllJobs()
                        }
                    } label: {
                        Text(unfinished.count > 1 ? "Cancel All" : "Cancel")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.red.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.12))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.red.opacity(0.25), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Cancel running compression tasks")
                }
            }
            
            ForEach(state.activeJobs) { job in
                let progressPct = Int(job.progress * 100)
                
                HStack(spacing: 9) {
                    FileThumbnailView(url: job.fileURL, mediaType: job.mediaType, size: 30)
                    
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(job.fileURL.lastPathComponent)
                            .font(.system(size: 11.5, weight: .semibold, design: .serif))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(job.statusText)
                            .font(.system(size: 9.5))
                            .foregroundColor(job.error == "Cancelled" ? .secondary : state.accentColor)
                    }
                    
                    Spacer(minLength: 4)
                    
                    if !job.isFinished {
                        // Compact Progress Pill
                        Text("\(progressPct)%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(state.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(state.accentColor.opacity(0.15))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(state.accentColor.opacity(0.3), lineWidth: 0.5)
                            )
                        
                        // Individual Cancel Button
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                state.cancelJob(id: job.id)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel this compression task")
                    } else if job.error == "Cancelled" {
                        Text("Cancelled")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(9)
                .background(
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Base Glass Card
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.045), Color.white.opacity(0.015)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            // Unified Light Opacity Progress Fill Across Card
                            if !job.isFinished {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                state.accentColor.opacity(0.22),
                                                state.accentColor.opacity(0.12)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geo.size.width * CGFloat(min(1.0, max(0.0, job.progress)))))
                                    .animation(.linear(duration: 0.2), value: job.progress)
                            }
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(job.error == "Cancelled" ? Color.white.opacity(0.1) : state.accentColor.opacity(0.35), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - Recent History Section with Collapsible Folders & Batch Edit
    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Bar
            HStack(spacing: 6) {
                Text("PROJECTS & RECENT")
                    .font(.system(size: 9.5, weight: .bold, design: .serif))
                    .foregroundColor(.secondary.opacity(0.9))
                
                Spacer()
                
                // New Folder Button
                Button {
                    newFolderName = "Project \(state.customFolders.count + 1)"
                    isCreatingFolder = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 9))
                        Text("New Folder")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Create Project Folder")
                
                if !state.recentResults.isEmpty {
                    // Edit Mode Toggle Button
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedResultIds.removeAll()
                            }
                        }
                    } label: {
                        Text(isEditMode ? "Done" : "Edit")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(isEditMode ? state.contrastTextColor : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(isEditMode ? state.accentColor : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    
                    if !isEditMode {
                        Button("Clear") {
                            showClearConfirmation = true
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(Color.red.opacity(0.88))
                        .confirmationDialog("Clear Recent Compressions?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                            Button("Clear All History", role: .destructive) {
                                state.clearHistory()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will remove recent items from your activity log. Original files on disk will not be deleted.")
                        }
                    }
                }
            }
            
            // Batch Action Toolbar (Visible in Edit Mode)
            if isEditMode {
                batchActionToolbar
            }
            
            if state.recentResults.isEmpty && state.customFolders.isEmpty {
                emptyHistoryView
            } else {
                // 1. Custom Project Folders
                ForEach(state.customFolders) { folder in
                    folderSectionView(folder: folder)
                }
                
                // 2. Uncategorized Recent Items
                let uncategorized = state.recentResults.filter { $0.folderId == nil }
                if !uncategorized.isEmpty || state.customFolders.isEmpty {
                    if !state.customFolders.isEmpty {
                        HStack {
                            Text("Uncategorized")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if isEditMode {
                                Button("Select All") {
                                    let ids = Set(uncategorized.map { $0.id })
                                    if selectedResultIds.isSuperset(of: ids) {
                                        selectedResultIds.subtract(ids)
                                    } else {
                                        selectedResultIds.formUnion(ids)
                                    }
                                }
                                .font(.system(size: 9))
                                .buttonStyle(.plain)
                                .foregroundColor(state.accentColor)
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    ForEach(uncategorized) { item in
                        historyRow(item: item)
                    }
                }
            }
        }
        .sheet(isPresented: $isCreatingFolder) {
            newFolderModal
        }
        .sheet(isPresented: $isBatchRenaming) {
            batchRenameModal
        }
    }
    // MARK: - Supporter Upgrade Modal (Paywall Experience)
    private var proUpgradeModal: some View {
        VStack(spacing: 16) {
            // Header with glowing badge
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("SqueezeBar")
                        .font(.system(size: 16, weight: .bold))
                    
                    Text("Supporter")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                }
                
                Text(proModalFeatureTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(state.accentColor)
                
                Text(proModalFeatureDesc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            
            // Feature Unlocks List
            VStack(alignment: .leading, spacing: 7) {
                proFeatureRow(icon: "infinity", title: "Unlimited Batch File Compression (No 50-file limit)")
                proFeatureRow(icon: "paintpalette.fill", title: "Full Color Palette & Custom HEX Theme Customization")
                proFeatureRow(icon: "menubar.rectangle", title: "Menu Bar Styles & Live Savings Stats Counter")
                proFeatureRow(icon: "speaker.wave.3.fill", title: "Custom Soundpacks (Arcade, Bubble, Hydraulic, Sci-Fi)")
                proFeatureRow(icon: "heart.fill", title: "Support Dev")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            )
            
            // Action Buttons
            VStack(spacing: 8) {
                SupporterActionButton {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        state.isProUser = true
                        showProModal = false
                    }
                    // Immersive celebratory confetti explosion that bursts across the window
                    ConfettiCannonController.shared.explode()
                }
                
                Button("Maybe Later") {
                    showProModal = false
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
    
    private func proFeatureRow(icon: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.primary.opacity(0.9))
            Spacer()
        }
    }
    
    // MARK: - Batch Action Toolbar (Select All, Delete, Move, Rename)
    private var batchActionToolbar: some View {
        HStack(spacing: 8) {
            Button {
                if selectedResultIds.count == state.recentResults.count {
                    selectedResultIds.removeAll()
                } else {
                    selectedResultIds = Set(state.recentResults.map { $0.id })
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedResultIds.count == state.recentResults.count && !state.recentResults.isEmpty ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundColor(selectedResultIds.isEmpty ? .secondary : state.accentColor)
                    Text(selectedResultIds.count == state.recentResults.count && !state.recentResults.isEmpty ? "Deselect All" : "Select All")
                        .font(.system(size: 9.5, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            
            Text("(\(selectedResultIds.count) selected)")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if !selectedResultIds.isEmpty {
                // Batch Rename Button
                Button {
                    renamePattern = "Compressed_#"
                    isBatchRenaming = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 9))
                        Text("Rename")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(state.contrastTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(state.accentColor))
                }
                .buttonStyle(.plain)
                
                // Move to Folder Menu
                Menu {
                    Button("None (Uncategorized)") {
                        state.assignResultsToFolder(resultIds: selectedResultIds, folderId: nil)
                    }
                    ForEach(state.customFolders) { f in
                        Button(f.name) {
                            state.assignResultsToFolder(resultIds: selectedResultIds, folderId: f.id)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text("Move")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                
                // Batch Delete Button
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        state.batchDeleteResults(ids: selectedResultIds)
                        selectedResultIds.removeAll()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(5)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Delete Selected")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        )
    }
    
    // MARK: - Collapsible Folder Section View with Direct Drag & Drop Support
    @ViewBuilder
    private func folderSectionView(folder: CompressionFolder) -> some View {
        FolderSectionItemView(
            folder: folder,
            isEditMode: isEditMode,
            selectedResultIds: $selectedResultIds
        )
    }
    
    // MARK: - Modals (New Folder & Format Rename)
    private var newFolderModal: some View {
        VStack(spacing: 12) {
            Text("Create Project Folder")
                .font(.system(size: 13, weight: .bold))
            
            TextField("Folder Name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            
            HStack(spacing: 10) {
                Button("Cancel") {
                    isCreatingFolder = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button("Create") {
                    state.addFolder(name: newFolderName)
                    isCreatingFolder = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(state.accentColor))
            }
        }
        .padding(20)
        .frame(width: 280)
    }
    
    private var batchRenameModal: some View {
        let previewExample1 = renamePattern.replacingOccurrences(of: "{index}", with: "1").replacingOccurrences(of: "{i}", with: "1").replacingOccurrences(of: "#", with: "1")
        let previewExample2 = renamePattern.replacingOccurrences(of: "{index}", with: "2").replacingOccurrences(of: "{i}", with: "2").replacingOccurrences(of: "#", with: "2")
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Batch Format Rename (\(selectedResultIds.count) files)")
                .font(.system(size: 13, weight: .bold))
            
            Text("Enter a format pattern. Use '#' or '{index}' for auto-incrementing numbers.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            TextField("e.g. Homerenovation_# or Project_{index}", text: $renamePattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            
            // Live Format Preview Box
            VStack(alignment: .leading, spacing: 3) {
                Text("LIVE PREVIEW:")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.8))
                
                HStack(spacing: 4) {
                    Text("\(previewExample1).mp4,  \(previewExample2).mp4 ...")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(state.accentColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(state.accentColor.opacity(0.3), lineWidth: 0.5))
            }
            
            // Quick preset tokens
            HStack(spacing: 6) {
                Button("Homerenovation_#") {
                    renamePattern = "Homerenovation_#"
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                
                Button("Optimized_{index}") {
                    renamePattern = "Optimized_{index}"
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    isBatchRenaming = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button("Rename Files") {
                    state.batchRenameResults(ids: selectedResultIds, pattern: renamePattern)
                    isBatchRenaming = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(state.accentColor))
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 320)
    }
    
    @State private var isDropTargeted: Bool = false
    @State private var isQueueDropTargeted: Bool = false
    
    private var emptyHistoryView: some View {
        VStack(spacing: 14) {
            // 1. Quick Squeeze Area (Top Zone - Instant Compression)
            quickSqueezeZone
            
            // 2. Custom Queue Area (Under Quick Squeeze - Stage & Customize Per File)
            customQueueSection
        }
    }
    
    // MARK: - Quick Squeeze Zone (Instant 1-Drop Compression)
    private var quickSqueezeZone: some View {
        VStack(spacing: 10) {
            ZStack {
                // Liquid ambient glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (isDropTargeted ? state.accentColor : Color.white).opacity(isDropTargeted ? 0.35 : 0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 32
                        )
                    )
                    .frame(width: 58, height: 58)
                
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down.on.square")
                    .font(.system(size: 24))
                    .foregroundColor(isDropTargeted ? state.accentColor : .secondary.opacity(0.6))
                    .scaleEffect(isDropTargeted ? 1.15 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isDropTargeted)
            }
            
            VStack(spacing: 3) {
                Text(isDropTargeted ? "Release to Squeeze" : "Ready to Squeeze")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundColor(.primary)
                
                Text("Drop media to compress immediately with current presets")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Format Tags Pill Strip
            HStack(spacing: 4) {
                ForEach(["MP4", "MOV", "PNG", "JPG", "WebP", "PDF", "AAC", "WAV"], id: \.self) { fmt in
                    Text(fmt)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.04)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
                }
            }
            
            // Clipboard Squeeze Button
            Button {
                state.squeezeClipboard()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 9))
                    Text("Squeeze from Clipboard")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    Text("⌘V")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.9))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .scaleEffect(isDropTargeted ? 1.02 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isDropTargeted)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    isDropTargeted ? state.accentColor.opacity(0.10) :
                    Color.white.opacity(0.02)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDropTargeted ? state.accentColor.opacity(0.7) : Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 1, dash: isDropTargeted ? [] : [4])
                        )
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            extractAndProcess(providers: providers)
        }
    }
    
    // MARK: - Custom Staged Queue Section (Customize Settings Per File)
    private var customQueueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.stagedQueue.isEmpty {
                // Empty Queue Drop Target Card
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.accentColor.opacity(0.15))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: isQueueDropTargeted ? "arrow.down.doc.fill" : "tray.and.arrow.down.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(state.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isQueueDropTargeted ? "Drop to Add to Queue" : "Custom Staged Queue")
                                .font(.system(size: 11.5, weight: .bold, design: .serif))
                                .foregroundColor(.primary)
                            
                            Text("Drop files here to customize individual settings before squeezing")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isQueueDropTargeted ? state.accentColor.opacity(0.12) : Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isQueueDropTargeted ? state.accentColor.opacity(0.8) : Color.white.opacity(0.08),
                                    style: StrokeStyle(lineWidth: isQueueDropTargeted ? 1.5 : 1, dash: isQueueDropTargeted ? [] : [3])
                                )
                        )
                )
                .scaleEffect(isQueueDropTargeted ? 1.02 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isQueueDropTargeted)
                .onDrop(of: [.fileURL], isTargeted: $isQueueDropTargeted) { providers in
                    extractAndAddToQueue(providers: providers)
                }
            } else {
                // Staged Queue Active Card
                stagedQueueActiveView
            }
        }
    }
    
    // MARK: - Active Staged Queue View with Per-File Cards
    private var stagedQueueActiveView: some View {
        VStack(spacing: 8) {
            // Queue Header with Squeeze All Button
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(state.accentColor)
                    
                    Text("Staged Queue (\(state.stagedQueue.count))")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button("Clear") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                        state.clearQueue()
                    }
                }
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color.red.opacity(0.88))
                .buttonStyle(.plain)
                
                Button {
                    state.squeezeStagedQueue()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Squeeze All (\(state.stagedQueue.count))")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(state.accentColor))
                    .shadow(color: state.accentColor.opacity(0.35), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
            
            // Queue Items List
            VStack(spacing: 6) {
                ForEach(state.stagedQueue) { item in
                    StagedQueueRowItem(item: item)
                }
            }
            
            // Drop more files footer strip
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Drop more files to add to queue")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3]))
            )
            .onDrop(of: [.fileURL], isTargeted: $isQueueDropTargeted) { providers in
                extractAndAddToQueue(providers: providers)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        )
    }
    
    private func extractAndProcess(providers: [NSItemProvider]) -> Bool {
        var collectedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    collectedURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !collectedURLs.isEmpty {
                Task {
                    await MediaCompressionEngine.shared.processDroppedURLs(collectedURLs)
                }
            }
        }
        return true
    }
    
    private func extractAndAddToQueue(providers: [NSItemProvider]) -> Bool {
        var collectedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    collectedURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !collectedURLs.isEmpty {
                state.addFilesToQueue(collectedURLs)
            }
        }
        return true
    }
    
    private func historyRow(item: CompressionResult) -> some View {
        QuickPopoverHistoryRowItem(
            item: item,
            isEditMode: isEditMode,
            selectedResultIds: $selectedResultIds
        )
    }
    
    // MARK: - Active Format Configuration Deck (Activity Tab Collapsible Drawer)
    @ViewBuilder
    private var activeFormatSettingsDeck: some View {
        if isFormatDrawerExpanded {
            VStack(spacing: 8) {
                // Header with Format Badge & Done Collapse Button
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: activeFormatCategory == .images ? "photo" : (activeFormatCategory == .videos ? "film" : (activeFormatCategory == .audio ? "waveform" : "doc.text.fill")))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(formatAccentColor(for: activeFormatCategory))
                        Text("\(activeFormatCategory.rawValue) Settings")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isFormatDrawerExpanded = false
                        }
                    } label: {
                        HStack(spacing: 3.5) {
                            Text("Done")
                                .font(.system(size: 9.5, weight: .semibold))
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(formatAccentColor(for: activeFormatCategory))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(formatAccentColor(for: activeFormatCategory).opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(formatAccentColor(for: activeFormatCategory).opacity(0.25), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Collapse Format Controls")
                }
                .padding(.horizontal, 2)
                
                if activeFormatCategory == .images {
                    imageSettingsCard
                } else if activeFormatCategory == .videos {
                    videoSettingsCard
                } else if activeFormatCategory == .audio {
                    audioSettingsCard
                } else if activeFormatCategory == .pdf {
                    pdfSettingsCard
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(formatAccentColor(for: activeFormatCategory).opacity(0.30), lineWidth: 0.75)
                    )
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }
    
    private func formatAccentColor(for category: MediaFormatCategory) -> Color {
        return state.accentColor
    }
    
    // MARK: - Settings Tab View (Theme & App Behavior Only)
    private var settingsSection: some View {
        generalSettingsCard
    }
    
    // MARK: - Smart Target Size Automation Card
    private func targetSizeAutomationCard(for category: MediaFormatCategory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            targetSizeHeader
            targetSizeGliderBar
            
            if state.targetSizeMode == .custom {
                customTargetSizeSlider
            }
            
            if state.targetSizeMode != .off {
                targetSizeToggles(for: category)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        )
    }
    
    private var targetSizeHeader: some View {
        HStack {
            Label("Target Size Limit", systemImage: "target")
                .font(.system(size: 11, weight: .bold, design: .serif))
            Spacer()
            if let targetMB = state.targetSizeMode.targetMegabytes ?? (state.targetSizeMode == .custom ? state.customTargetSizeMB : nil) {
                Text(String(format: "≤ %.0f MB", targetMB))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(state.accentColor)
            } else {
                Text("Manual Quality")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var targetSizeGliderBar: some View {
        HStack(spacing: 4) {
            ForEach(TargetSizeMode.allCases, id: \.self) { mode in
                let isHovered = hoveredTargetLimitMode == mode
                let isOtherHovered = hoveredTargetLimitMode != nil && !isHovered
                
                UniversalPillGliderItem(
                    item: mode,
                    title: mode == .off ? "Manual" : (mode == .custom ? "Custom" : (mode.targetMegabytes.map { "\(Int($0)) MB" } ?? mode.rawValue)),
                    icon: state.targetSizeMode == mode ? "checkmark" : nil,
                    isSelected: state.targetSizeMode == mode,
                    accentColor: state.accentColor,
                    contrastTextColor: state.contrastTextColor,
                    namespace: targetLimitGliderNamespace,
                    gliderId: "TargetLimitGlider"
                ) {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        state.targetSizeMode = mode
                    }
                }
                .scaleEffect(isHovered ? 1.015 : 1.0)
                .opacity(isOtherHovered ? 0.88 : 1.0)
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredTargetLimitMode)
                .onHover { hovering in
                    withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                        if hovering {
                            hoveredTargetLimitMode = mode
                        } else if hoveredTargetLimitMode == mode {
                            hoveredTargetLimitMode = nil
                        }
                    }
                }
            }
        }
    }
    
    private var customTargetSizeSlider: some View {
        VStack(spacing: 3) {
            HStack {
                Text("Custom Max Size")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f MB", state.customTargetSizeMB))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(state.accentColor)
            }
            
            LiquidGlassSlider(
                value: Binding(
                    get: { state.customTargetSizeMB },
                    set: { newVal in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            state.customTargetSizeMB = newVal
                        }
                    }
                ),
                range: 1.0...200.0,
                step: 1.0,
                accentColor: state.accentColor
            )
        }
        .padding(.top, 1)
    }
    
    @ViewBuilder
    private func targetSizeToggles(for category: MediaFormatCategory) -> some View {
        Divider()
            .opacity(0.12)
            .padding(.vertical, 1)
        
        VStack(spacing: 5) {
            LiquidGlassToggleRow(
                title: "Lock Original Resolution",
                subtitle: state.preserveResolutionInTargetMode ? "Keeps 100% dimensions and compresses quality/bitrate" : "Allows smart downscaling + bitrate reduction",
                icon: "aspectratio",
                isOn: $state.preserveResolutionInTargetMode
            )
            
            if category == .videos {
                LiquidGlassToggleRow(
                    title: "Lock Original Audio Quality",
                    subtitle: state.preserveAudioQualityInTargetMode ? "Keeps standard 128 kbps audio" : "Dynamically scales audio to maximize video quality",
                    icon: "waveform",
                    isOn: $state.preserveAudioQualityInTargetMode
                )
            }
        }
    }
    
    // MARK: - Image Settings
    private var imageSettingsCard: some View {
        VStack(spacing: 8) {
            targetSizeAutomationCard(for: .images)
            
            // Quality Slider Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Image Quality", systemImage: "photo")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text(String(format: "%.0f%%", state.imageQualitySlider * 100))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                LiquidGlassSlider(
                    value: $state.imageQualitySlider,
                    range: 0.30...1.0,
                    step: 0.05,
                    accentColor: state.accentColor
                )
                
                // Quick preset pills with matched geometry glider
                HStack(spacing: 4) {
                    ForEach(QualityPreset.allCases, id: \.self) { preset in
                        UniversalPillGliderItem(
                            item: preset,
                            title: preset.rawValue,
                            icon: nil,
                            isSelected: state.imageQualityPreset == preset,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: imgQualityGliderNamespace,
                            gliderId: "ImgQualityGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.imageQualityPreset = preset
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Resolution Slider Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Resolution Scale", systemImage: "aspectratio")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.imageResolutionScale >= 0.99 ? "Original (100%)" : String(format: "%.0f%% Scale", state.imageResolutionScale * 100))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                LiquidGlassSlider(
                    value: $state.imageResolutionScale,
                    range: 0.25...1.0,
                    step: 0.05,
                    accentColor: state.accentColor
                )
                
                // Quick resolution pills with matched geometry glider
                HStack(spacing: 4) {
                    ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { scale in
                        UniversalPillGliderItem(
                            item: scale,
                            title: scale >= 0.99 ? "Original" : "\(Int(scale * 100))%",
                            icon: nil,
                            isSelected: abs(state.imageResolutionScale - scale) < 0.01,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: imgResGliderNamespace,
                            gliderId: "ImgResGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.imageResolutionScale = scale
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Format Policy Card
            VStack(alignment: .leading, spacing: 7) {
                Text("Format Target")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                
                HStack(spacing: 4) {
                    ForEach(ImageFormatPolicy.allCases, id: \.self) { policy in
                        UniversalPillGliderItem(
                            item: policy,
                            title: policy.rawValue.replacingOccurrences(of: "Modern ", with: ""),
                            icon: nil,
                            isSelected: state.imageFormatPolicy == policy,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: imgFormatGliderNamespace,
                            gliderId: "ImgFormatGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.imageFormatPolicy = policy
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
    }
    
    // MARK: - Video Settings
    private var videoSettingsCard: some View {
        VStack(spacing: 8) {
            targetSizeAutomationCard(for: .videos)
            
            // Video Quality / Bitrate Slider
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Video Bitrate", systemImage: "film")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text(String(format: "%.0f%% of source", state.videoQualitySlider * 90))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                LiquidGlassSlider(
                    value: $state.videoQualitySlider,
                    range: 0.30...1.0,
                    step: 0.05,
                    accentColor: state.accentColor
                )
                
                // Quick preset pills with matched geometry glider
                HStack(spacing: 4) {
                    ForEach(QualityPreset.allCases, id: \.self) { preset in
                        UniversalPillGliderItem(
                            item: preset,
                            title: preset.rawValue,
                            icon: nil,
                            isSelected: state.videoQualityPreset == preset,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: vidQualityGliderNamespace,
                            gliderId: "VidQualityGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.videoQualityPreset = preset
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Video Resolution Slider Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Resolution Scale", systemImage: "aspectratio")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.videoResolutionScale >= 0.99 ? "Original (100%)" : String(format: "%.0f%% Scale", state.videoResolutionScale * 100))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                LiquidGlassSlider(
                    value: $state.videoResolutionScale,
                    range: 0.25...1.0,
                    step: 0.05,
                    accentColor: state.accentColor
                )
                
                // Quick resolution pills with matched geometry glider
                HStack(spacing: 4) {
                    ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { scale in
                        UniversalPillGliderItem(
                            item: scale,
                            title: scale >= 0.99 ? "Original" : "\(Int(scale * 100))%",
                            icon: nil,
                            isSelected: abs(state.videoResolutionScale - scale) < 0.01,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: vidResGliderNamespace,
                            gliderId: "VidResGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.videoResolutionScale = scale
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Framerate & Codec Controls Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Framerate (FPS)", systemImage: "speedometer")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.videoFramerate.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                HStack(spacing: 3.5) {
                    ForEach(VideoFramerateOption.allCases, id: \.self) { opt in
                        UniversalPillGliderItem(
                            item: opt,
                            title: opt == .original ? "Original" : opt.rawValue.replacingOccurrences(of: " FPS", with: ""),
                            icon: nil,
                            isSelected: state.videoFramerate == opt,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: vidFpsGliderNamespace,
                            gliderId: "VidFpsGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.videoFramerate = opt
                            }
                        }
                    }
                }
                
                Divider().opacity(0.15)
                
                Text("Format / Codec")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                
                HStack(spacing: 4) {
                    ForEach(VideoCodecPreference.allCases, id: \.self) { codec in
                        UniversalPillGliderItem(
                            item: codec,
                            title: codec.rawValue,
                            icon: nil,
                            isSelected: state.videoCodec == codec,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: vidCodecGliderNamespace,
                            gliderId: "VidCodecGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.videoCodec = codec
                            }
                        }
                    }
                }
                
                if state.videoCodec == .gif {
                    Divider().opacity(0.15)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label("GIF Framerate", systemImage: "speedometer")
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                            Text(state.gifFramerate.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(state.accentColor)
                        }
                        
                        HStack(spacing: 4) {
                            ForEach(GIFFramerateOption.allCases, id: \.self) { opt in
                                UniversalPillGliderItem(
                                    item: opt,
                                    title: opt.rawValue,
                                    icon: nil,
                                    isSelected: state.gifFramerate == opt,
                                    accentColor: state.accentColor,
                                    contrastTextColor: state.contrastTextColor,
                                    namespace: gifFpsGliderNamespace,
                                    gliderId: "GifFpsGlider"
                                ) {
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                        state.gifFramerate = opt
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Divider().opacity(0.15)
                    
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            state.videoRemoveAudio.toggle()
                        }
                    } label: {
                        HStack(alignment: .center) {
                            Text("Mute / Remove Audio Track")
                                .font(.system(size: 10))
                                .foregroundColor(.primary)
                            Spacer()
                            LiquidGlassSwitch(isOn: $state.videoRemoveAudio)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
    }
    
    // MARK: - Audio Settings
    private var audioSettingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Audio Bitrate", systemImage: "waveform")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.audioBitrate.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                // Bitrate pills with matched geometry glider
                HStack(spacing: 4) {
                    ForEach(AudioBitratePreference.allCases, id: \.self) { rate in
                        UniversalPillGliderItem(
                            item: rate,
                            title: rate.rawValue.components(separatedBy: " ").first ?? rate.rawValue,
                            icon: nil,
                            isSelected: state.audioBitrate == rate,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: audioBitrateGliderNamespace,
                            gliderId: "AudioBitrateGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.audioBitrate = rate
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
    }
    
    // MARK: - PDF Settings
    private var pdfSettingsCard: some View {
        VStack(spacing: 8) {
            targetSizeAutomationCard(for: .pdf)
            
            // DPI / Resolution Preset Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Document Resolution (DPI)", systemImage: "doc.text.image")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text("\(Int(state.pdfDPI.dpiValue)) DPI")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                HStack(spacing: 5) {
                    ForEach(PDFDPIOption.allCases, id: \.self) { dpi in
                        UniversalPillGliderItem(
                            item: dpi,
                            title: dpi.rawValue,
                            icon: nil,
                            isSelected: state.pdfDPI == dpi,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: pdfDpiGliderNamespace,
                            gliderId: "PDFDpiGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.pdfDPI = dpi
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Embedded Image Quality Slider Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Image Compression Quality", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    Spacer()
                    Text(String(format: "%.0f%%", state.pdfImageQuality * 100))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                LiquidGlassSlider(
                    value: $state.pdfImageQuality,
                    range: 0.30...1.0,
                    step: 0.05,
                    accentColor: state.accentColor
                )
                
                // Quick preset pills
                HStack(spacing: 5) {
                    ForEach([0.50, 0.70, 0.85], id: \.self) { quality in
                        let title = quality == 0.50 ? "50% Compact" : (quality == 0.70 ? "70% Balanced" : "85% High")
                        UniversalPillGliderItem(
                            item: quality,
                            title: title,
                            icon: nil,
                            isSelected: abs(state.pdfImageQuality - quality) < 0.01,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: pdfQualityGliderNamespace,
                            gliderId: "PDFQualityGlider"
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.pdfImageQuality = quality
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Advanced Document Optimization Toggles
            VStack(alignment: .leading, spacing: 7) {
                Text("Document Optimization")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                
                VStack(spacing: 5) {
                    LiquidGlassToggleRow(
                        title: "Convert to Grayscale (B&W)",
                        subtitle: "Converts scans & images to monochrome for extra reduction",
                        icon: "circle.lefthalf.filled",
                        isOn: $state.pdfGrayscale
                    )
                    
                    LiquidGlassToggleRow(
                        title: "Strip Document Metadata",
                        subtitle: "Removes author info and embedded thumbnail bloat",
                        icon: "tag.slash",
                        isOn: $state.pdfStripMetadata
                    )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
    }
    
    // MARK: - General Settings
    private var generalSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // UI Scaling / Display Density Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Interface Scaling", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                    Spacer()
                    Text("\(state.uiScale.rawValue) (\(state.uiScale.percentageLabel))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                // Liquid Pill Glider with Matched Geometry and Collective Focus Bounce
                HStack(spacing: 5) {
                    ForEach(UIScaleOption.allCases, id: \.self) { option in
                        let isHovered = hoveredUIScaleOption == option
                        let isOtherHovered = hoveredUIScaleOption != nil && !isHovered
                        
                        UniversalPillGliderItem(
                            item: option,
                            title: "\(option.rawValue) (\(option.percentageLabel))",
                            icon: state.uiScale == option ? "checkmark" : (option == .small ? "arrow.down.right.and.arrow.up.left" : (option == .large ? "arrow.up.left.and.arrow.down.right" : "rectangle.center.inset.filled")),
                            isSelected: state.uiScale == option,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor,
                            namespace: uiScaleGliderNamespace,
                            gliderId: "UIScaleGlider"
                        ) {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                                state.uiScale = option
                            }
                        }
                        .scaleEffect(isHovered ? 1.015 : 1.0)
                        .opacity(isOtherHovered ? 0.88 : 1.0)
                        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hoveredUIScaleOption)
                        .onHover { hovering in
                            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                                if hovering {
                                    hoveredUIScaleOption = option
                                } else if hoveredUIScaleOption == option {
                                    hoveredUIScaleOption = nil
                                }
                            }
                        }
                    }
                }
                
                Text(state.uiScale.description)
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Apple Minimalist Theme Accent Color Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Theme Accent Color", systemImage: "paintpalette.fill")
                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.accentTheme == .custom ? "#\(state.customAccentHex)" : state.accentTheme.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                // Native macOS Style Swatch Circles
                HStack(spacing: 8) {
                    ForEach(AccentColorTheme.allCases, id: \.self) { theme in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                state.accentTheme = theme
                            }
                            if theme != .custom {
                                CustomColorPanelManager.shared.close()
                            }
                        } label: {
                            ZStack {
                                if theme == .custom {
                                    // Angular rainbow gradient colorwheel circle with live center pip
                                    ZStack {
                                        AngularGradient(
                                            gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .pink, .red]),
                                            center: .center
                                        )
                                        .clipShape(Circle())
                                        .frame(width: 22, height: 22)
                                        
                                        // Center preview orb of current custom color
                                        Circle()
                                            .fill(state.accentColor)
                                            .frame(width: 10, height: 10)
                                            .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 0.5))
                                    }
                                } else {
                                    Circle()
                                        .fill(themeColor(for: theme))
                                        .frame(width: 22, height: 22)
                                }
                                
                                // Selected Ring
                                if state.accentTheme == theme {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                        .frame(width: 28, height: 28)
                                        .shadow(color: Color.black.opacity(0.3), radius: 2)
                                }
                            }
                            .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .help(theme == .custom ? "Custom Color Wheel & Spectrum" : "\(theme.rawValue) Accent")
                    }
                }
                .padding(.vertical, 2)
                
                // Custom HEX Color Tab (Expands when Custom Color Wheel is active)
                if state.accentTheme == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider().opacity(0.15)
                        
                        HStack(spacing: 8) {
                            Text("HEX Code")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 3) {
                                Text("#")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                TextField("007AFF", text: Binding(
                                    get: { state.customAccentHex },
                                    set: { newHex in
                                        let filtered = newHex.filter { "0123456789abcdefABCDEF".contains($0) }.prefix(6)
                                        state.customAccentHex = String(filtered).uppercased()
                                    }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .frame(width: 65)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(state.accentColor.opacity(0.4), lineWidth: 0.75)
                                    )
                            )
                            
                            // Anchored Color Wheel Button (Opens Color Wheel right under button)
                            Button {
                                CustomColorPanelManager.shared.toggle(initialColor: state.accentColor)
                            } label: {
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(state.accentColor)
                                        .frame(width: 22, height: 16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.75)
                                        )
                                        .shadow(color: Color.black.opacity(0.2), radius: 2)
                                    
                                    Image(systemName: "paintpalette")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Open Anchored Color Wheel")
                            
                            // Screen Eyedropper Loupe Button
                            if #available(macOS 10.15, *) {
                                Button {
                                    NSColorSampler().show { selectedColor in
                                        guard let selectedColor = selectedColor,
                                              let srgb = selectedColor.usingColorSpace(.sRGB) else { return }
                                        Task { @MainActor in
                                            let r = Int(round(srgb.redComponent * 255))
                                            let g = Int(round(srgb.greenComponent * 255))
                                            let b = Int(round(srgb.blueComponent * 255))
                                            let hex = String(format: "%02X%02X%02X", r, g, b)
                                            withAnimation(.spring(response: 0.2)) {
                                                state.customAccentHex = hex
                                                state.accentTheme = .custom
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "eyedropper.halffull")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 22, height: 22)
                                        .background(
                                            Circle()
                                                .fill(Color.white.opacity(0.06))
                                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Pick color from screen")
                            }
                            
                            Spacer()
                            
                            // Quick Popular Hex Swatches
                            HStack(spacing: 4) {
                                ForEach(["FF2D55", "5856D6", "00C7BE", "30D158", "FF9500"], id: \.self) { quickHex in
                                    Button {
                                        withAnimation(.spring(response: 0.25)) {
                                            state.customAccentHex = quickHex
                                        }
                                    } label: {
                                        Circle()
                                            .fill(AppState.colorFromHex(quickHex) ?? .blue)
                                            .frame(width: 14, height: 14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Text("Personalize highlight colors, buttons, active toggles, and glow indicators.")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Menu Bar Display Style Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Menu Bar Display Style", systemImage: "menubar.rectangle")
                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.menuBarDisplayStyle.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                HStack(spacing: 6) {
                    ForEach(MenuBarDisplayStyle.allCases, id: \.self) { style in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                state.menuBarDisplayStyle = style
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: style.iconName)
                                    .font(.system(size: 9))
                                Text(style.rawValue)
                                    .font(.system(size: 9.5, weight: state.menuBarDisplayStyle == style ? .semibold : .regular))
                            }
                            .foregroundColor(state.menuBarDisplayStyle == style ? state.contrastTextColor : .primary.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    if state.menuBarDisplayStyle == style {
                                        Capsule()
                                            .fill(state.accentColor)
                                            .shadow(color: state.accentColor.opacity(0.35), radius: 4, y: 1)
                                    } else {
                                        Capsule()
                                            .fill(Color.white.opacity(0.05))
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Text(state.menuBarDisplayStyle == .liveSavings ? "Shows real-time cumulative disk space savings next to your menu bar icon." : (state.menuBarDisplayStyle == .minimalMonochrome ? "Displays an ultra-clean minimalist monochrome indicator on your top bar." : "Standard animated clamp icon with drop-zone expansion."))
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            
            // Completion Sound Effects Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Completion Soundpack", systemImage: "speaker.wave.3.fill")
                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.soundTheme.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(SoundEffectTheme.allCases, id: \.self) { sound in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                state.soundTheme = sound
                            }
                            // Play preview of sound
                            NSSound(named: sound.systemSoundName)?.play()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: sound.icon)
                                    .font(.system(size: 9))
                                Text(sound.rawValue.components(separatedBy: " ").first ?? sound.rawValue)
                                    .font(.system(size: 9.5, weight: state.soundTheme == sound ? .semibold : .regular))
                            }
                            .foregroundColor(state.soundTheme == sound ? state.contrastTextColor : .primary.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4.5)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    if state.soundTheme == sound {
                                        Capsule()
                                            .fill(state.accentColor)
                                            .shadow(color: state.accentColor.opacity(0.35), radius: 4, y: 1)
                                    } else {
                                        Capsule()
                                            .fill(Color.white.opacity(0.05))
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Text("Plays dynamic audio feedback upon completing batch or single file squeezes.")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            
            // Watch Folder Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Auto-Squeeze Watch Folder", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                    Spacer()
                    Button {
                        let enabled = !state.isWatchFolderEnabled
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            state.isWatchFolderEnabled = enabled
                        }
                    } label: {
                        LiquidGlassSwitch(isOn: $state.isWatchFolderEnabled)
                    }
                    .buttonStyle(.plain)
                    .onChange(of: state.isWatchFolderEnabled) { _, enabled in
                        if enabled, let path = state.watchFolderPath {
                            FolderWatchService.shared.startMonitoring(path: path)
                        } else {
                            FolderWatchService.shared.stopMonitoring()
                        }
                    }
                }
                
                if let path = state.watchFolderPath {
                    Text(path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Button {
                    selectWatchFolder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(state.watchFolderPath == nil ? "Select Folder to Watch..." : "Change Watch Folder...")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                
                Text("Monitors folder and automatically compresses any new image, video, or audio file dropped in.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            
            // Output Directory & Suffix Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Save Destination", systemImage: "folder")
                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                    Spacer()
                    Text(state.customOutputFolder != nil ? "Custom Directory" : (state.exportToSubfolder ? "Automatic Subfolder" : "Next to Original"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(state.accentColor)
                }
                
                // Mode Switcher: Next to Original vs Auto Subfolder vs Custom Folder
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            state.exportToSubfolder.toggle()
                        }
                    } label: {
                        HStack(alignment: .center) {
                            Text("Create Subfolder for Compressed Files")
                                .font(.system(size: 10))
                                .foregroundColor(.primary)
                            Spacer()
                            LiquidGlassSwitch(isOn: $state.exportToSubfolder)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if state.exportToSubfolder {
                        HStack(spacing: 6) {
                            Text("Subfolder Name:")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                            
                            TextField("Squeezed", text: $state.subfolderName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                                .font(.system(size: 10, design: .monospaced))
                            
                            Text("(e.g. ./Squeezed/)")
                                .font(.system(size: 8.5))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .padding(.leading, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 2)
                
                Divider().opacity(0.15)
                
                // Specific Custom Directory Override
                VStack(alignment: .leading, spacing: 4) {
                    Text("Or specify a fixed Global Output Directory:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    if let customFolder = state.customOutputFolder {
                        Text(customFolder)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        Button {
                            let openPanel = NSOpenPanel()
                            openPanel.canChooseFiles = false
                            openPanel.canChooseDirectories = true
                            openPanel.allowsMultipleSelection = false
                            openPanel.canCreateDirectories = true
                            openPanel.prompt = "Select Output Folder"
                            if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                                state.customOutputFolder = selectedURL.path
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 9))
                                Text(state.customOutputFolder == nil ? "Choose Fixed Folder..." : "Change Folder...")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        
                        if state.customOutputFolder != nil {
                            Button {
                                state.customOutputFolder = nil
                            } label: {
                                Text("Clear")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color.red.opacity(0.88))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider().opacity(0.15).padding(.vertical, 2)
                
                HStack {
                    Text("Output File Suffix")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    TextField("_min", text: $state.outputSuffix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                Divider().opacity(0.2)
                
                // MARK: - DropBall Desktop Widget Section
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            state.floatingBallEnabled.toggle()
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text("DropBall")
                                        .font(.system(size: 10.5, weight: .bold, design: .serif))
                                        .foregroundColor(.primary)
                                    
                                    Text("EDGE-DOCK")
                                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                        .foregroundColor(state.accentColor)
                                        .padding(.horizontal, 3.5)
                                        .padding(.vertical, 0.5)
                                        .background(Capsule().fill(state.accentColor.opacity(0.15)))
                                }
                                
                                Text("Edge-docked liquid glass drop zone for instant 1-drop compression.")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            LiquidGlassSwitch(isOn: $state.floatingBallEnabled)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Optimization & Animation Dynamics Glider (Calm / Standard / Exaggerated)
                    if state.floatingBallEnabled {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("BOUNCE DYNAMICS")
                                    .font(.system(size: 8, weight: .bold, design: .serif))
                                    .foregroundColor(.secondary.opacity(0.8))
                                
                                Spacer()
                                
                                Text(state.dropBallAnimationStyle.description)
                                    .font(.system(size: 7.5))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                            }
                            
                            HStack(spacing: 4) {
                                ForEach(DropBallAnimationStyle.allCases) { style in
                                    let isSelected = state.dropBallAnimationStyle == style
                                    let isHovered = hoveredDropBallAnimStyle == style
                                    
                                    Button {
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                            state.dropBallAnimationStyle = style
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: style.icon)
                                                .font(.system(size: 8.5, weight: isSelected ? .bold : .medium))
                                            Text(style.rawValue)
                                                .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .foregroundColor(isSelected ? state.contrastTextColor : .secondary)
                                        .background(
                                            ZStack {
                                                if isSelected {
                                                    Capsule()
                                                        .fill(state.accentColor)
                                                        .matchedGeometryEffect(id: "dropBallAnimGlider", in: dropBallGliderNamespace)
                                                        .shadow(color: state.accentColor.opacity(0.35), radius: 3)
                                                } else {
                                                    Capsule()
                                                        .fill(Color.white.opacity(0.04))
                                                }
                                            }
                                        )
                                        .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .scaleEffect(isHovered ? 1.02 : 1.0)
                                    .onHover { hovering in
                                        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.85)) {
                                            if hovering {
                                                hoveredDropBallAnimStyle = style
                                            } else if hoveredDropBallAnimStyle == style {
                                                hoveredDropBallAnimStyle = nil
                                            }
                                        }
                                    }
                                    .help(style.description)
                                }
                            }
                            .padding(2.5)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.22))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
                            )
                            
                            // Glass Optics Template Glider (Crystal Clear / Balanced / High Contrast)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("GLASS OPTICS")
                                        .font(.system(size: 8, weight: .bold, design: .serif))
                                        .foregroundColor(.secondary.opacity(0.8))
                                    
                                    Spacer()
                                    
                                    Text(state.dropBallGlassStyle.description)
                                        .font(.system(size: 7.5))
                                        .foregroundColor(.secondary.opacity(0.7))
                                        .lineLimit(1)
                                }
                                
                                HStack(spacing: 4) {
                                    ForEach(DropBallGlassStyle.allCases) { style in
                                        let isSelected = state.dropBallGlassStyle == style
                                        let isHovered = hoveredDropBallGlassStyle == style
                                        
                                        Button {
                                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                                state.dropBallGlassStyle = style
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: style.icon)
                                                    .font(.system(size: 8.5, weight: isSelected ? .bold : .medium))
                                                Text(style.rawValue)
                                                    .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 5)
                                            .foregroundColor(isSelected ? state.contrastTextColor : .secondary)
                                            .background(
                                                ZStack {
                                                    if isSelected {
                                                        Capsule()
                                                            .fill(state.accentColor)
                                                            .matchedGeometryEffect(id: "dropBallGlassGlider", in: dropBallGlassGliderNamespace)
                                                            .shadow(color: state.accentColor.opacity(0.35), radius: 3)
                                                    } else {
                                                        Capsule()
                                                            .fill(Color.white.opacity(0.04))
                                                    }
                                                }
                                            )
                                            .contentShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .scaleEffect(isHovered ? 1.02 : 1.0)
                                        .onHover { hovering in
                                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.85)) {
                                                if hovering {
                                                    hoveredDropBallGlassStyle = style
                                                } else if hoveredDropBallGlassStyle == style {
                                                    hoveredDropBallGlassStyle = nil
                                                }
                                            }
                                        }
                                        .help(style.description)
                                    }
                                }
                                .padding(2.5)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.22))
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
                                )
                            }
                            .padding(.top, 2)
                        }
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                Divider().opacity(0.2)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        state.setLaunchAtLogin(enabled: !state.launchAtLogin)
                    }
                } label: {
                    HStack(alignment: .center) {
                        Text("Launch at System Startup")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Spacer()
                        LiquidGlassSwitch(isOn: $state.launchAtLogin)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        state.finderServiceEnabled.toggle()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 5) {
                        Text("Finder Right-Click Quick Action")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        
                        Text("BETA")
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundColor(state.accentColor)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(state.accentColor.opacity(0.15)))
                        
                        Spacer()
                        LiquidGlassSwitch(isOn: $state.finderServiceEnabled)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        state.stripMetadata.toggle()
                    }
                } label: {
                    HStack(alignment: .center) {
                        Text("Strip EXIF / Metadata")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Spacer()
                        LiquidGlassSwitch(isOn: $state.stripMetadata)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        state.soundEnabled.toggle()
                    }
                } label: {
                    HStack(alignment: .center) {
                        Text("Sound Chime on Completion")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Spacer()
                        LiquidGlassSwitch(isOn: $state.soundEnabled)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        state.hapticEnabled.toggle()
                    }
                } label: {
                    HStack(alignment: .center) {
                        Text("Haptic Feedback on Completion")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Spacer()
                        LiquidGlassSwitch(isOn: $state.hapticEnabled)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button {
                    OnboardingWindowController.shared.show(forceReplay: true)
                } label: {
                    HStack(alignment: .center) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 10))
                            .foregroundColor(state.accentColor)
                        Text("Replay Welcome Tour & Setup")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button("Reset All Compression Stats") {
                    state.resetAllStats()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.red.opacity(0.80))
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
    }
    
    private func selectWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Watch Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            state.watchFolderPath = url.path
            state.isWatchFolderEnabled = true
            FolderWatchService.shared.startMonitoring(path: url.path)
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Text("SqueezeBar v1.0.0 • SirJameTV")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
    
    private func themeColor(for theme: AccentColorTheme) -> Color {
        switch theme {
        case .custom:
            return state.accentColor
        case .blue:
            return Color(red: 0.1, green: 0.5, blue: 1.0)
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
}

// MARK: - AppKit Visual Effect Background Helper
public struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - File Thumbnail View
public struct FileThumbnailView: View {
    let url: URL
    let mediaType: MediaType
    var size: CGFloat = 28
    
    @State private var thumbnail: NSImage?
    
    public init(url: URL, mediaType: MediaType, size: CGFloat = 28) {
        self.url = url
        self.mediaType = mediaType
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                // Frosted Glass Media Placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: mediaIconName)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundColor(mediaIconColor)
                    )
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            await loadThumbnail()
        }
    }
    
    private var mediaIconName: String {
        switch mediaType {
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.text.fill"
        case .image: return "photo"
        case .unsupported: return "doc.fill"
        }
    }
    
    private var mediaIconColor: Color {
        return .secondary.opacity(0.85)
    }
    
    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.image(for: url) {
            self.thumbnail = cached
            return
        }
        
        let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let maxPixelSize = Int(size * 3.0)
            
            // 1. Direct ImageIO Thumbnail for Images (Ultra-fast, hardware accelerated)
            let ext = url.pathExtension.lowercased()
            if mediaType == .image || ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp", "avif"].contains(ext) {
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                    ]
                    if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                        return NSImage(cgImage: cgThumb, size: CGSize(width: size, height: size))
                    }
                }
                if let directImg = NSImage(contentsOf: url) {
                    return directImg
                }
            }
            
            // 2. AVAsset Video Frame Thumbnail
            if mediaType == .video || ["mp4", "mov", "m4v", "mkv", "avi"].contains(ext) {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    return NSImage(cgImage: cgImage, size: CGSize(width: size, height: size))
                }
            }
            
            // 3. PDF Kit Thumbnail
            if mediaType == .pdf || ext == "pdf" {
                if let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
                    return page.thumbnail(of: CGSize(width: size * 2, height: size * 2), for: .mediaBox)
                }
            }
            
            // 4. QuickLook Thumbnail Generator
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: size * 2, height: size * 2),
                scale: 2.0,
                representationTypes: .thumbnail
            )
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                return representation.nsImage
            }
            
            return nil
        }.value
        
        if let loaded = loaded {
            ThumbnailCache.shared.setImage(loaded, for: url)
            self.thumbnail = loaded
        }
    }
}

// MARK: - Thumbnail Cache
private final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()
    
    private init() {
        cache.countLimit = 150
    }
    
    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }
    
    func setImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

// MARK: - Premium Liquid Glass Toggle Row
private struct LiquidGlassToggleRow: View {
    @EnvironmentObject var state: AppState
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                isOn.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                // Left text block
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 9.5))
                            .foregroundColor(isOn ? state.accentColor : .secondary)
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 8)
                
                // Right Liquid Glass Toggle Switch
                LiquidGlassSwitch(isOn: $isOn)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isOn ? state.accentColor.opacity(0.06) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isOn ? state.accentColor.opacity(0.18) : Color.white.opacity(0.04), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liquid Glass Switch
public struct LiquidGlassSwitch: View {
    @EnvironmentObject var state: AppState
    @Binding var isOn: Bool
    
    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }
    
    public var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            // Track Capsule with Glassmorphism
            Capsule()
                .fill(
                    isOn ?
                    LinearGradient(
                        colors: [state.accentColor.opacity(0.95), state.accentColor.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 21)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isOn ?
                            LinearGradient(colors: [Color.white.opacity(0.5), state.accentColor.opacity(0.3)], startPoint: .top, endPoint: .bottom) :
                            LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: isOn ? state.accentColor.opacity(0.4) : Color.black.opacity(0.2), radius: isOn ? 4 : 1, y: 1)
            
            // Thumb Orb with Frosted Glass Reflection & Shadow
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(white: 0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 17, height: 17)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 2.5, x: isOn ? -1 : 1, y: 1)
                .padding(2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                isOn.toggle()
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isOn)
    }
}

// MARK: - Proximity Glow Container & Interactive Tile with Seamless Cursor Falloff
private struct ProximityGlowContainer<Content: View>: View {
    let content: Content
    @State private var cursorPosition: CGPoint = .zero
    @State private var isCursorNearby: Bool = false
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(1)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                withAnimation(.linear(duration: 0.04)) {
                                    cursorPosition = loc
                                    isCursorNearby = true
                                }
                            case .ended:
                                withAnimation(.easeOut(duration: 0.35)) {
                                    isCursorNearby = false
                                }
                            }
                        }
                }
            )
    }
}

// MARK: - Interactive Cursor-Following Glow & Light Leak Tile
private struct InteractiveGlowTile: View {
    let title: String
    let value: String
    let badge: String?
    let icon: String
    let accentColor: Color
    
    @State private var isHovered = false
    @State private var mouseLocation: CGPoint = .zero
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5))
                    .foregroundColor(accentColor)
                
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold, design: .default))
                    .foregroundColor(.secondary.opacity(0.85))
                
                Spacer(minLength: 0)
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(accentColor.opacity(0.12)))
                }
            }
            
            // Editorial Serif Value
            Text(value)
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                // Base Glass Slab
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isHovered ? 0.085 : 0.055), Color.white.opacity(isHovered ? 0.03 : 0.015)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Cursor-Following Light Leak / Specular Bloom (Gentle Faded White with Smooth Proximity Falloff)
                if isHovered {
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.11),
                            Color.white.opacity(0.04),
                            Color.clear
                        ]),
                        center: UnitPoint(
                            x: mouseLocation.x / 140.0,
                            y: mouseLocation.y / 60.0
                        ),
                        startRadius: 0,
                        endRadius: 95
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
                }
            }
        )
        .overlay(
            ZStack {
                // Base Specular Border
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(isHovered ? 0.26 : 0.14), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                
                // Cursor-Following Border Glint (Subtle Faded White Light Leak)
                if isHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.42),
                                    Color.white.opacity(0.10),
                                    Color.clear
                                ]),
                                center: UnitPoint(
                                    x: mouseLocation.x / 140.0,
                                    y: mouseLocation.y / 60.0
                                ),
                                startRadius: 0,
                                endRadius: 75
                            ),
                            lineWidth: 0.75
                        )
                }
            }
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.25 : 0.12),
            radius: isHovered ? 5 : 2,
            y: 1.5
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                withAnimation(.linear(duration: 0.04)) {
                    mouseLocation = location
                    isHovered = true
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.32)) {
                    isHovered = false
                }
            }
        }
    }
}

// MARK: - Live Profile Glow Card with Specular Shine & Proximity Light Leak
private struct LiveProfileGlowCard<Content: View>: View {
    let accentColor: Color
    var isSelected: Bool = false
    @ViewBuilder let content: () -> Content
    
    @State private var isHovered = false
    @State private var mouseLocation: CGPoint = .zero
    
    var body: some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    // Base Frosted Glass Slab
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isSelected ?
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.18),
                                    accentColor.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.08 : 0.04),
                                    Color.white.opacity(isHovered ? 0.03 : 0.015)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Pure White Cursor-Following Light Leak / Specular Bloom (Identical to Size Glider)
                    if isHovered {
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.04),
                                Color.clear
                            ]),
                            center: UnitPoint(
                                x: mouseLocation.x / 130.0,
                                y: mouseLocation.y / 55.0
                            ),
                            startRadius: 1,
                            endRadius: 75
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity)
                    }
                }
            )
            .overlay(
                ZStack {
                    // Base Specular Border
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(accentColor.opacity(0.85), lineWidth: 1.25)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.28 : 0.12),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.65
                            )
                    }
                    
                    // Pure White Dynamic Border Glint on Hover
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0.15),
                                        Color.clear
                                    ]),
                                    center: UnitPoint(
                                        x: mouseLocation.x / 130.0,
                                        y: mouseLocation.y / 55.0
                                    ),
                                    startRadius: 1,
                                    endRadius: 50
                                ),
                                lineWidth: 0.85
                            )
                    }
                }
            )
            .shadow(
                color: isSelected ? accentColor.opacity(0.28) : Color.black.opacity(isHovered ? 0.22 : 0.08),
                radius: isSelected ? 5 : (isHovered ? 4 : 1.5),
                y: 1
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    withAnimation(.linear(duration: 0.04)) {
                        mouseLocation = location
                        isHovered = true
                    }
                case .ended:
                    withAnimation(.easeOut(duration: 0.28)) {
                        isHovered = false
                    }
                }
            }
    }
}

// MARK: - AppKit Non-Draggable View (Prevents window drag during slider scrub)
private struct NonDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NonDraggableNSView {
        NonDraggableNSView()
    }
    
    func updateNSView(_ nsView: NonDraggableNSView, context: Context) {}
}

private final class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
}

// MARK: - Modern Liquid Glass Slider with Subtle White Specular Dynamics
private struct LiquidGlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let accentColor: Color
    
    @State private var isDragging: Bool = false
    @State private var isHovered: Bool = false
    @State private var dragVelocity: CGFloat = 0.0
    @State private var lastLocationX: CGFloat = 0.0
    @State private var lastDragTimestamp: Date = Date()
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = max(1, geometry.size.width)
            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            let percentage = CGFloat((clampedValue - range.lowerBound) / (range.upperBound - range.lowerBound))
            let fillWidth = max(0, min(totalWidth, totalWidth * percentage))
            let thumbSize: CGFloat = isDragging ? 14 : (isHovered ? 12.5 : 11)
            let thumbCenter = max(thumbSize / 2, min(totalWidth - thumbSize / 2, fillWidth))
            
            let whiteGlowRadius: CGFloat = 4.0 + (dragVelocity * 6.0)
            let whiteGlowOpacity: Double = 0.20 + Double(dragVelocity * 0.25)
            
            ZStack(alignment: .leading) {
                // Non-Draggable AppKit Anchor (Prevents Window Drag in Detached Mode)
                NonDraggableArea()
                
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.09))
                    .frame(height: 6)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                
                // Active Filled Track with Accent Gradient
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.85), accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: 6)
                    .shadow(color: accentColor.opacity(0.20), radius: 2)
                
                // Subtle Neutral White Specular Aura Bloom on Hold / Velocity Scrub
                if isDragging {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(whiteGlowOpacity),
                                    Color.white.opacity(whiteGlowOpacity * 0.35),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 1,
                                endRadius: thumbSize * 1.1 + (dragVelocity * 5.0)
                            )
                        )
                        .frame(width: 32 + (dragVelocity * 10), height: 32 + (dragVelocity * 10))
                        .offset(x: thumbCenter - (16 + (dragVelocity * 5)))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                
                // Frosted Thumb Indicator with Subtle Neutral Specular Glow
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isDragging ? 0.95 : 0.40), lineWidth: isDragging ? 1.2 : 0.8)
                    )
                    .shadow(
                        color: Color.black.opacity(isDragging ? 0.25 : 0.20),
                        radius: isDragging ? 2.5 : 1.5,
                        y: 1
                    )
                    .shadow(
                        color: isDragging ? Color.white.opacity(whiteGlowOpacity * 0.90) : (isHovered ? Color.white.opacity(0.12) : Color.clear),
                        radius: isDragging ? whiteGlowRadius : 2,
                        y: 0
                    )
                    .scaleEffect(isDragging ? (1.10 + dragVelocity * 0.08) : (isHovered ? 1.05 : 1.0))
                    .offset(x: max(0, min(totalWidth - thumbSize, fillWidth - (thumbSize / 2))))
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .background(NonDraggableArea())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let locationX = gesture.location.x
                        let now = Date()
                        let timeDelta = max(0.008, now.timeIntervalSince(lastDragTimestamp))
                        
                        if isDragging {
                            let distance = abs(locationX - lastLocationX)
                            let instantVelocity = distance / CGFloat(timeDelta)
                            let normalizedSpeed = min(1.0, instantVelocity / 850.0)
                            withAnimation(.easeOut(duration: 0.08)) {
                                dragVelocity = dragVelocity * 0.35 + normalizedSpeed * 0.65
                            }
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                isDragging = true
                                dragVelocity = 0.15
                            }
                        }
                        
                        lastLocationX = locationX
                        lastDragTimestamp = now
                        
                        let newPct = max(0.0, min(1.0, Double(locationX / totalWidth)))
                        var newValue = range.lowerBound + newPct * (range.upperBound - range.lowerBound)
                        if let step = step, step > 0 {
                            newValue = (newValue / step).rounded() * step
                        }
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                            isDragging = false
                            dragVelocity = 0.0
                        }
                    }
            )
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    isHovered = hovering
                }
            }
        }
        .frame(height: 18)
    }
}

// MARK: - Generic Universal Pill Glider with Sliding Animation & Cursor Glow
private struct UniversalPillGliderItem<T: Equatable>: View {
    let item: T
    let title: String
    let icon: String?
    let isSelected: Bool
    let accentColor: Color
    let contrastTextColor: Color
    let namespace: Namespace.ID
    let gliderId: String
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var mouseLocation: CGPoint = .zero
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? contrastTextColor : (isHovered ? .white : .primary.opacity(0.85)))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 26)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.95), accentColor.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .matchedGeometryEffect(id: gliderId, in: namespace)
                            .shadow(color: accentColor.opacity(0.38), radius: 5, y: 1.5)
                    } else {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isHovered ? 0.12 : 0.08), Color.white.opacity(isHovered ? 0.05 : 0.03)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    // Subtle Faded White Cursor Light Leak
                    if isHovered && !isSelected {
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.04),
                                Color.clear
                            ]),
                            center: UnitPoint(
                                x: mouseLocation.x / 65.0,
                                y: mouseLocation.y / 24.0
                            ),
                            startRadius: 1,
                            endRadius: 35
                        )
                        .clipShape(Capsule())
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                ZStack {
                    if isSelected {
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.6), lineWidth: 0.5)
                    } else {
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(isHovered ? 0.28 : 0.10), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                    
                    if isHovered && !isSelected {
                        Capsule()
                            .strokeBorder(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.40),
                                        Color.white.opacity(0.10),
                                        Color.clear
                                    ]),
                                    center: UnitPoint(
                                        x: mouseLocation.x / 65.0,
                                        y: mouseLocation.y / 24.0
                                    ),
                                    startRadius: 1,
                                    endRadius: 30
                                ),
                                lineWidth: 0.75
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                withAnimation(.linear(duration: 0.05)) {
                    mouseLocation = location
                    isHovered = true
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.25)) {
                    isHovered = false
                }
            }
        }
    }
}

// MARK: - Interactive Preset Pill with Sliding Glider & Cursor Light Leak
private struct InteractivePresetPill: View {
    let mode: TargetSizeMode
    let isSelected: Bool
    let accentColor: Color
    let contrastTextColor: Color
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        UniversalPillGliderItem(
            item: mode,
            title: mode == .off ? "Manual" : (mode == .custom ? "Custom" : (mode.targetMegabytes.map { "\(Int($0))MB" } ?? mode.rawValue)),
            icon: isSelected ? "checkmark" : nil,
            isSelected: isSelected,
            accentColor: accentColor,
            contrastTextColor: contrastTextColor,
            namespace: namespace,
            gliderId: "ActivePresetGlider",
            action: action
        )
    }
}

// MARK: - Dedicated Folder Section Item View with Drag & Drop Targeting & Inline Customization
private struct FolderSectionItemView: View {
    @EnvironmentObject var state: AppState
    let folder: CompressionFolder
    let isEditMode: Bool
    @Binding var selectedResultIds: Set<UUID>
    
    @State private var isFolderDropTargeted: Bool = false
    @State private var isEditingName: Bool = false
    @State private var editedName: String = ""
    @State private var showColorPicker: Bool = false
    
    private var effectiveFolderColor: Color {
        if let hex = folder.colorHex, !hex.isEmpty {
            return AppState.colorFromHex(hex) ?? state.accentColor
        }
        return state.accentColor
    }
    
    var body: some View {
        let itemsInFolder = state.recentResults.filter { $0.folderId == folder.id }
        let totalFolderSavedBytes = itemsInFolder.reduce(0) { $0 + max(0, $1.originalSize - $1.compressedSize) }
        let formattedFolderSaved = ByteCountFormatter.string(fromByteCount: totalFolderSavedBytes, countStyle: .file)
        
        VStack(alignment: .leading, spacing: 6) {
            // Folder Header
            HStack(spacing: 6) {
                // Collapse Chevron
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                        state.toggleFolderCollapse(id: folder.id)
                    }
                } label: {
                    Image(systemName: folder.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Folder Icon (Double Click to Change Folder Color)
                Image(systemName: isFolderDropTargeted ? "folder.badge.plus" : folder.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isFolderDropTargeted ? .green : effectiveFolderColor)
                    .scaleEffect(isFolderDropTargeted ? 1.2 : 1.0)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        showColorPicker = true
                    }
                    .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                        folderColorPaletteView
                    }
                    .help("Double-click to change folder color")
                
                // Folder Name (Double Click to Inline Edit)
                if isEditingName {
                    TextField("Folder Name", text: $editedName, onCommit: {
                        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            state.renameFolder(id: folder.id, newName: trimmed)
                        }
                        isEditingName = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
                    .frame(maxWidth: 140)
                } else {
                    Text(folder.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            editedName = folder.name
                            isEditingName = true
                        }
                        .help("Double-click to rename folder")
                }
                
                // Folder item count & space saved badge
                HStack(spacing: 3) {
                    Text("(\(itemsInFolder.count))")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    
                    if totalFolderSavedBytes > 0 {
                        Text("• -\(formattedFolderSaved)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green.opacity(0.9))
                    }
                }
                
                if isFolderDropTargeted {
                    Text("Drop to Add")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                }
                
                Spacer()
                
                if isEditMode {
                    Button("Select All") {
                        let ids = Set(itemsInFolder.map { $0.id })
                        if selectedResultIds.isSuperset(of: ids) {
                            selectedResultIds.subtract(ids)
                        } else {
                            selectedResultIds.formUnion(ids)
                        }
                    }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundColor(effectiveFolderColor)
                }
                
                // Folder Options Menu
                Menu {
                    Button("Rename Folder") {
                        editedName = folder.name
                        isEditingName = true
                    }
                    Button("Change Color") {
                        showColorPicker = true
                    }
                    Divider()
                    Button("Delete Folder") {
                        state.deleteFolder(id: folder.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFolderDropTargeted ? Color.green.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isFolderDropTargeted ? Color.green.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
            
            // Folder Contents (Collapsible)
            if !folder.isCollapsed {
                if itemsInFolder.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: isFolderDropTargeted ? "arrow.down.doc.fill" : "plus.square.dashed")
                            .font(.system(size: 14))
                            .foregroundColor(isFolderDropTargeted ? .green : effectiveFolderColor.opacity(0.6))
                        
                        Text(isFolderDropTargeted ? "Release to drop into \(folder.name)" : "Drop files here or use 'Move' in Edit mode")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(isFolderDropTargeted ? .green : .secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isFolderDropTargeted ? Color.green.opacity(0.08) : Color.white.opacity(0.015))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        isFolderDropTargeted ? Color.green.opacity(0.5) : effectiveFolderColor.opacity(0.2),
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                    )
                            )
                    )
                    .padding(.leading, 12)
                } else {
                    HStack(spacing: 6) {
                        // Vertical hierarchy tree line
                        Rectangle()
                            .fill(effectiveFolderColor.opacity(0.25))
                            .frame(width: 2)
                            .cornerRadius(1)
                            .padding(.leading, 10)
                        
                        VStack(spacing: 6) {
                            ForEach(itemsInFolder) { item in
                                QuickPopoverHistoryRowItem(
                                    item: item,
                                    isEditMode: isEditMode,
                                    selectedResultIds: $selectedResultIds
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .onDrop(of: [.fileURL], isTargeted: $isFolderDropTargeted) { providers in
            extractAndProcessFolderDrop(providers: providers, targetFolderId: folder.id)
        }
    }
    
    // MARK: - Folder Color Palette Popover (Matches Settings Theme Tab)
    private var folderColorPaletteView: some View {
        let presetThemes: [(AccentColorTheme, String, Color)] = [
            (.blue, "1A80FF", Color(red: 0.1, green: 0.5, blue: 1.0)),
            (.purple, "A652E0", Color(red: 0.65, green: 0.32, blue: 0.88)),
            (.pink, "FA5294", Color(red: 0.98, green: 0.32, blue: 0.58)),
            (.red, "F24747", Color(red: 0.95, green: 0.28, blue: 0.28)),
            (.orange, "FA8C2E", Color(red: 0.98, green: 0.55, blue: 0.18)),
            (.yellow, "FAC71F", Color(red: 0.98, green: 0.78, blue: 0.12)),
            (.green, "52D16B", Color(red: 0.32, green: 0.82, blue: 0.42)),
            (.graphite, "9499A3", Color(red: 0.58, green: 0.60, blue: 0.64))
        ]
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Folder Color")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary)
            
            HStack(spacing: 8) {
                // Default theme accent option
                Button {
                    state.updateFolderColor(id: folder.id, colorHex: nil)
                    showColorPicker = false
                } label: {
                    ZStack {
                        Circle()
                            .fill(state.accentColor)
                            .frame(width: 20, height: 20)
                        
                        if folder.colorHex == nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Default App Theme Color")
                
                // Color presets from theme palette
                ForEach(presetThemes, id: \.1) { item in
                    let hex = item.1
                    let col = item.2
                    Button {
                        state.updateFolderColor(id: folder.id, colorHex: hex)
                        showColorPicker = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(col)
                                .frame(width: 20, height: 20)
                            
                            if folder.colorHex?.uppercased() == hex.uppercased() {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.0.rawValue)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
    }
    
    private func extractAndProcessFolderDrop(providers: [NSItemProvider], targetFolderId: UUID) -> Bool {
        var collectedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    collectedURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !collectedURLs.isEmpty {
                Task {
                    await MediaCompressionEngine.shared.processDroppedURLs(collectedURLs, targetFolderId: targetFolderId)
                }
            }
        }
        return true
    }
}

// MARK: - Reusable History Row Item
private struct QuickPopoverHistoryRowItem: View {
    @EnvironmentObject var state: AppState
    let item: CompressionResult
    let isEditMode: Bool
    @Binding var selectedResultIds: Set<UUID>
    
    @State private var isHovered: Bool = false
    @State private var shimmerOffset: CGFloat = -1.2
    
    var body: some View {
        let isSelected = selectedResultIds.contains(item.id)
        
        HStack(spacing: 9) {
            if isEditMode {
                Button {
                    withAnimation(.spring(response: 0.2)) {
                        if isSelected {
                            selectedResultIds.remove(item.id)
                        } else {
                            selectedResultIds.insert(item.id)
                        }
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? state.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            FileThumbnailView(url: item.outputURL, mediaType: item.mediaType, size: 30)
            
            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.fileName)
                    .font(.system(size: 11.5, weight: .semibold, design: .serif))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 5) {
                    Text(item.formattedOriginalSize)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.8))
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(item.formattedCompressedSize)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(state.accentColor.opacity(0.95))
                }
            }
            
            Spacer(minLength: 4)
            
            // Percentage Pill
            let hasSavings = item.percentSaved > 0
            Text(hasSavings ? String(format: "-%.0f%%", item.percentSaved) : "0%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(hasSavings ? state.accentColor : .secondary)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(hasSavings ? state.accentColor.opacity(0.14) : Color.white.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(hasSavings ? state.accentColor.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
            
            // Action Buttons in Frosted Mini Glass
            HStack(spacing: 2) {
                Button {
                    InspectorWindowController.shared.show(result: item)
                } label: {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Before/After Comparison Inspector")
                
                Button {
                    state.revealInFinder(url: item.outputURL)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
        }
        .padding(9)
        .background(
            ZStack {
                NonDraggableArea()
                
                GeometryReader { cardGeo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.065 : 0.045),
                                        Color.white.opacity(isHovered ? 0.025 : 0.015)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Specular Completion Shimmer Flare
                        if shimmerOffset < 1.2 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear,
                                            state.accentColor.opacity(0.15),
                                            Color.white.opacity(0.20),
                                            state.accentColor.opacity(0.15),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .rotationEffect(.degrees(25))
                                .offset(x: cardGeo.size.width * shimmerOffset)
                        }
                    }
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? state.accentColor.opacity(0.7) :
                    (isHovered ? state.accentColor.opacity(0.3) : Color.white.opacity(0.08)),
                    lineWidth: isSelected ? 1.0 : 0.5
                )
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.2 : 0.08), radius: isHovered ? 4 : 2, y: 1)
        .onHover { h in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovered = h
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75)) {
                shimmerOffset = 1.4
            }
        }
        .onDrag {
            NSItemProvider(object: item.outputURL as NSURL)
        }
    }
}

// MARK: - Supporter Action Button (with Subtle Hover Glow)
private struct SupporterActionButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isHovered ? .white : .white.opacity(0.95))
                    .shadow(color: Color.white.opacity(isHovered ? 0.6 : 0.0), radius: isHovered ? 4 : 0)
                
                Text("Support")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: Color.white.opacity(isHovered ? 0.55 : 0.0), radius: isHovered ? 5 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8.5)
            .background(
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    isHovered ? Color.orange.opacity(0.95) : Color.orange,
                                    isHovered ? Color(red: 0.95, green: 0.45, blue: 0.12) : Color.orange.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    if isHovered {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                    }
                }
                .shadow(color: Color.orange.opacity(isHovered ? 0.5 : 0.3), radius: isHovered ? 8 : 5, y: 2)
            )
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Staged Queue Row Item with Per-File Custom Settings
private struct StagedQueueRowItem: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var item: StagedQueueItem
    @State private var showSettingsSheet: Bool = false
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 28, height: 28)
                
                Image(systemName: iconForMediaType(item.mediaType))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(state.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 4) {
                    Text(item.formattedOriginalSize)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Text(customSettingSummary)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(state.accentColor.opacity(0.95))
                }
            }
            
            Spacer(minLength: 4)
            
            // Custom Settings Button
            Button {
                showSettingsSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("Custom")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettingsSheet, arrowEdge: .trailing) {
                QueueItemSettingsSheet(item: item)
            }
            
            // Remove Button
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    state.removeFromQueue(id: item.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            ZStack {
                NonDraggableArea()
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovered ? 0.05 : 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
            }
        )
        .onHover { h in
            isHovered = h
        }
    }
    
    private var customSettingSummary: String {
        var parts: [String] = []
        if item.customTargetSizeMode != .off {
            if let mb = item.customTargetSizeMode.targetMegabytes {
                parts.append("\(Int(mb))MB Limit")
            }
        }
        parts.append("\(Int(item.customQuality * 100))% Q")
        if item.customResolutionScale < 0.99 {
            parts.append("\(Int(item.customResolutionScale * 100))% Scale")
        }
        return parts.joined(separator: " • ")
    }
    
    private func iconForMediaType(_ type: MediaType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.text.fill"
        case .unsupported: return "doc"
        }
    }
}


