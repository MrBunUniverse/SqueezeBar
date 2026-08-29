import Foundation
import AppKit
import SwiftUI

@MainActor
public final class CustomColorPanelManager: NSObject {
    public static let shared = CustomColorPanelManager()
    
    private var observer: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?
    
    public override init() {
        super.init()
    }
    
    public func toggle(anchorWindow: NSWindow? = nil, initialColor: Color? = nil) {
        if NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible {
            close()
        } else {
            show(anchorWindow: anchorWindow, initialColor: initialColor)
        }
    }
    
    public func show(anchorWindow: NSWindow? = nil, initialColor: Color? = nil) {
        let panel = NSColorPanel.shared
        
        // Configure panel options
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.mode = .wheel
        
        if let initialColor = initialColor {
            let nsColor = NSColor(initialColor).usingColorSpace(.sRGB) ?? NSColor.blue
            panel.color = nsColor
        }
        
        // Find best reference window for anchoring
        let targetWindow = anchorWindow 
            ?? NSApp.keyWindow 
            ?? FloatingDropWindowController.shared.window 
            ?? StatusBarController.sharedInstance?.window
            ?? NSApp.windows.first(where: { $0.isVisible && !$0.isKind(of: NSColorPanel.self) })
        
        if let window = targetWindow {
            let windowFrame = window.frame
            let panelSize = panel.frame.size
            
            // Image 3 positioning: centered horizontally with the SqueezeBar window,
            // anchored directly under the Theme Accent Color row (~170px below top)
            let targetX = windowFrame.minX + max(0, (windowFrame.width - panelSize.width) / 2)
            let targetY = windowFrame.maxY - 170
            
            if let screen = window.screen ?? NSScreen.main {
                let screenFrame = screen.visibleFrame
                let boundedX = min(max(screenFrame.minX + 8, targetX), screenFrame.maxX - panelSize.width - 8)
                let boundedY = min(max(screenFrame.minY + panelSize.height + 8, targetY), screenFrame.maxY - 8)
                panel.setFrameTopLeftPoint(NSPoint(x: boundedX, y: boundedY))
            } else {
                panel.setFrameTopLeftPoint(NSPoint(x: targetX, y: targetY))
            }
        }
        
        // Set up live listener if not already set
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSColorPanel.colorDidChangeNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleColorChange()
                }
            }
        }
        
        // Register window close observer to restore popover behavior
        if windowCloseObserver == nil {
            windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: panel,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    StatusBarController.sharedInstance?.onColorPanelClose()
                }
            }
        }
        
        StatusBarController.sharedInstance?.onColorPanelOpen()
        
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelAction(_:)))
        panel.level = .floating
        panel.orderFront(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func close() {
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.orderOut(nil)
        }
        StatusBarController.sharedInstance?.onColorPanelClose()
    }
    
    @objc private func colorPanelAction(_ sender: Any?) {
        handleColorChange()
    }
    
    private func handleColorChange() {
        let color = NSColorPanel.shared.color
        guard let srgb = color.usingColorSpace(.sRGB) else { return }
        
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        let hex = String(format: "%02X%02X%02X", r, g, b)
        
        withAnimation(.spring(response: 0.20, dampingFraction: 0.80)) {
            AppState.shared.customAccentHex = hex
            if AppState.shared.accentTheme != .custom {
                AppState.shared.accentTheme = .custom
            }
        }
    }
}
