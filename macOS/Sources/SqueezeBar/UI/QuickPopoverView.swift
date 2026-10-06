import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import ImageIO
import AVFoundation
import PDFKit

private func loadDroppedFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let lock = NSLock()
    let group = DispatchGroup()

    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            let url = item as? URL ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let url, url.isFileURL else { return }
            lock.lock()
            urls.append(url)
            lock.unlock()
        }
    }

    group.notify(queue: .main) {
        completion(urls)
    }
}

public struct QuickPopoverView: View {
    @EnvironmentObject var state: AppState
    public var isDetachedWindow: Bool = false
    @State private var selectedTab: PopoverTab = .activity
    @State private var isWindowDropTargeted: Bool = false
    @State private var isGlassSettingsExpanded = true
    @State private var isAppearanceExpanded = false
    @State private var activeFormatCategory: MediaFormatCategory = .images
    @State private var isFormatDrawerExpanded: Bool = false
    
    // Project Folders & Batch Edit State
    @State private var isEditMode: Bool = false
    @State private var selectedResultIds: Set<UUID> = []
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var isBatchRenaming: Bool = false
    @State private var renamePattern: String = ""
    @State private var showClearConfirmation: Bool = false
    
    // Liquid Glass Collective Hover States (Apple-like Focus Bounce)
    @State private var hoveredTab: PopoverTab? = nil
    @State private var hoveredTargetLimitMode: TargetSizeMode? = nil
    @State private var hoveredUIScaleOption: UIScaleOption? = nil
    @State private var soundThemeLiquidDirection = PillLiquidDirection.leadingToTrailing
    
    enum PopoverTab: String, CaseIterable {
        case activity = "Activity"
        case settings = "Settings"
    }
    
    enum MediaFormatCategory: String, CaseIterable {
        case images = "Images"
        case videos = "Video"
        case audio = "Audio"
        case pdf = "PDF"
        
        var displayName: String {
            switch self {
            case .images: return String(localized: "Images")
            case .videos: return String(localized: "Video")
            case .audio: return String(localized: "Audio")
            case .pdf: return "PDF"
            }
        }
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
            
