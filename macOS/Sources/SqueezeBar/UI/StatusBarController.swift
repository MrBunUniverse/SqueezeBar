import Foundation
import AppKit
import SwiftUI

struct FileDragSession {
    enum Presentation { case popover, floatingWindow }
    let openedPresentation: Presentation?
    private var outsideSince: TimeInterval?
    private var releasedSince: TimeInterval?

    init(openedPresentation: Presentation?) {
        self.openedPresentation = openedPresentation
    }

    mutating func markReleased(at time: TimeInterval) {
        if releasedSince == nil { releasedSince = time }
    }

    mutating func shouldFinish(isInside: Bool, mousePressed: Bool, time: TimeInterval) -> Bool {
        if !mousePressed { markReleased(at: time) }
        if let releasedSince { return time - releasedSince >= 0.12 }
        if isInside {
            outsideSince = nil
            return false
        }
        if outsideSince == nil { outsideSince = time }
        return time - outsideSince! >= 0.25
    }
}

@MainActor
public final class StatusBarController: NSObject {
    public static weak var sharedInstance: StatusBarController?
    
    // MARK: - Dimensions
    private let normalWidth: CGFloat = 34.0
    private let barHeight: CGFloat = 24.0
    private let dragHoverWidth: CGFloat = 118.0
    
    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private var dropView: StatusItemDropView!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var dragEventMonitor: Any?
    private var localDragEventMonitor: Any?
    private var dragTrackingTimer: Timer?
    private var fileDragSession: FileDragSession?
    
    public var window: NSWindow? {
        return popover?.contentViewController?.view.window
    }
    
    // MARK: - Init
    public override init() {
        super.init()
        StatusBarController.sharedInstance = self
        setupStatusItem()
        setupPopover()
    }
    
