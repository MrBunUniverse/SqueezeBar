import Foundation
import AppKit
import SwiftUI

@MainActor
public final class StatusBarController: NSObject {
    public static weak var sharedInstance: StatusBarController?
    
    // MARK: - Dimensions
    private let normalWidth: CGFloat = 34.0
    private let barHeight: CGFloat = 24.0
    
    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private var dropView: StatusItemDropView!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    
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
                NSPasteboard.PasteboardType("public.file-url")
            ])
        }
    }
    
    // MARK: - Dynamic Status Item Sizing
    public var idleWidth: CGFloat {
        let state = AppState.shared
        
        switch state.menuBarDisplayStyle {
        case .iconOnly:
            return normalWidth
        case .minimalMonochrome:
            return 28.0
        case .liveSavings:
            let savedStr = ByteCountFormatter.string(fromByteCount: state.totalBytesSaved, countStyle: .file)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            let textWidth = (savedStr as NSString).size(withAttributes: [.font: font]).width
            return normalWidth + textWidth + 10.0
        }
    }
    
    public func updateStatusItemLength() {
        let target = idleWidth
        if statusItem.length != target {
            statusItem.length = target
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
    
    public func showPopover(sender: NSView? = nil) {
        if AppState.shared.isDetached {
            FloatingDropWindowController.shared.showFloatingWindow()
            return
        }
        
        let targetView = sender ?? statusItem.button ?? dropView
        if let button = targetView {
            popover.behavior = AppState.shared.isPinned ? .applicationDefined : .transient
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            
            if let window = popover.contentViewController?.view.window {
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
        
        let openItem = NSMenuItem(title: "Open SqueezeBar Hub", action: #selector(menuOpenHub), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        let detachItem = NSMenuItem(
            title: AppState.shared.isDetached ? "Dock to Menu Bar" : "Detach Floating Window",
            action: #selector(menuToggleDetach),
            keyEquivalent: "d"
        )
        detachItem.target = self
        menu.addItem(detachItem)
        
        let ballItem = NSMenuItem(
            title: AppState.shared.floatingBallEnabled ? "Hide Desktop Drop Ball" : "Show Desktop Drop Ball",
            action: #selector(menuToggleFloatingBall),
            keyEquivalent: "b"
        )
        ballItem.target = self
        menu.addItem(ballItem)
        
        let clearItem = NSMenuItem(title: "Clear Compression History", action: #selector(menuClearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit SqueezeBar", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
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