            ZStack(alignment: .topLeading) {
                LiquidGlassHoverField()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                innerMainContent
                    .frame(width: contentWidth, height: contentHeight)
                    .scaleEffect(scale, anchor: .topLeading)
            }
        }
        .frame(minWidth: state.uiScale.baseWidth - 20, maxWidth: .infinity, minHeight: state.uiScale.baseHeight - 40, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(1 - state.appTransparency))
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0)
                    .fill(Color.black.opacity(0.35 * state.appTransparency))
                    .allowsHitTesting(false)

                if state.appGlassFrost > 0 {
                    RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0)
                        .fill(.ultraThinMaterial)
                        .opacity(state.appGlassFrost)
                        .allowsHitTesting(false)
                }

                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(.clear.tint(Color.black.opacity(0.3)), in: RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0))
                        .allowsHitTesting(false)
                }

                if state.appGlassDepth > 0 {
                    RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.16), .clear, .black.opacity(0.32)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .opacity(state.appGlassDepth)
                        .allowsHitTesting(false)
                }

                if isWindowDropTargeted {
                    RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0)
                        .strokeBorder(state.accentColor, lineWidth: 2.5)
                        .background(state.accentColor.opacity(0.10))
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isDetachedWindow ? 14 : 0))
        .ignoresSafeArea()
        .onDrop(of: [.fileURL], isTargeted: $isWindowDropTargeted) { providers in
            extractAndProcess(providers: providers)
        }
        .overlay(alignment: .top) {
            if isWindowDropTargeted {
                Label("Drop here", systemImage: "arrow.down.doc.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(state.accentColor, lineWidth: 1.5))
                    .padding(.top, 10)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isWindowDropTargeted)
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
        .font(.system(.body, design: .rounded))
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
                        
                        if !state.failedJobs.isEmpty {
                            failedJobsSection
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
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(0.35)
                
                Text("Universal Media Optimizer")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isDetached {
                // Circular Dock button (Only shown in detached floating window)
                Button {
                    FloatingDropWindowController.shared.dockToMenuBar()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left.square")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(state.accentColor)
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            state.cancelAllJobs()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11, design: .rounded))
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
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.green)
                    Text("Complete")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
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
    
    // MARK: - Tab Selector
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
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(isActivitySelected ? state.accentColor : .secondary.opacity(0.8))
                    Text("Activity")
                        .font(.system(size: 13, weight: isActivitySelected ? .semibold : .medium, design: .rounded))
                        .foregroundColor(isActivitySelected ? .white : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
            
            // Settings tab
            let isSettingsSelected = selectedTab == .settings
            let isSettingsHovered = hoveredTab == .settings
            
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    selectedTab = .settings
                    FloatingDropWindowController.shared.ensureMinimumDimensions(width: 490, height: 660)
                    StatusBarController.sharedInstance?.ensurePopoverDimensions(width: 490, height: 660)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSettingsSelected ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(isSettingsSelected ? state.accentColor : .secondary)
                    Text("Settings")
                        .font(.system(size: 13, weight: isSettingsSelected ? .semibold : .medium, design: .rounded))
                        .foregroundColor(isSettingsSelected ? .white : .secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Capsule())
                .background {
                    if isSettingsSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75))
                    }
                }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
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
    
    // MARK: - Live Format Selector Cards (Images, Video, Audio, PDF)
    private var statsSummaryCard: some View {
        HStack(spacing: 6) {
            profileTile(.images, icon: "photo", primary: state.imageFormatPolicy.displayName, secondary: state.imageResolutionScale < 1 ? String(localized: "\(Int(state.imageQualitySlider * 100))% · \(Int(state.imageResolutionScale * 100))% size") : String(localized: "\(Int(state.imageQualitySlider * 100))% quality"))
            profileTile(.videos, icon: "film", primary: state.videoCodec == .hevc ? "HEVC" : (state.videoCodec == .h264 ? "H.264" : "GIF"), secondary: state.videoFramerate == .original ? String(localized: "\(Int(state.videoQualitySlider * 100))% quality") : "\(state.videoFramerate.displayName) · \(Int(state.videoQualitySlider * 100))%")
            profileTile(.audio, icon: "waveform", primary: state.audioBitrate.shortName, secondary: state.stripMetadata ? String(localized: "Metadata removed") : String(localized: "Metadata kept"))
            profileTile(.pdf, icon: "doc.text.fill", primary: "\(Int(state.pdfDPI.dpiValue)) DPI", secondary: "\(Int(state.pdfImageQuality * 100))% quality\(state.pdfGrayscale ? " · Grayscale" : "")")
        }
    }

    private func profileTile(_ category: MediaFormatCategory, icon: String, primary: String, secondary: String) -> some View {
        let title = category.displayName
        let isExpanded = activeFormatCategory == category && isFormatDrawerExpanded

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isExpanded {
                    isFormatDrawerExpanded = false
                } else {
                    activeFormatCategory = category
                    isFormatDrawerExpanded = true
                }
            }
        } label: {
            LiveProfileGlowCard(accentColor: state.accentColor, isSelected: isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(isExpanded ? state.accentColor : .primary.opacity(0.85))
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(isExpanded ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundColor(isExpanded ? state.accentColor : .secondary.opacity(0.6))
                    }
                    .frame(height: 16)

                    Text(primary)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(secondary)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .help("Click to toggle \(title) compression settings")
    }
    
    // MARK: - Failed Files (kept until dismissed so errors aren't missed)
    private var failedJobsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Couldn't compress", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
                Spacer()
                Button("Dismiss all") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        state.clearFailures()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            }
            
            ForEach(state.failedJobs) { failure in
                HStack(alignment: .top, spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.fileName)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(failure.message)
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            state.dismissFailure(id: failure.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss error for \(failure.fileName)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.red.opacity(0.18), lineWidth: 0.5)
                        )
                )
            }
        }
    }
    
    // MARK: - Active Queue Section
    private var activeQueueSection: some View {
        let unfinished = state.activeJobs.filter { !$0.isFinished }
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current queue")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                
                if state.hasPausableJobs {
                    let allPaused = state.areAllPausableJobsPaused
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            if allPaused {
                                state.resumeAllJobs()
                            } else {
                                state.pauseAllJobs()
                            }
                        }
                    } label: {
                        Label(allPaused ? "Resume All" : "Pause All", systemImage: allPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(state.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(state.accentColor.opacity(0.12))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(state.accentColor.opacity(0.25), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(allPaused ? "Resume all paused tasks" : "Pause running video and audio tasks")
                }
                
                if !unfinished.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            state.cancelAllJobs()
                        }
                    } label: {
                        Text(unfinished.count > 1 ? "Cancel All" : "Cancel")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
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
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(job.statusText)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(job.error == "Cancelled" || job.isFinished || job.isPaused ? .secondary : state.accentColor)
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
                        
                        if job.canPause {
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    if job.isPaused {
                                        state.resumeJob(id: job.id)
                                    } else {
                                        state.pauseJob(id: job.id)
                                    }
                                }
                            } label: {
                                Image(systemName: job.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(job.isPaused ? state.accentColor : .secondary.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help(job.isPaused ? "Resume this task" : "Pause this task")
                            .accessibilityLabel(job.isPaused ? "Resume \(job.fileURL.lastPathComponent)" : "Pause \(job.fileURL.lastPathComponent)")
                        }
                        
                        // Individual Cancel Button
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                state.cancelJob(id: job.id)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel this compression task")
                        .accessibilityLabel("Cancel \(job.fileURL.lastPathComponent)")
                    } else if job.error == "Cancelled" {
                        Text("Cancelled")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
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
                .overlay(alignment: .bottom) {
                    if !job.isFinished {
                        Rectangle()
                            .fill(state.accentColor.opacity(0.45))
                            .frame(height: 1)
                    }
                }
            }
        }
    }
    
    // MARK: - Recent History Section with Collapsible Folders & Batch Edit
    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Bar
            HStack(spacing: 6) {
                Text("Recent")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = true
                    panel.prompt = String(localized: "Add Files")
                    if panel.runModal() == .OK, !panel.urls.isEmpty {
                        let urls = panel.urls
                        Task {
                            await MediaCompressionEngine.shared.processDroppedURLs(urls)
                        }
                    }
                } label: {
                    Label("Add files", systemImage: "plus")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Choose files to compress")

                Spacer()
                
                Menu {
                    Button {
                        newFolderName = "Project \(state.customFolders.count + 1)"
                        isCreatingFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    if !state.recentResults.isEmpty {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear History…", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .help("Recent actions")

                if !state.recentResults.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedResultIds.removeAll()
                            }
                        }
                    } label: {
                        Text(isEditMode ? "Done" : "Edit")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(isEditMode ? state.contrastTextColor : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(isEditMode ? state.accentColor : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
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
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 9, design: .rounded))
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
        .confirmationDialog("Clear Recent Compressions?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear All History", role: .destructive) {
                state.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove recent items from your activity log. Original files on disk will not be deleted.")
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
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(selectedResultIds.isEmpty ? .secondary : state.accentColor)
                    Text(selectedResultIds.count == state.recentResults.count && !state.recentResults.isEmpty ? "Deselect All" : "Select All")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
            }
            .buttonStyle(.plain)
            
            Text("(\(selectedResultIds.count) selected)")
                .font(.system(size: 9, design: .rounded))
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
                            .font(.system(size: 9, design: .rounded))
                        Text("Rename")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
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
                            .font(.system(size: 9, design: .rounded))
                        Text("Move")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
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
                        .font(.system(size: 9.5, design: .rounded))
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
                .font(.system(size: 13, weight: .bold, design: .rounded))
            
            TextField("Folder Name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .rounded))
            
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
                .font(.system(size: 13, weight: .bold, design: .rounded))
            
            Text("Enter a format pattern. Use '#' or '{index}' for auto-incrementing numbers.")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.secondary)
            
            TextField("e.g. Homerenovation_# or Project_{index}", text: $renamePattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .rounded))
            
            // Live Format Preview Box
            VStack(alignment: .leading, spacing: 3) {
                Text("LIVE PREVIEW:")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.8))
                
                HStack(spacing: 4) {
                    Text("\(previewExample1).mp4,  \(previewExample2).mp4 ...")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
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
                .font(.system(size: 9, design: .rounded))
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                
                Button("Optimized_{index}") {
                    renamePattern = "Optimized_{index}"
                }
                .font(.system(size: 9, design: .rounded))
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
                    .font(.system(size: 24, design: .rounded))
                    .foregroundColor(isDropTargeted ? state.accentColor : .secondary.opacity(0.6))
                    .scaleEffect(isDropTargeted ? 1.15 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isDropTargeted)
            }
            
            VStack(spacing: 3) {
                Text(isDropTargeted ? "Release to Squeeze" : "Ready to Squeeze")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .tracking(0.25)
                    .foregroundColor(.primary)
                
                Text("Drop media to compress immediately with current presets")
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Format Tags Pill Strip
            HStack(spacing: 4) {
                ForEach(["MP4", "MOV", "PNG", "JPG", "WebP", "PDF", "AAC", "WAV"], id: \.self) { fmt in
                    Text(fmt)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 9, design: .rounded))
                    Text("Squeeze from Clipboard")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    Text("⌘V")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
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
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(state.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isQueueDropTargeted ? "Drop to Add to Queue" : "Custom Staged Queue")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Drop files here to customize individual settings before squeezing")
                                .font(.system(size: 9, design: .rounded))
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(state.accentColor)
                    
                    Text("Staged Queue (\(state.stagedQueue.count))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button("Clear") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                        state.clearQueue()
                    }
                }
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.red.opacity(0.88))
                .buttonStyle(.plain)
                
                Button {
                    state.squeezeStagedQueue()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                        Text("Squeeze All (\(state.stagedQueue.count))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
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
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
                Text("Drop more files to add to queue")
                    .font(.system(size: 9, design: .rounded))
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
        StatusBarController.sharedInstance?.finishFileDragHover(didDrop: true)
        loadDroppedFileURLs(from: providers) { collectedURLs in
            if !collectedURLs.isEmpty {
                Task {
                    await MediaCompressionEngine.shared.processDroppedURLs(collectedURLs)
                }
            }
        }
        return true
    }
    
    private func extractAndAddToQueue(providers: [NSItemProvider]) -> Bool {
        StatusBarController.sharedInstance?.finishFileDragHover(didDrop: true)
        loadDroppedFileURLs(from: providers) { collectedURLs in
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
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(formatAccentColor(for: activeFormatCategory))
                        Text("\(activeFormatCategory.displayName) Settings")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
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
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
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
                Label(targetSizeAutomaticNote(for: category), systemImage: "wand.and.stars")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
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
    
    private func targetSizeAutomaticNote(for category: MediaFormatCategory) -> String {
        switch category {
        case .images: return "Image quality is chosen automatically to fit the limit."
        case .videos: return "Video bitrate is chosen automatically to fit the limit."
        case .audio: return "Audio bitrate is chosen automatically to fit the limit."
        case .pdf: return "DPI and image quality act as upper limits; they're lowered only if needed."
        }
    }
    
    private var targetSizeHeader: some View {
        HStack {
            Label("Target Size Limit", systemImage: "target")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Spacer()
            if let targetMB = state.targetSizeMode.targetMegabytes ?? (state.targetSizeMode == .custom ? state.customTargetSizeMB : nil) {
                Text(String(format: "≤ %.0f MB", targetMB))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(state.accentColor)
            } else {
                Text("Manual Quality")
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var targetSizeGliderBar: some View {
        GeometryReader { proxy in
            let modes = TargetSizeMode.allCases
            let spacing: CGFloat = 4
            let available = proxy.size.width - spacing * CGFloat(modes.count - 1)
            let baseWidth = available / CGFloat(modes.count)
            let manualSelected = state.targetSizeMode == .off
            let manualWidth = baseWidth * (manualSelected ? 1.28 : 0.62)
            let otherWidth = (available - manualWidth) / CGFloat(modes.count - 1)
            let pillWidths = modes.map { $0 == .off ? manualWidth : otherWidth }

            HStack(spacing: spacing) {
                ForEach(modes, id: \.self) { mode in
                    let isSelected = state.targetSizeMode == mode
                    let isHovered = hoveredTargetLimitMode == mode
                    let isOtherHovered = hoveredTargetLimitMode != nil && !isHovered
                    let title = mode == .off
                        ? (isSelected ? String(localized: "Manual") : String(localized: "M", comment: "Single-letter abbreviation of Manual on a narrow pill"))
                        : (mode == .custom ? String(localized: "Custom") : (mode.targetMegabytes.map { String(localized: "\(Int($0)) MB") } ?? mode.displayName))

                    UniversalPillGliderItem(
                        item: mode,
                        title: title,
                        icon: isSelected ? "checkmark" : nil,
                        isSelected: isSelected,
                        accentColor: state.accentColor,
                        contrastTextColor: state.contrastTextColor
                    ) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            state.targetSizeMode = mode
                        }
                    }
                    .frame(width: mode == .off ? manualWidth : otherWidth)
                    .accessibilityLabel(mode == .off ? String(localized: "Manual") : title)
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
            .modifier(SelectedPillDragGesture(
                options: modes,
                selected: state.targetSizeMode,
                spacing: spacing,
                optionWidths: pillWidths
            ) { mode in
                state.targetSizeMode = mode
            })
        }
        .frame(height: 26)
    }
    
    private var customTargetSizeSlider: some View {
        VStack(spacing: 3) {
            HStack {
                Text("Custom Max Size")
                    .font(.system(size: 9, design: .rounded))
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
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
                            title: preset.displayName,
                            icon: nil,
                            isSelected: state.imageQualityPreset == preset,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.imageQualityPreset = preset
                            }
                        }
                    }
                }
                .modifier(SelectedPillDragGesture(
                    options: QualityPreset.allCases,
                    selected: state.imageQualityPreset,
                    spacing: 4
                ) { preset in
                    state.imageQualityPreset = preset
                })
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
            .targetSizeLocked(state: state, what: "quality")
            
            // Resolution Slider Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Resolution Scale", systemImage: "aspectratio")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    Text(state.imageResolutionScale >= 0.99 ? String(localized: "Original (100%)") : String(localized: "\(Int((state.imageResolutionScale * 100).rounded()))% Scale"))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                LiquidGlassSlider(
                    value: $state.imageResolutionScale,
                    range: 0.25...1.0,
                    step: 0.05,
                    accentColor: state.accentColor
                )
                
                // Quick resolution pills with matched geometry glider
                let scales = [0.25, 0.50, 0.75, 1.0]
                HStack(spacing: 4) {
                    ForEach(scales, id: \.self) { scale in
                        UniversalPillGliderItem(
                            item: scale,
                            title: scale >= 0.99 ? "Original" : "\(Int(scale * 100))%",
                            icon: nil,
                            isSelected: abs(state.imageResolutionScale - scale) < 0.01,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.imageResolutionScale = scale
                            }
                        }
                    }
                }
                .modifier(SelectedPillDragGesture(
                    options: scales,
                    selected: scales.first { abs(state.imageResolutionScale - $0) < 0.01 },
                    spacing: 4
                ) { scale in
                    state.imageResolutionScale = scale
                })
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                
                GeometryReader { proxy in
                    let policies = ImageFormatPolicy.allCases
                    let spacing: CGFloat = 4
                    let available = proxy.size.width - spacing * CGFloat(policies.count - 1)
                    let selectedWidth = available / CGFloat(policies.count) * 1.8
                    let otherWidth = (available - selectedWidth) / CGFloat(policies.count - 1)
                    let pillWidths = policies.map { $0 == state.imageFormatPolicy ? selectedWidth : otherWidth }

                    HStack(spacing: spacing) {
                        ForEach(policies, id: \.self) { policy in
                            let isSelected = state.imageFormatPolicy == policy
                            let title = isSelected ? policy.selectedName : policy.shortName

                            UniversalPillGliderItem(
                                item: policy,
                                title: title,
                                icon: nil,
                                isSelected: isSelected,
                                accentColor: state.accentColor,
                                contrastTextColor: state.contrastTextColor
                            ) {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                    state.imageFormatPolicy = policy
                                }
                            }
                            .frame(width: isSelected ? selectedWidth : otherWidth)
                            .accessibilityLabel(policy.displayName)
                        }
                    }
                    .modifier(SelectedPillDragGesture(
                        options: policies,
                        selected: state.imageFormatPolicy,
                        spacing: spacing,
                        optionWidths: pillWidths
                    ) { policy in
                        state.imageFormatPolicy = policy
                    })
                }
                .frame(height: 26)
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
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
                            title: preset.displayName,
                            icon: nil,
                            isSelected: state.videoQualityPreset == preset,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.videoQualityPreset = preset
                            }
                        }
                    }
                }
                .modifier(SelectedPillDragGesture(
                    options: QualityPreset.allCases,
                    selected: state.videoQualityPreset,
                    spacing: 4
                ) { preset in
                    state.videoQualityPreset = preset
                })
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
            .targetSizeLocked(state: state, what: "bitrate")
            
            // Video Resolution Slider Card
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Resolution Scale", systemImage: "aspectratio")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    Text(state.videoResolutionScale >= 0.99 ? String(localized: "Original (100%)") : String(localized: "\(Int((state.videoResolutionScale * 100).rounded()))% Scale"))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                LiquidGlassSlider(
                    value: $state.videoResolutionScale,
                    range: 0.25...1.0,
                    step: 0.05,
                    accentColor: state.accentColor
                )
                
                // Quick resolution pills with matched geometry glider
                let scaleOptions = [0.25, 0.50, 0.75, 1.0]
                HStack(spacing: 4) {
                    ForEach(scaleOptions, id: \.self) { scale in
                        UniversalPillGliderItem(
                            item: scale,
                            title: scale >= 0.99 ? "Original" : "\(Int(scale * 100))%",
                            icon: nil,
                            isSelected: abs(state.videoResolutionScale - scale) < 0.01,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.videoResolutionScale = scale
                            }
                        }
                    }
                }
                .modifier(SelectedPillDragGesture(
                    options: scaleOptions,
                    selected: scaleOptions.first { abs(state.videoResolutionScale - $0) < 0.01 },
                    spacing: 4
                ) { scale in
                    state.videoResolutionScale = scale
                })
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    Text(state.videoFramerate.displayName)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                GeometryReader { proxy in
                    let options = VideoFramerateOption.allCases
                    let spacing: CGFloat = 3.5
                    let available = proxy.size.width - spacing * CGFloat(options.count - 1)
                    let baseWidth = available / CGFloat(options.count)
                    let selectedWidth = baseWidth * 1.55
                    let otherWidth = (available - selectedWidth) / CGFloat(options.count - 1)

                    HStack(spacing: spacing) {
                        ForEach(options, id: \.self) { opt in
                            let isSelected = state.videoFramerate == opt
                            let title = isSelected && opt == .original ? opt.displayName : opt.shortName

                            UniversalPillGliderItem(
                                item: opt,
                                title: title,
                                icon: nil,
                                isSelected: isSelected,
                                accentColor: state.accentColor,
                                contrastTextColor: state.contrastTextColor
                            ) {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                    state.videoFramerate = opt
                                }
                            }
                            .frame(width: isSelected ? selectedWidth : otherWidth)
                            .accessibilityLabel(opt.displayName)
                        }
                    }
                    .modifier(SelectedPillDragGesture(
                        options: options,
                        selected: state.videoFramerate,
                        spacing: spacing,
                        optionWidths: options.map { $0 == state.videoFramerate ? selectedWidth : otherWidth }
                    ) { option in
                        state.videoFramerate = option
                    })
                }
                .frame(height: 26)
                
                Divider().opacity(0.15)
                
                Text("Format / Codec")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                
                GeometryReader { proxy in
                    let options = VideoCodecPreference.allCases
                    let spacing: CGFloat = 4
                    let available = proxy.size.width - spacing * CGFloat(options.count - 1)
                    let baseWidth = available / CGFloat(options.count)
                    let selectedWidth = baseWidth * 1.25
                    let otherWidth = (available - selectedWidth) / CGFloat(options.count - 1)

                    HStack(spacing: spacing) {
                        ForEach(options, id: \.self) { codec in
                            let isSelected = state.videoCodec == codec

                            UniversalPillGliderItem(
                                item: codec,
                                title: codec.displayName,
                                icon: nil,
                                isSelected: isSelected,
                                accentColor: state.accentColor,
                                contrastTextColor: state.contrastTextColor
                            ) {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                    state.videoCodec = codec
                                }
                            }
                            .frame(width: isSelected ? selectedWidth : otherWidth)
                            .accessibilityLabel(codec.displayName)
                        }
                    }
                    .modifier(SelectedPillDragGesture(
                        options: options,
                        selected: state.videoCodec,
                        spacing: spacing,
                        optionWidths: options.map { $0 == state.videoCodec ? selectedWidth : otherWidth }
                    ) { codec in
                        state.videoCodec = codec
                    })
                }
                .frame(height: 26)
                
                if state.videoCodec == .gif {
                    Divider().opacity(0.15)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label("GIF Framerate", systemImage: "speedometer")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(state.gifFramerate.displayName)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(state.accentColor)
                        }
                        
                        HStack(spacing: 4) {
                            ForEach(GIFFramerateOption.allCases, id: \.self) { opt in
                                UniversalPillGliderItem(
                                    item: opt,
                                    title: opt.displayName,
                                    icon: nil,
                                    isSelected: state.gifFramerate == opt,
                                    accentColor: state.accentColor,
                                    contrastTextColor: state.contrastTextColor
                                ) {
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                        state.gifFramerate = opt
                                    }
                                }
                            }
                            .modifier(SelectedPillDragGesture(
                                options: GIFFramerateOption.allCases,
                                selected: state.gifFramerate,
                                spacing: 4
                            ) { option in
                                state.gifFramerate = option
                            })
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
                                .font(.system(size: 10, design: .rounded))
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    Text(state.audioBitrate.displayName)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                // Bitrate pills with matched geometry glider
                HStack(spacing: 4) {
                    ForEach(AudioBitratePreference.allCases, id: \.self) { rate in
                        UniversalPillGliderItem(
                            item: rate,
                            title: rate.shortName,
                            icon: nil,
                            isSelected: state.audioBitrate == rate,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.audioBitrate = rate
                            }
                        }
                    }
                }
                .modifier(SelectedPillDragGesture(
                    options: AudioBitratePreference.allCases,
                    selected: state.audioBitrate,
                    spacing: 4
                ) { rate in
                    state.audioBitrate = rate
                })
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
            .targetSizeLocked(state: state, what: "bitrate")
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(Int(state.pdfDPI.dpiValue)) DPI")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                HStack(spacing: 5) {
                    ForEach(PDFDPIOption.allCases, id: \.self) { dpi in
                        UniversalPillGliderItem(
                            item: dpi,
                            title: dpi.displayName,
                            icon: nil,
                            isSelected: state.pdfDPI == dpi,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.pdfDPI = dpi
                            }
                        }
                    }
                }
                .modifier(SelectedPillDragGesture(
                    options: PDFDPIOption.allCases,
                    selected: state.pdfDPI,
                    spacing: 5
                ) { dpi in
                    state.pdfDPI = dpi
                })
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
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
                let qualities = [0.50, 0.70, 0.85]
                HStack(spacing: 5) {
                    ForEach(qualities, id: \.self) { quality in
                        let title = quality == 0.50 ? "50% Compact" : (quality == 0.70 ? "70% Balanced" : "85% High")
                        UniversalPillGliderItem(
                            item: quality,
                            title: title,
                            icon: nil,
                            isSelected: abs(state.pdfImageQuality - quality) < 0.01,
                            accentColor: state.accentColor,
                            contrastTextColor: state.contrastTextColor
                        ) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                                state.pdfImageQuality = quality
                            }
                        }
                    }
                }
                .modifier(SelectedPillDragGesture(
                    options: qualities,
                    selected: qualities.first { abs(state.pdfImageQuality - $0) < 0.01 },
                    spacing: 5
                ) { quality in
                    state.pdfImageQuality = quality
                })
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                
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
            // Output Directory & Suffix Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Save Destination", systemImage: "folder")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(state.customOutputFolder != nil ? "Custom Directory" : (state.exportToSubfolder ? "Automatic Subfolder" : "Next to Original"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 10, design: .rounded))
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
                                .font(.system(size: 9.5, design: .rounded))
                                .foregroundColor(.secondary)
                            
                            TextField("Squeezed", text: $state.subfolderName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                                .font(.system(size: 10, design: .rounded))
                            
                            Text("(e.g. ./Squeezed/)")
                                .font(.system(size: 9.5, design: .rounded))
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
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    if let customFolder = state.customOutputFolder {
                        Text(customFolder)
                            .font(.system(size: 9, design: .rounded))
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
                            openPanel.prompt = String(localized: "Select Output Folder")
                            if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                                state.customOutputFolder = selectedURL.path
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 9, design: .rounded))
                                Text(state.customOutputFolder == nil ? "Choose Fixed Folder..." : "Change Folder...")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
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
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 10, weight: .medium, design: .rounded))
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
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                    
                                    Text("EDGE-DOCK")
                                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                        .foregroundColor(state.accentColor)
                                        .padding(.horizontal, 3.5)
                                        .padding(.vertical, 0.5)
                                        .background(Capsule().fill(state.accentColor.opacity(0.15)))
                                }
                                
                                Text("Edge-docked liquid glass drop zone for instant 1-drop compression.")
                                    .font(.system(size: 9.5, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            LiquidGlassSwitch(isOn: $state.floatingBallEnabled)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                }
                
                Divider().opacity(0.2)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        state.setLaunchAtLogin(enabled: !state.launchAtLogin)
                    }
                } label: {
                    HStack(alignment: .center) {
                        Text("Launch at System Startup")
                            .font(.system(size: 10, design: .rounded))
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
                            .font(.system(size: 10, design: .rounded))
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
                            .font(.system(size: 10, design: .rounded))
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
                            .font(.system(size: 10, design: .rounded))
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
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        LiquidGlassSwitch(isOn: $state.hapticEnabled)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button {
                    WelcomeWindowController.shared.show()
                } label: {
                    HStack(alignment: .center) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(state.accentColor)
                        Text("Welcome & File Access")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button("Reset All Compression Stats") {
                    state.resetAllStats()
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
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
            // Watch Folder Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Auto-Squeeze Watch Folder", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
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
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Button {
                    selectWatchFolder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 9, design: .rounded))
                        Text(state.watchFolderPath == nil ? "Select Folder to Watch..." : "Change Watch Folder...")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                
                Text("Monitors folder and automatically compresses any new image, video, or audio file dropped in.")
                    .font(.system(size: 9, design: .rounded))
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
            
            // Completion Sound Effects Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Completion Soundpack", systemImage: "speaker.wave.3.fill")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(state.soundTheme.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
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
                            LiquidSelectionReader(isSelected: state.soundTheme == sound, id: AnyHashable(sound)) { progress, flowsToLeading in
                                LiquidRevealLabel(
                                    progress: progress,
                                    flowsToLeading: flowsToLeading,
                                    baseColor: .primary.opacity(0.85),
                                    revealColor: state.contrastTextColor
                                ) { color in
                                    HStack(spacing: 4) {
                                        Image(systemName: sound.icon)
                                            .font(.system(size: 9, design: .rounded))
                                        Text(sound.shortName)
                                            .font(.system(size: 9.5, weight: state.soundTheme == sound ? .semibold : .regular, design: .rounded))
                                    }
                                    .foregroundColor(color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4.5)
                                    .frame(maxWidth: .infinity)
                                }
                                .background(
                                    ZStack {
                                        Capsule().fill(Color.white.opacity(0.05))
                                        LiquidFillLayer(progress: progress, flowsToLeading: flowsToLeading, accentColor: state.accentColor, isSelected: state.soundTheme == sound)
                                    }
                                    .clipShape(Capsule())
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .environment(\.pillLiquidDirection, soundThemeLiquidDirection)
                .onChange(of: state.soundTheme) { oldSound, newSound in
                    guard let oldIndex = SoundEffectTheme.allCases.firstIndex(of: oldSound),
                          let newIndex = SoundEffectTheme.allCases.firstIndex(of: newSound),
                          oldIndex != newIndex else { return }
                    let oldColumn = oldIndex % 3
                    let newColumn = newIndex % 3
                    let movesRight = oldIndex / 3 == newIndex / 3
                        ? newColumn > oldColumn
                        : newIndex > oldIndex
                    soundThemeLiquidDirection = movesRight ? .leadingToTrailing : .trailingToLeading
                }
                
                Text("Plays dynamic audio feedback upon completing batch or single file squeezes.")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            
            // Appearance group (scaling, glass, accent colour); collapsed by default
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isAppearanceExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("Appearance", systemImage: "paintbrush")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Scale, glass, accent colour")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Image(systemName: isAppearanceExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isAppearanceExpanded {
                // UI Scaling / Display Density Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Interface Scaling", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Spacer()
                        Text("\(state.uiScale.displayName) (\(state.uiScale.percentageLabel))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(state.accentColor)
                    }
                
                    // Liquid Pill Glider with Matched Geometry and Collective Focus Bounce
                    HStack(spacing: 5) {
                        ForEach(UIScaleOption.allCases, id: \.self) { option in
                            let isHovered = hoveredUIScaleOption == option
                            let isOtherHovered = hoveredUIScaleOption != nil && !isHovered
                        
                            UniversalPillGliderItem(
                                item: option,
                                title: "\(option.displayName) (\(option.percentageLabel))",
                                icon: state.uiScale == option ? "checkmark" : (option == .small ? "arrow.down.right.and.arrow.up.left" : (option == .large ? "arrow.up.left.and.arrow.down.right" : "rectangle.center.inset.filled")),
                                isSelected: state.uiScale == option,
                                accentColor: state.accentColor,
                                contrastTextColor: state.contrastTextColor
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
                    .modifier(SelectedPillDragGesture(
                        options: UIScaleOption.allCases,
                        selected: state.uiScale,
                        spacing: 5
                    ) { option in
                        state.uiScale = option
                    })

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

                // App transparency and Liquid Glass controls
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isGlassSettingsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Label("Liquid Glass", systemImage: "sparkles")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Spacer(minLength: 4)
                            Text("\(Int((state.appTransparency * 100).rounded()))% transparency")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(state.accentColor)
                            Image(systemName: isGlassSettingsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Liquid Glass settings")
                    .accessibilityValue(isGlassSettingsExpanded ? "Expanded" : "Collapsed")
                    .accessibilityHint("Shows or hides transparency, frostedness, and depth controls")

                    if isGlassSettingsExpanded {
                        VStack(alignment: .leading, spacing: 9) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("App Transparency")
                                    Spacer()
                                    Text("\(Int((state.appTransparency * 100).rounded()))%")
                                        .foregroundColor(state.accentColor)
                                }
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))

                                LiquidGlassSlider(
                                    value: $state.appTransparency,
                                    range: 0...1,
                                    accentColor: state.accentColor
                                )
                                .accessibilityLabel("App transparency")

                            }

                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("Frostedness")
                                    Spacer()
                                    Text("\(Int((state.appGlassFrost * 100).rounded()))%")
                                        .foregroundColor(state.accentColor)
                                }
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))

                                LiquidGlassSlider(
                                    value: $state.appGlassFrost,
                                    range: 0...1,
                                    accentColor: state.accentColor
                                )
                                .accessibilityLabel("Liquid Glass frostedness")

                            }

                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("Depth")
                                    Spacer()
                                    Text("\(Int((state.appGlassDepth * 100).rounded()))%")
                                        .foregroundColor(state.accentColor)
                                }
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))

                                LiquidGlassSlider(
                                    value: $state.appGlassDepth,
                                    range: 0...1,
                                    accentColor: state.accentColor
                                )
                                .accessibilityLabel("Liquid Glass depth")

                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
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
                VStack(alignment: .leading, spacing: 8) {
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
                            .help(theme == .custom ? String(localized: "Custom Color Wheel & Spectrum") : String(localized: "\(theme.displayName) Accent"))
                        }
                    }
                    .padding(.vertical, 2)
                
                    // Custom HEX Color Tab (Expands when Custom Color Wheel is active)
                    if state.accentTheme == .custom {
                        VStack(alignment: .leading, spacing: 6) {
                            Divider().opacity(0.15)
                        
                            HStack(spacing: 8) {
                                Text("HEX Code")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            
                                HStack(spacing: 3) {
                                    Text("#")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                
                                    TextField("007AFF", text: Binding(
                                        get: { state.customAccentHex },
                                        set: { newHex in
                                            let filtered = newHex.filter { "0123456789abcdefABCDEF".contains($0) }.prefix(6)
                                            state.customAccentHex = String(filtered).uppercased()
                                        }
                                    ))
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
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
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
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
                                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
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
                
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
            .padding(.horizontal, 4)

        }
    }
    
    private func selectWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Select Watch Folder")
        
        if panel.runModal() == .OK, let url = panel.url {
            state.watchFolderPath = url.path
            state.isWatchFolderEnabled = true
            FolderWatchService.shared.startMonitoring(path: url.path)
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Text("SqueezeBar v1.1.0 • SirJameTV")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
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

// MARK: - Target-size lock for controls the engine ignores
/// In a target-size mode the engine derives quality/bitrate from the size limit, so the manual control is dimmed and explained instead of silently doing nothing.
private struct TargetSizeLockModifier: ViewModifier {
    @ObservedObject var state: AppState
    let what: String

    private var limitLabel: String {
        let mb = state.targetSizeMode.targetMegabytes ?? state.customTargetSizeMB
        return String(format: "%g MB", mb)
    }

    func body(content: Content) -> some View {
        let isLocked = state.targetSizeMode != .off
        VStack(alignment: .leading, spacing: 5) {
            content
                .disabled(isLocked)
                .opacity(isLocked ? 0.4 : 1)
            if isLocked {
                Label("Automatic at \(limitLabel). Choose Manual to adjust \(what).", systemImage: "lock.fill")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isLocked)
    }
}

private extension View {
    func targetSizeLocked(state: AppState, what: String) -> some View {
        modifier(TargetSizeLockModifier(state: state, what: what))
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
                            .font(.system(size: 16, design: .rounded))
                            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
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

private struct LiquidGlassHoverField: View {
    @State private var pointerLocation: CGPoint?

    private let diameter: CGFloat = 600
    private let radius: CGFloat = 300

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HoverTrackingView { location in
                    guard let location, pointerLocation != nil else {
                        pointerLocation = location
                        return
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        pointerLocation = location
                    }
                }
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if let location = pointerLocation {
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: .black.opacity(0.09), location: 0),
                                .init(color: .black.opacity(0.07), location: 0.42),
                                .init(color: .black.opacity(0.04), location: 0.78),
                                .init(color: .black.opacity(0.015), location: 0.95),
                                .init(color: .clear, location: 1)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        ))
                        .frame(width: diameter, height: diameter)
                        .offset(x: location.x - radius, y: location.y - radius)
                        .allowsHitTesting(false)

                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct HoverTrackingView: NSViewRepresentable {
    let onLocationChange: (CGPoint?) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        view.onLocationChange = onLocationChange
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onLocationChange = onLocationChange
    }
}

private final class HoverTrackingNSView: NSView {
    var onLocationChange: ((CGPoint?) -> Void)?
    private var mouseTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        mouseTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointerLocation(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointerLocation(event)
    }

    override func mouseExited(with event: NSEvent) {
        onLocationChange?(nil)
    }

    private func updatePointerLocation(_ event: NSEvent) {
        onLocationChange?(convert(event.locationInWindow, from: nil))
    }
}

// MARK: - Liquid Glass Toggle Row
private struct LiquidGlassToggleRow: View {
    @EnvironmentObject var state: AppState
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
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
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundColor(isOn ? state.accentColor : .secondary)
                        Text(title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 9.5, design: .rounded))
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

// MARK: - Format Tile
private struct LiveProfileGlowCard<Content: View>: View {
    let accentColor: Color
    var isSelected: Bool = false
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? accentColor.opacity(0.12) : Color.white.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? accentColor.opacity(0.45) : Color.clear, lineWidth: 0.75))
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
struct LiquidGlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let accentColor: Color
    
    @State private var isDragging: Bool = false
    @State private var isHovered: Bool = false
    /// Continuous pointer position (0...1) while dragging. The thumb follows this with easing; `value` still snaps to `step`.
    @State private var dragPercentage: CGFloat? = nil
    @State private var dragVelocity: CGFloat = 0.0
    @State private var lastLocationX: CGFloat = 0.0
    @State private var lastDragTimestamp: Date = Date()
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = max(1, geometry.size.width)
            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            let valuePercentage = CGFloat((clampedValue - range.lowerBound) / (range.upperBound - range.lowerBound))
            let percentage = dragPercentage ?? valuePercentage
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
                        // The thumb glides to the pointer; only the stored value is quantized.
                        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.88, blendDuration: 0.1)) {
                            dragPercentage = CGFloat(newPct)
                        }
                        var newValue = range.lowerBound + newPct * (range.upperBound - range.lowerBound)
                        if let step = step, step > 0 {
                            newValue = (newValue / step).rounded() * step
                        }
                        newValue = min(max(newValue, range.lowerBound), range.upperBound)
                        if newValue != value {
                            value = newValue
                        }
                    }
                    .onEnded { _ in
                        // Releasing eases the thumb from the pointer to the snapped value instead of jumping.
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            dragPercentage = nil
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
        .accessibilityElement()
        .accessibilityValue("\(Int(((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let increment = step ?? (range.upperBound - range.lowerBound) / 20
            let proposed = direction == .increment ? value + increment : value - increment
            value = min(max(proposed, range.lowerBound), range.upperBound)
        }
    }
}

