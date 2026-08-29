import Foundation
import AppKit
import SwiftUI

@MainActor
public final class FloatingDropWindowController: NSObject, NSWindowDelegate {
    public static let shared = FloatingDropWindowController()
    
    private var floatingPanel: NSPanel?
    public var window: NSPanel? { return floatingPanel }
    
    public override init() {
        super.init()
    }
    
    public func toggleWindow() {
        if let panel = floatingPanel, panel.isVisible {
            dockToMenuBar()
        } else {
            showFloatingWindow()
        }
    }
    
    public func showFloatingWindow() {
        let scale = AppState.shared.uiScale
        if floatingPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: scale.baseWidth, height: scale.baseHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "SqueezeBar"
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.minSize = NSSize(width: scale.baseWidth - 20, height: scale.baseHeight - 40)
            panel.delegate = self
            
            let hostingView = NSHostingView(
                rootView: QuickPopoverView(isDetachedWindow: true)
                    .environmentObject(AppState.shared)
            )
            panel.contentView = hostingView
            panel.center()
            self.floatingPanel = panel
        }
        
        AppState.shared.isDetached = true
        floatingPanel?.level = .floating
        floatingPanel?.hidesOnDeactivate = false
        floatingPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func updateWindowDimensionsForScale(_ scale: UIScaleOption) {
        guard let panel = floatingPanel else { return }
        panel.minSize = NSSize(width: scale.baseWidth - 20, height: scale.baseHeight - 40)
        var frame = panel.frame
        let diff = scale.baseHeight - frame.size.height
        frame.origin.y -= diff
        frame.size = NSSize(width: scale.baseWidth, height: scale.baseHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
    
    public func updatePinState(pinned: Bool) {
        floatingPanel?.level = pinned ? .floating : .normal
    }
    
    public func ensureMinimumDimensions(width: CGFloat, height: CGFloat) {
        guard let panel = floatingPanel else { return }
        var frame = panel.frame
        var needsResize = false
        if frame.size.width < width {
            frame.size.width = width
            needsResize = true
        }
        if frame.size.height < height {
            let diff = height - frame.size.height
            frame.origin.y -= diff // expand downward smoothly
            frame.size.height = height
            needsResize = true
        }
        if needsResize {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
    
    public func dockToMenuBar() {
        AppState.shared.isDetached = false
        floatingPanel?.orderOut(nil)
    }
    
    public func windowWillClose(_ notification: Notification) {
        AppState.shared.isDetached = false
    }
}