    // MARK: - Status Item Setup
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: normalWidth)
        
        let customView = StatusItemDropView(frame: NSRect(x: 0, y: 0, width: normalWidth, height: barHeight))
        customView.controller = self
        self.dropView = customView
        
        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.addSubview(customView)
            customView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                customView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                customView.topAnchor.constraint(equalTo: button.topAnchor),
                customView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            
            button.registerForDraggedTypes([
                .fileURL,
                NSPasteboard.PasteboardType("NSFilenamesPboardType"),
                NSPasteboard.PasteboardType("public.file-url"),
                NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
                NSPasteboard.PasteboardType("public.item")
            ])
        }

        let dragEvents: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp, .keyDown]
        dragEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: dragEvents) { [weak self] event in
            self?.handleFileDragEvent(event)
        }
        localDragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: dragEvents) { [weak self] event in
            self?.handleFileDragEvent(event)
            return event
        }
    }

    private func handleFileDragEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { finishFileDragHover() }
        } else if event.type == .leftMouseUp {
            scheduleFileDragEnd()
        } else if fileDragSession != nil {
            updateFileDragHover()
        } else {
            revealForNearbyFileDrag()
        }
    }

    private func revealForNearbyFileDrag() {
        guard fileDragSession == nil,
              let button = statusItem.button,
              let window = button.window else { return }

        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let dropZone = NSRect(
            x: buttonFrame.minX - 18,
            y: buttonFrame.minY - 48,
            width: buttonFrame.width + 36,
            height: buttonFrame.height + 48
        )
        guard dropZone.contains(NSEvent.mouseLocation),
              StatusItemDropView.containsPotentialFileDragType(NSPasteboard(name: .drag).types ?? []) else { return }

        dropView.beginDragHover()
    }
    
    public func updateStatusItemLength() {
        if statusItem.length != normalWidth {
            statusItem.length = normalWidth
            dropView.needsDisplay = true
        }
    }
    
    // MARK: - Popover Setup
    private func setupPopover() {
        let pop = NSPopover()
        let scale = AppState.shared.uiScale
        pop.contentSize = NSSize(width: scale.baseWidth, height: scale.baseHeight)
        pop.behavior = .transient
        pop.animates = true
        
        let contentView = QuickPopoverView(isDetachedWindow: false)
            .environmentObject(AppState.shared)
        
        pop.contentViewController = NSHostingController(rootView: contentView)
        self.popover = pop
    }
    
    public func updatePopoverDimensionsForScale(_ scale: UIScaleOption) {
        guard let pop = popover else { return }
        pop.contentSize = NSSize(width: scale.baseWidth, height: scale.baseHeight)
    }
    
    public func ensurePopoverDimensions(width: CGFloat, height: CGFloat) {
        guard let pop = popover, pop.isShown else { return }
        let scale = AppState.shared.uiScale
        let targetW = max(pop.contentSize.width, width * scale.scaleFactor)
        let targetH = max(pop.contentSize.height, height * scale.scaleFactor)
        if targetW != pop.contentSize.width || targetH != pop.contentSize.height {
            pop.contentSize = NSSize(width: targetW, height: targetH)
        }
    }
    
    // MARK: - Popover Presentation
    public func togglePopover(sender: NSView) {
        if AppState.shared.isDetached {
            FloatingDropWindowController.shared.showFloatingWindow()
            return
        }
        
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }
    
    public func showPopover(sender: NSView? = nil, relativeTo anchor: NSRect? = nil) {
        if AppState.shared.isDetached {
            FloatingDropWindowController.shared.showFloatingWindow()
            return
        }
        
        let targetView = sender ?? statusItem.button ?? dropView
        if let button = targetView {
            popover.behavior = AppState.shared.isPinned ? .applicationDefined : .transient
            popover.show(relativeTo: anchor ?? button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            
            if let window = popover.contentViewController?.view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .floating
            }
            
            // Monitor clicks outside to dismiss (only if not pinned and not clicking on Color Panel)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self else { return }
                guard !AppState.shared.isPinned else { return }
                
                // If NSColorPanel is open and the click is inside its window frame, keep popover open
                if NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible {
                    let mousePoint = NSEvent.mouseLocation
                    if NSPointInRect(mousePoint, NSColorPanel.shared.frame) {
                        return
                    }
                }
                
                self.closePopover(sender: nil)
            }
        }
    }

    public func showPopoverForDrag(sender: NSView) {
        guard fileDragSession == nil else { return }
        let openedPresentation: FileDragSession.Presentation?
        if AppState.shared.isDetached {
            openedPresentation = FloatingDropWindowController.shared.window?.isVisible == true ? nil : .floatingWindow
        } else {
            openedPresentation = popover.isShown ? nil : .popover
        }
        fileDragSession = FileDragSession(openedPresentation: openedPresentation)
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateFileDragHover() }
        }
        dragTrackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        statusItem.length = max(normalWidth, dragHoverWidth)
        dropView.needsDisplay = true
        if AppState.shared.isDetached {
            showPopover(sender: sender)
            return
        }
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            let anchor = NSRect(
                x: max(button.bounds.minX, button.bounds.maxX - barHeight),
                y: button.bounds.minY,
                width: min(barHeight, button.bounds.width),
                height: button.bounds.height
            )
            showPopover(sender: button, relativeTo: anchor)
        }
        if !AppState.shared.isPinned {
            popover.behavior = .applicationDefined
        }
    }

    private func updateFileDragHover() {
        guard var session = fileDragSession else { return }
        let mouse = NSEvent.mouseLocation
        var isInside = false
        if let button = statusItem.button, let window = button.window {
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            isInside = frame.insetBy(dx: -18, dy: -48).contains(mouse)
        }
        let contentWindow = AppState.shared.isDetached ? FloatingDropWindowController.shared.window : window
        if let contentWindow, contentWindow.isVisible {
            isInside = isInside || contentWindow.frame.insetBy(dx: -8, dy: -8).contains(mouse)
        }
        let shouldFinish = session.shouldFinish(
            isInside: isInside,
            mousePressed: NSEvent.pressedMouseButtons & 1 != 0,
            time: ProcessInfo.processInfo.systemUptime
        )
        fileDragSession = session
        if shouldFinish { finishFileDragHover() }
    }

    public func scheduleFileDragEnd() {
        fileDragSession?.markReleased(at: ProcessInfo.processInfo.systemUptime)
    }

    public func finishFileDragHover(didDrop: Bool = false) {
        let openedPresentation = fileDragSession?.openedPresentation
        fileDragSession = nil
        dragTrackingTimer?.invalidate()
        dragTrackingTimer = nil
        dropView.endDragHover()
        if !didDrop {
            switch openedPresentation {
            case .popover: closePopover(sender: nil)
            case .floatingWindow: FloatingDropWindowController.shared.dismissDragPresentation()
            case nil: break
            }
        }
        guard !AppState.shared.isDetached,
              !AppState.shared.isPinned,
              !(NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible) else { return }
        popover.behavior = .transient
    }
    
    public func updatePinState(pinned: Bool) {
        popover.behavior = pinned ? .applicationDefined : .transient
        if let window = popover.contentViewController?.view.window {
            window.level = pinned ? .floating : .normal
        }
    }
    
    public func onColorPanelOpen() {
        popover?.behavior = .applicationDefined
    }
    
    public func onColorPanelClose() {
        if !AppState.shared.isPinned {
            popover?.behavior = .transient
        }
    }
    
    public func closePopover(sender: Any?) {
        if fileDragSession != nil { finishFileDragHover(didDrop: true) }
        if NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible {
            CustomColorPanelManager.shared.close()
        }
        if popover.isShown {
            popover.performClose(sender)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    // MARK: - Right Click Context Menu
    public func showContextMenu(for view: NSView, with event: NSEvent) {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "SqueezeBar", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let openItem = NSMenuItem(title: String(localized: "Open SqueezeBar Hub"), action: #selector(menuOpenHub), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        let detachItem = NSMenuItem(
            title: AppState.shared.isDetached ? String(localized: "Dock to Menu Bar") : String(localized: "Detach Floating Window"),
            action: #selector(menuToggleDetach),
            keyEquivalent: "d"
        )
        detachItem.target = self
        menu.addItem(detachItem)
        
        let ballItem = NSMenuItem(
            title: AppState.shared.floatingBallEnabled ? String(localized: "Hide Desktop Drop Ball") : String(localized: "Show Desktop Drop Ball"),
            action: #selector(menuToggleFloatingBall),
            keyEquivalent: "b"
        )
        ballItem.target = self
        menu.addItem(ballItem)
        
        let clearItem = NSMenuItem(title: String(localized: "Clear Compression History"), action: #selector(menuClearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: String(localized: "Quit SqueezeBar"), action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let menuFont = NSFont.roundedSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)
        for item in menu.items where !item.isSeparatorItem {
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: menuFont])
        }
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // restore custom click handler
    }
    
    @objc private func menuOpenHub() {
        if AppState.shared.isDetached {
            FloatingDropWindowController.shared.showFloatingWindow()
        } else if let button = statusItem.button {
            showPopover(sender: button)
        }
    }
    
    @objc private func menuToggleDetach() {
        FloatingDropWindowController.shared.toggleWindow()
    }
    
    @objc private func menuToggleFloatingBall() {
        AppState.shared.floatingBallEnabled.toggle()
    }

    @objc private func menuClearHistory() {
        AppState.shared.clearHistory()
    }
    
    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }
}