private struct PillRowWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum PillLiquidDirection {
    case leadingToTrailing
    case trailingToLeading
}

private struct PillLiquidDirectionKey: EnvironmentKey {
    static let defaultValue = PillLiquidDirection.leadingToTrailing
}

private struct PillLiquidDragContext {
    var isDragging = false
    var selected: AnyHashable?
    var trailing: AnyHashable?
}

private struct PillLiquidDragContextKey: EnvironmentKey {
    static let defaultValue = PillLiquidDragContext()
}

private extension EnvironmentValues {
    var pillLiquidDragContext: PillLiquidDragContext {
        get { self[PillLiquidDragContextKey.self] }
        set { self[PillLiquidDragContextKey.self] = newValue }
    }

    var pillLiquidDirection: PillLiquidDirection {
        get { self[PillLiquidDirectionKey.self] }
        set { self[PillLiquidDirectionKey.self] = newValue }
    }
}

/// The liquid body of a selected pill: everything between the wavy front edge and the far end of the pill.
private struct LiquidPillFillShape: Shape {
    var progress: CGFloat
    var flowsToLeading: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Points along the front edge, top to bottom. The edge ripples and bulges most mid-pour and is flat when at rest.
    static func edgePoints(in rect: CGRect, progress: CGFloat, flowsToLeading: Bool, segments: Int = 28) -> [CGPoint] {
        let amount = min(max(progress, 0), 1)
        let frontierX = flowsToLeading
            ? rect.maxX - rect.width * amount
            : rect.minX + rect.width * amount
        let travel = CGFloat(sin(Double(amount) * .pi))
        let amplitude = rect.height * 0.20 * travel
        let bulge = rect.height * 0.16 * travel
        let phase = Double(amount) * .pi * 1.6
        let direction: CGFloat = flowsToLeading ? -1 : 1
        return (0...segments).map { index -> CGPoint in
            let y = Double(index) / Double(segments)
            let envelope = sin(Double.pi * y)
            let ripple = sin(2 * Double.pi * y - phase) + 0.35 * sin(4 * Double.pi * y + phase * 1.3)
            let offset = (CGFloat(envelope * ripple) * amplitude + CGFloat(envelope) * bulge) * direction
            return CGPoint(x: frontierX + offset, y: rect.minY + rect.height * CGFloat(y))
        }
    }

