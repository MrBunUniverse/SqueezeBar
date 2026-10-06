import Foundation
import AppKit
import SwiftUI
import Combine

public final class StatusItemDropView: NSView {
    
    // MARK: - Delegate / Callback
    public weak var controller: StatusBarController?
    
    // MARK: - State
    public enum DisplayMode {
        case idle
        case dragHover
        case processing(progress: Double)
        case success
    }
    
    public var mode: DisplayMode = .idle {
        didSet {
            needsDisplay = true
        }
    }
    
    private var isHighlighted: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = false
        
        // Register for all File Drag Types
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("public.item")
        ])
        
        // Observe AppState
        Publishers.CombineLatest3(
            AppState.shared.$isProcessing,
            AppState.shared.$overallProgress,
            AppState.shared.$showSuccessBadge
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] isProc, prog, isSuccess in
            guard let self = self else { return }
            
            if isSuccess {
                self.mode = .success
            } else if isProc {
                self.mode = .processing(progress: prog)
            } else {
                self.mode = .idle
            }
        }
        .store(in: &cancellables)
    }
    
    private var isHoveringDrag: Bool = false
    
    // MARK: - Mouse Click Handling
    public override func mouseDown(with event: NSEvent) {
        isHighlighted = true
    }
    
    public override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            controller?.togglePopover(sender: self)
        }
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        controller?.showContextMenu(for: self, with: event)
    }
    
    // MARK: - NSDraggingDestination
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasValidMediaFiles(in: sender) else {
            return []
        }
        
        beginDragHover()
        return .copy
    }
    
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let isValid = hasValidMediaFiles(in: sender)
        if isValid { beginDragHover() }
        return isValid ? .copy : []
    }
    
    public override func draggingEnded(_ sender: NSDraggingInfo) {
        controller?.scheduleFileDragEnd()
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = extractFileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        
        controller?.finishFileDragHover(didDrop: true)
        
        Task {
            await MediaCompressionEngine.shared.processDroppedURLs(urls)
        }
        
        return true
    }
    
    private func updateCurrentMode() {
        let state = AppState.shared
        if state.showSuccessBadge {
            mode = .success
        } else if state.isProcessing {
            mode = .processing(progress: state.overallProgress)
        } else {
            mode = .idle
        }
    }
    
    // MARK: - Drag Helpers
    private func hasValidMediaFiles(in sender: NSDraggingInfo) -> Bool {
        let urls = extractFileURLs(from: sender)
        if !urls.isEmpty {
            return true
        }
        return Self.containsPotentialFileDragType(sender.draggingPasteboard.types ?? [])
    }

    static func containsPotentialFileDragType(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(.fileURL) ||
        types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) ||
        types.contains(NSPasteboard.PasteboardType("public.file-url")) ||
        types.contains(NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")) ||
        types.contains(NSPasteboard.PasteboardType("public.item"))
    }

    func beginDragHover() {
        guard !isHoveringDrag else { return }
        isHoveringDrag = true
        mode = .dragHover
        controller?.showPopoverForDrag(sender: self)
    }

    func endDragHover() {
        guard isHoveringDrag else { return }
        isHoveringDrag = false
        controller?.updateStatusItemLength()
        updateCurrentMode()
    }
    
    private func extractFileURLs(from sender: NSDraggingInfo) -> [URL] {
        var urls: [URL] = []
        let pb = sender.draggingPasteboard
        
        // 1. NSURL reading
        if let items = pb.readObjects(
            forClasses: [NSURL.self],
            options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]
        ) as? [URL], !items.isEmpty {
            urls.append(contentsOf: items)
        }
        
        // 2. Filenames array fallback
        if urls.isEmpty, let filenames = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        }
        
        // 3. Pasteboard items fallback
        if urls.isEmpty, let pasteboardItems = pb.pasteboardItems {
            for item in pasteboardItems {
                if let urlString = item.string(forType: .fileURL), let url = URL(string: urlString) {
                    urls.append(url)
                }
            }
        }
        
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
    
    // MARK: - Custom Drawing
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let rect = bounds
        
        switch mode {
        case .idle:
            drawIdleState(in: rect, context: context)
            
        case .dragHover:
            drawDragHoverPill(in: rect, context: context)
            
        case .processing(let progress):
            drawProcessingState(in: rect, progress: progress, context: context)
            
        case .success:
            drawSuccessState(in: rect, context: context)
        }
    }
    
    // MARK: - Render: Idle Icon
    private func drawIdleState(in rect: NSRect, context: CGContext) {
        let iconSize: CGFloat = 17.0
        let iconColor: NSColor = isHighlighted ? .systemBlue : .white
        let clampImage = NSImage.squeezeClampImage(size: iconSize, color: iconColor)
        let iconRect = NSRect(
            x: (rect.width - iconSize) / 2,
            y: (rect.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        clampImage.draw(in: iconRect)
    }
    
    // MARK: - Render: In-Place Drop Hover Indicator
    private func drawDragHoverPill(in rect: NSRect, context: CGContext) {
        let pillRect = NSRect(x: rect.minX + 3, y: rect.minY + 5, width: rect.width - 6, height: rect.height - 7)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 7, yRadius: 7)
        let tailCenterX = rect.maxX - 17
        let tailHalfWidth: CGFloat = 4
        let tailBaseY = pillRect.minY + 0.5
        let tailTipY = rect.minY + 1
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: tailCenterX - tailHalfWidth, y: tailBaseY))
        tail.line(to: CGPoint(x: tailCenterX, y: tailTipY))
        tail.line(to: CGPoint(x: tailCenterX + tailHalfWidth, y: tailBaseY))
        tail.close()

        let fillColor = NSColor.systemBlue.withAlphaComponent(0.88)
        fillColor.setFill()
        tail.fill()
        pillPath.fill()
        NSColor.systemBlue.setStroke()
        pillPath.lineWidth = 1
        pillPath.stroke()

        let tailOutline = NSBezierPath()
        tailOutline.move(to: CGPoint(x: tailCenterX - tailHalfWidth, y: tailBaseY + 1))
        tailOutline.line(to: CGPoint(x: tailCenterX, y: tailTipY))
        tailOutline.line(to: CGPoint(x: tailCenterX + tailHalfWidth, y: tailBaseY + 1))
        tailOutline.lineWidth = 1
        tailOutline.stroke()

        let label = "Drop here" as NSString
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.roundedSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelSize = label.size(withAttributes: labelAttributes)
        let iconSize: CGFloat = 14
        let iconRect = NSRect(
            x: tailCenterX - iconSize / 2,
            y: pillRect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        let labelRect = NSRect(
            x: iconRect.minX - 6 - labelSize.width,
            y: pillRect.midY - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        label.draw(in: labelRect, withAttributes: labelAttributes)

        let clampImage = NSImage.squeezeClampImage(size: iconSize, color: .white)
        clampImage.draw(in: iconRect)
    }
    
    // MARK: - Render: Circular Progress Indicator
    private func drawProcessingState(in rect: NSRect, progress: Double, context: CGContext) {
        let size: CGFloat = 16.0
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = (size - 2.5) / 2.0
        
        context.saveGState()
        
        // Background track (semi-transparent white)
        context.setLineWidth(2.0)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
        
        // Progress arc (vibrant bright cyan/blue)
        let startAngle: CGFloat = -.pi / 2.0
        let currentProg = max(0.05, min(progress, 1.0))
        let endAngle: CGFloat = startAngle + CGFloat(currentProg * .pi * 2.0)
        
        context.setLineWidth(2.2)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor(red: 0.25, green: 0.75, blue: 1.0, alpha: 1.0).cgColor)
        context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        context.strokePath()
        
        context.restoreGState()
    }
    
    // MARK: - Render: Success Checkmark Badge
    private func drawSuccessState(in rect: NSRect, context: CGContext) {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)]))
        if let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: String(localized: "Completed"))?.withSymbolConfiguration(iconConfig) {
            let iconRect = NSRect(
                x: (rect.width - 18) / 2,
                y: (rect.height - 18) / 2,
                width: 18,
                height: 18
            )
            checkImage.draw(in: iconRect)
        }
    }
}
