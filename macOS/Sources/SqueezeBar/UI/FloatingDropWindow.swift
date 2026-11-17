import Foundation
import AppKit
import SwiftUI

/// Root of the popover and the detached window. While the window is hidden `live` is false and the
/// tree is empty, so a hidden window does no SwiftUI work on job updates (same cost as never opened).
struct HostedPopoverRoot: View {
    var isDetachedWindow: Bool
    var live: Bool

    var body: some View {
        if live {
            QuickPopoverView(isDetachedWindow: isDetachedWindow)
                .environmentObject(AppState.shared)
        } else {
            Color.clear
        }
    }
}

@MainActor
public final class FloatingDropWindowController: NSObject, NSWindowDelegate {
    public static let shared = FloatingDropWindowController()
    
    private var floatingPanel: NSPanel?
    private var hostingView: NSHostingView<HostedPopoverRoot>?
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
            // Off: AppKit re-walks every SwiftUI responder for drag margins on each job row change.
            // The header carries a WindowDragHandle instead (QuickPopoverView.headerView).
            panel.isMovableByWindowBackground = false
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
            
            let hostingView = NSHostingView(rootView: HostedPopoverRoot(isDetachedWindow: true, live: false))
            panel.contentView = hostingView
            self.hostingView = hostingView
            panel.center()
            self.floatingPanel = panel
        }
        
        AppState.shared.isDetached = true
        // Build the content before ordering front so the window never shows empty.
        if hostingView?.rootView.live == false {
            hostingView?.rootView.live = true
            hostingView?.layoutSubtreeIfNeeded()
        }
        floatingPanel?.level = .floating
        floatingPanel?.hidesOnDeactivate = false
        floatingPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func hide() {
        floatingPanel?.orderOut(nil)
        if hostingView?.rootView.live == true {
            hostingView?.rootView.live = false
            hostingView?.layoutSubtreeIfNeeded()
        }
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
        hide()
    }

    public func dismissDragPresentation() {
        hide()
    }
    
    public func windowWillClose(_ notification: Notification) {
        hide()
    }
}