    func path(in rect: CGRect) -> Path {
        let edge = Self.edgePoints(in: rect, progress: progress, flowsToLeading: flowsToLeading)
        let segments = edge.count - 1
        var path = Path()

        if flowsToLeading {
            path.move(to: edge[0])
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: edge[0])
        }

        for index in 0..<segments {
            let start = edge[index]
            let end = edge[index + 1]
            let previous = edge[max(index - 1, 0)]
            let following = edge[min(index + 2, segments)]
            let control1 = CGPoint(
                x: start.x + (end.x - previous.x) / 6,
                y: start.y + (end.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: end.x - (following.x - start.x) / 6,
                y: end.y - (following.y - start.y) / 6
            )
            path.addCurve(to: end, control1: control1, control2: control2)
        }

        if flowsToLeading {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

/// A thin glossy band just behind the front edge; it grows while the liquid moves and vanishes at rest.
private struct LiquidFrontHighlightShape: Shape {
    var progress: CGFloat
    var flowsToLeading: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let amount = min(max(progress, 0), 1)
        let thickness = 2.4 * CGFloat(sin(Double(amount) * .pi))
        guard thickness > 0.05 else { return Path() }
        let edge = LiquidPillFillShape.edgePoints(in: rect, progress: progress, flowsToLeading: flowsToLeading)
        let behind: CGFloat = flowsToLeading ? thickness : -thickness
        var path = Path()
        path.addLines(edge)
        path.addLines(edge.reversed().map { CGPoint(x: $0.x + behind, y: $0.y) })
        path.closeSubpath()
        return path
    }
}

private struct LiquidFillLayer: View {
    let progress: CGFloat
    let flowsToLeading: Bool
    let accentColor: Color
    let isSelected: Bool

    var body: some View {
        let body = LiquidPillFillShape(progress: progress, flowsToLeading: flowsToLeading)
        ZStack {
            body.fill(
                LinearGradient(
                    colors: [accentColor.opacity(0.95), accentColor.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // Volume: lighter on top, slightly deeper underneath.
            body.fill(
                LinearGradient(
                    colors: [.white.opacity(0.20), .white.opacity(0.0), .black.opacity(0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LiquidFrontHighlightShape(progress: progress, flowsToLeading: flowsToLeading)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.55), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .clipShape(Capsule())
        .shadow(color: accentColor.opacity(isSelected ? 0.38 : 0), radius: 5, y: 1.5)
        .overlay(Capsule().strokeBorder(accentColor.opacity(isSelected ? 0.6 : 0), lineWidth: 0.5))
    }
}

/// Owns a pill's fill progress so the liquid and its label reveal animate from the same value.
private struct LiquidSelectionReader<Content: View>: View {
    let isSelected: Bool
    var id: AnyHashable? = nil
    let content: (_ progress: CGFloat, _ flowsToLeading: Bool) -> Content

    @State private var progress: CGFloat

    @Environment(\.pillLiquidDirection) private var pillLiquidDirection
    @Environment(\.pillLiquidDragContext) private var dragContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isSelected: Bool,
        id: AnyHashable? = nil,
        @ViewBuilder content: @escaping (_ progress: CGFloat, _ flowsToLeading: Bool) -> Content
    ) {
        self.isSelected = isSelected
        self.id = id
        self.content = content
        _progress = State(initialValue: isSelected ? 1 : 0)
    }

    var body: some View {
        let movingLeft = pillLiquidDirection == .trailingToLeading
        content(progress, isSelected ? movingLeft : !movingLeft)
            .onChange(of: isSelected) { _, selected in
                // While dragging, pills the drag has already passed drain instantly instead of trailing behind.
                if dragContext.isDragging && !selected && dragContext.trailing != id {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { progress = 0 }
                    return
                }
                let animation: Animation? = reduceMotion ? nil
                    : (dragContext.isDragging ? .easeOut(duration: 0.10) : .timingCurve(0.3, 0.7, 0.2, 1.0, duration: 0.5))
                withAnimation(animation) {
                    progress = selected ? 1 : 0
                }
            }
    }
}

/// Draws a label twice: in the resting colour where there is no liquid, and in the reveal colour where the liquid has reached.
private struct LiquidRevealLabel<Label: View>: View {
    let progress: CGFloat
    let flowsToLeading: Bool
    let baseColor: Color
    let revealColor: Color
    let label: (Color) -> Label

    var body: some View {
        let liquid = LiquidPillFillShape(progress: progress, flowsToLeading: flowsToLeading).fill(Color.black)
        ZStack {
            label(baseColor)
                .mask(
                    Rectangle().fill(Color.black)
                        .overlay(liquid.blendMode(.destinationOut))
                        .compositingGroup()
                )
            label(revealColor)
                .mask(liquid)
        }
    }
}

private struct SelectedPillDragGesture<Option: Hashable>: ViewModifier {
    let options: [Option]
    let selected: Option?
    let spacing: CGFloat
    var optionWidths: [CGFloat]? = nil
    let onSelect: (Option) -> Void

    @State private var pillLiquidDirection = PillLiquidDirection.leadingToTrailing
    @State private var centersAtDragStart: [CGFloat] = []
    @State private var trailingOption: Option?
    @State private var rowWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.pillLiquidDirection, pillLiquidDirection)
            .environment(\.pillLiquidDragContext, PillLiquidDragContext(
                isDragging: !centersAtDragStart.isEmpty,
                selected: selected.map { AnyHashable($0) },
                trailing: trailingOption.map { AnyHashable($0) }
            ))
            .onChange(of: selected) { oldSelection, newSelection in
                guard let oldSelection,
                      let newSelection,
                      let oldIndex = options.firstIndex(of: oldSelection),
                      let newIndex = options.firstIndex(of: newSelection),
                      oldIndex != newIndex else { return }
                pillLiquidDirection = newIndex > oldIndex ? .leadingToTrailing : .trailingToLeading
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PillRowWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(PillRowWidthPreferenceKey.self) { rowWidth = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard let selected, let selectedIndex = options.firstIndex(of: selected) else { return }

                    if centersAtDragStart.isEmpty {
                        let widths = optionWidths.flatMap { $0.count == options.count ? $0 : nil }
                            ?? Array(repeating: max(0, (rowWidth - spacing * CGFloat(options.count - 1)) / CGFloat(options.count)), count: options.count)
                        var centers: [CGFloat] = []
                        var x: CGFloat = 0
                        for width in widths {
                            centers.append(x + width / 2)
                            x += width + spacing
                        }

                        guard abs(value.startLocation.x - centers[selectedIndex]) <= widths[selectedIndex] / 2 else { return }
                        centersAtDragStart = centers
                    }

                    let cursorX = value.startLocation.x + value.translation.width
                    guard let targetIndex = centersAtDragStart.indices.min(by: {
                        abs(centersAtDragStart[$0] - cursorX) < abs(centersAtDragStart[$1] - cursorX)
                    }), targetIndex != selectedIndex else { return }

                    pillLiquidDirection = targetIndex > selectedIndex ? .leadingToTrailing : .trailingToLeading
                    trailingOption = abs(targetIndex - selectedIndex) == 1 ? selected : nil
                    withAnimation(.easeOut(duration: 0.10)) {
                        onSelect(options[targetIndex])
                    }
                }
                .onEnded { _ in
                    centersAtDragStart.removeAll()
                    trailingOption = nil
                }
        )
    }
}

// MARK: - Reusable selectable pill with liquid fill and cursor glow
private struct UniversalPillGliderItem<T: Hashable>: View {
    let item: T
    let title: String
    let icon: String?
    let isSelected: Bool
    let accentColor: Color
    let contrastTextColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var mouseLocation: CGPoint = .zero
    
    var body: some View {
        LiquidSelectionReader(isSelected: isSelected, id: AnyHashable(item)) { progress, flowsToLeading in
            pillButton(progress: progress, flowsToLeading: flowsToLeading)
        }
    }
    
    private func pillButton(progress: CGFloat, flowsToLeading: Bool) -> some View {
        Button(action: action) {
            LiquidRevealLabel(
                progress: progress,
                flowsToLeading: flowsToLeading,
                baseColor: isHovered ? .white : .primary.opacity(0.85),
                revealColor: contrastTextColor
            ) { color in
                HStack(spacing: 4) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 9, design: .rounded))
                    }
                    Text(title)
                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minHeight: 26)
                .frame(maxWidth: .infinity)
            }
            .background(
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.12 : 0.08), Color.white.opacity(isHovered ? 0.05 : 0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    LiquidFillLayer(progress: progress, flowsToLeading: flowsToLeading, accentColor: accentColor, isSelected: isSelected)
                    
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
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.28 : 0.10), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                    
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
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Folder Icon (Double Click to Change Folder Color)
                Image(systemName: isFolderDropTargeted ? "folder.badge.plus" : folder.icon)
                    .font(.system(size: 12, design: .rounded))
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
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
                    .frame(maxWidth: 140)
                } else {
                    Text(folder.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    if totalFolderSavedBytes > 0 {
                        Text("• -\(formattedFolderSaved)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 9, design: .rounded))
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
                        .font(.system(size: 9, design: .rounded))
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
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(isFolderDropTargeted ? .green : effectiveFolderColor.opacity(0.6))
                        
                        Text(isFolderDropTargeted ? "Release to drop into \(folder.name)" : "Drop files here or use 'Move' in Edit mode")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
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
                .font(.system(size: 11, weight: .bold, design: .rounded))
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
                                .font(.system(size: 8, weight: .black, design: .rounded))
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
                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.0.displayName)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
    }
    
    private func extractAndProcessFolderDrop(providers: [NSItemProvider], targetFolderId: UUID) -> Bool {
        StatusBarController.sharedInstance?.finishFileDragHover(didDrop: true)
        loadDroppedFileURLs(from: providers) { collectedURLs in
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
    private var resultBadge: some View {
        let sizeDifference = item.compressedSize - item.originalSize
        let tint: Color
        let label: String
        let fillOpacity: Double

        if sizeDifference < 0 {
            tint = state.accentColor
            label = String(format: "-%.0f%%", item.percentSaved)
            fillOpacity = 0.07
        } else if sizeDifference > 0 {
            tint = .orange
            label = "\(ByteCountFormatter.string(fromByteCount: sizeDifference, countStyle: .file)) larger"
            fillOpacity = 0.05
        } else {
            tint = .secondary
            label = "0%"
            fillOpacity = 0.03
        }

        return Text(label)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(tint)
            .lineLimit(1)
            .padding(.horizontal, 6.5)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(tint.opacity(fillOpacity)))
    }
    
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
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? state.accentColor : .secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect item" : "Select item")
            }
            
            FileThumbnailView(url: item.outputURL, mediaType: item.mediaType, size: 30)
            
            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 5) {
                    Text(item.formattedOriginalSize)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(item.formattedCompressedSize)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(item.compressedSize < item.originalSize ? state.accentColor : .secondary)
                    Text("·  \(item.timestamp, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.75))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 4)
            
            resultBadge
            
            // Action Buttons in Frosted Mini Glass
            HStack(spacing: 2) {
                Button {
                    InspectorWindowController.shared.show(result: item)
                } label: {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Before/After Comparison Inspector")
                .accessibilityLabel("Compare before and after")
                
                Button {
                    state.revealInFinder(url: item.outputURL)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal in Finder")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(isSelected ? state.accentColor.opacity(0.08) : Color.white.opacity(isHovered ? 0.025 : 0.008))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.045)).frame(height: 0.5)
        }
        .onHover { h in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovered = h
            }
        }
        .onDrag {
            NSItemProvider(object: item.outputURL as NSURL)
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(state.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.fileName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 4) {
                    Text(item.formattedOriginalSize)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Text(customSettingSummary)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
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
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    Text("Custom")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 12, design: .rounded))
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
                parts.append(String(localized: "\(Int(mb))MB Limit"))
            }
        }
        parts.append(String(localized: "\(Int(item.customQuality * 100))% Q", comment: "Quality percentage, abbreviated"))
        if item.customResolutionScale < 0.99 {
            parts.append(String(localized: "\(Int(item.customResolutionScale * 100))% Scale"))
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
