import Foundation
import AppKit
import SwiftUI

// MARK: - Liquid Ball Physical Model
@MainActor
public final class LiquidBallModel: ObservableObject {
    public static let shared = LiquidBallModel()
    
    public enum DockEdge: String {
        case left
        case right
    }
    
    @Published public var scaleX: CGFloat = 1.0
    @Published public var scaleY: CGFloat = 1.0
    @Published public var rotationAngle: Double = 0.0
    @Published public var isMoving: Bool = false
    @Published public var isHovered: Bool = false
    @Published public var dockEdge: DockEdge = .right
    @Published public var isTucked: Bool = true
    
    private var tuckTimerTask: Task<Void, Never>?
    
    public func applyMotionVelocity(dx: CGFloat, dy: CGFloat) {
        isMoving = true
        isTucked = false
        cancelTuckTimer()
        
        let speed = sqrt(dx * dx + dy * dy)
        let intensity = min(1.0, speed / 20.0)
        let absDx = abs(dx)
        let absDy = abs(dy)
        let style = AppState.shared.dropBallAnimationStyle
        
        let stretchFactor: CGFloat
        switch style {
        case .calm: stretchFactor = 0.12
        case .standard: stretchFactor = 0.24
        case .exaggerated: stretchFactor = 0.42
        }
        
        var targetScaleX: CGFloat = 1.0
        var targetScaleY: CGFloat = 1.0
        var targetAngle: Double = 0.0
        
        if absDx >= absDy {
            // Horizontal drag: stretch wide, squash tall
            targetScaleX = 1.0 + (stretchFactor * intensity)
            targetScaleY = 1.0 - (stretchFactor * 0.6 * intensity)
            targetAngle = Double(dx > 0 ? 6.0 : -6.0) * intensity
        } else {
            // Vertical drag: stretch tall, squash wide
            targetScaleX = 1.0 - (stretchFactor * 0.6 * intensity)
            targetScaleY = 1.0 + (stretchFactor * intensity)
            targetAngle = Double(dx * 0.18)
        }
        
        withAnimation(.interactiveSpring(response: 0.14, dampingFraction: 0.64)) {
            self.scaleX = targetScaleX
            self.scaleY = targetScaleY
            self.rotationAngle = targetAngle
        }
    }
    
    public func releaseMotion() {
        isMoving = false
        let spring: Animation
        switch AppState.shared.dropBallAnimationStyle {
        case .calm: spring = .spring(response: 0.38, dampingFraction: 0.82)
        case .standard: spring = .spring(response: 0.35, dampingFraction: 0.60, blendDuration: 0.05)
        case .exaggerated: spring = .spring(response: 0.42, dampingFraction: 0.42, blendDuration: 0.08)
        }
        withAnimation(spring) {
            self.scaleX = 1.0
            self.scaleY = 1.0
            self.rotationAngle = 0.0
        }
    }
    
    public func revealFromTuck() {
        cancelTuckTimer()
        let spring: Animation
        switch AppState.shared.dropBallAnimationStyle {
        case .calm: spring = .spring(response: 0.38, dampingFraction: 0.82)
        case .standard: spring = .spring(response: 0.35, dampingFraction: 0.58, blendDuration: 0.05)
        case .exaggerated: spring = .spring(response: 0.40, dampingFraction: 0.44, blendDuration: 0.08)
        }
        withAnimation(spring) {
            self.isTucked = false
        }
    }
    
    public func scheduleAutoTuck(afterSeconds: Double = 1.8) {
        cancelTuckTimer()
        tuckTimerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if !self.isMoving && !AppState.shared.isProcessing && !self.isHovered {
                let spring: Animation
                switch AppState.shared.dropBallAnimationStyle {
                case .calm: spring = .spring(response: 0.45, dampingFraction: 0.88)
                case .standard: spring = .spring(response: 0.40, dampingFraction: 0.72)
                case .exaggerated: spring = .spring(response: 0.44, dampingFraction: 0.56)
                }
                withAnimation(spring) {
                    self.isTucked = true
                }
            }
        }
    }
    
    public func cancelTuckTimer() {
        tuckTimerTask?.cancel()
        tuckTimerTask = nil
    }
}

// MARK: - Floating Ball Hosting View with Proximity Snapping & Drag Physics
public final class FloatingBallHostingView: NSHostingView<FloatingBallView> {
    private var initialMouseLocation: CGPoint = .zero
    private var initialWindowOrigin: CGPoint = .zero
    private var lastMouseLocation: CGPoint = .zero
    private var isDraggingWindow = false
    private var trackingArea: NSTrackingArea?
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    public override func mouseEntered(with event: NSEvent) {
        Task { @MainActor in
            LiquidBallModel.shared.isHovered = true
            LiquidBallModel.shared.revealFromTuck()
        }
    }
    
    public override func mouseMoved(with event: NSEvent) {
        Task { @MainActor in
            LiquidBallModel.shared.isHovered = true
            LiquidBallModel.shared.revealFromTuck()
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        Task { @MainActor in
            LiquidBallModel.shared.isHovered = false
            LiquidBallModel.shared.scheduleAutoTuck(afterSeconds: 1.8)
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        lastMouseLocation = initialMouseLocation
        initialWindowOrigin = window?.frame.origin ?? .zero
        isDraggingWindow = false
        Task { @MainActor in
            LiquidBallModel.shared.revealFromTuck()
        }
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - initialMouseLocation.x
        let deltaY = currentMouse.y - initialMouseLocation.y
        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
        
        if distance > 2.0 {
            isDraggingWindow = true
            
            // Move window directly on GPU
            let newOrigin = CGPoint(
                x: initialWindowOrigin.x + deltaX,
                y: initialWindowOrigin.y + deltaY
            )
            window?.setFrameOrigin(newOrigin)
            
            // Update dynamic liquid squash and stretch physics
            let stepDx = currentMouse.x - lastMouseLocation.x
            let stepDy = currentMouse.y - lastMouseLocation.y
            Task { @MainActor in
                LiquidBallModel.shared.applyMotionVelocity(dx: stepDx, dy: stepDy)
            }
            lastMouseLocation = currentMouse
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        if isDraggingWindow {
            Task { @MainActor in
                LiquidBallModel.shared.releaseMotion()
                FloatingBallController.shared.snapToNearestScreenEdge()
            }
            isDraggingWindow = false
        } else {
            // Click without drag toggles the main popover/window
            Task { @MainActor in
                FloatingBallController.shared.toggleMainPopover()
                LiquidBallModel.shared.scheduleAutoTuck(afterSeconds: 2.5)
            }
        }
    }
}

// MARK: - Floating Ball Window Controller
@MainActor
public final class FloatingBallController: NSObject, NSWindowDelegate {
    public static let shared = FloatingBallController()
    
    private var ballPanel: NSPanel?
    private let ballSize: CGFloat = 160
    private var snapTimer: Timer?
    
    private struct Keys {
        static let ballOriginX = "squeezebar.floatingBallOriginX"
        static let ballOriginY = "squeezebar.floatingBallOriginY"
        static let dockEdge = "squeezebar.dockEdge"
    }
    
    public override init() {
        super.init()
    }
    
    public var currentPanelOrigin: CGPoint? {
        return ballPanel?.frame.origin
    }
    
    public func setPanelOrigin(_ origin: CGPoint) {
        guard let panel = ballPanel else { return }
        panel.setFrameOrigin(origin)
    }
    
    public func saveCurrentPosition() {
        guard let panel = ballPanel else { return }
        let origin = panel.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: Keys.ballOriginX)
        UserDefaults.standard.set(Double(origin.y), forKey: Keys.ballOriginY)
        UserDefaults.standard.set(LiquidBallModel.shared.dockEdge.rawValue, forKey: Keys.dockEdge)
    }
    
    public func snapToNearestScreenEdge() {
        guard let panel = ballPanel else { return }
        let currentOrigin = panel.frame.origin
        
        // Find exact screen under the ball's center
        let ballCenter = CGPoint(x: currentOrigin.x + (ballSize / 2), y: currentOrigin.y + (ballSize / 2))
        let screen = NSScreen.screens.first(where: { NSPointInRect(ballCenter, $0.frame) }) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        
        let dockEdge: LiquidBallModel.DockEdge = (ballCenter.x < visibleFrame.midX) ? .left : .right
        LiquidBallModel.shared.dockEdge = dockEdge
        
        // In 160x160 canvas: 58px orb is centered at x=80, spanning [51, 109].
        // Left dock anchors left orb edge (51) to screen minX: targetX = minX - 51
        // Right dock anchors right orb edge (109) to screen maxX: targetX = maxX - 109
        let targetX: CGFloat = (dockEdge == .left) ? visibleFrame.minX - 51 : visibleFrame.maxX - 109
        let targetY: CGFloat = max(visibleFrame.minY + 20, min(visibleFrame.maxY - ballSize - 20, currentOrigin.y))
        let targetOrigin = CGPoint(x: targetX, y: targetY)
        
        // Smooth frame interpolation animation
        snapTimer?.invalidate()
        let startOrigin = currentOrigin
        let startTime = CACurrentMediaTime()
        let duration: Double = 0.24
        
        snapTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self, let panel = self.ballPanel else {
                    timer.invalidate()
                    return
                }
                
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1.0, elapsed / duration)
                let t = 1.0 - pow(1.0 - progress, 3.0)
                
                let curX = startOrigin.x + (targetOrigin.x - startOrigin.x) * CGFloat(t)
                let curY = startOrigin.y + (targetOrigin.y - startOrigin.y) * CGFloat(t)
                panel.setFrameOrigin(CGPoint(x: curX, y: curY))
                
                if progress >= 1.0 {
                    timer.invalidate()
                    panel.setFrameOrigin(targetOrigin)
                    self.saveCurrentPosition()
                    LiquidBallModel.shared.scheduleAutoTuck(afterSeconds: 1.2)
                }
            }
        }
    }
    
    public func updateVisibility() {
        if AppState.shared.floatingBallEnabled {
            show()
        } else {
            hide()
        }
    }
    
    public func show() {
        if ballPanel == nil {
            createPanel()
        }
        
        ballPanel?.level = .floating
        ballPanel?.orderFrontRegardless()
        LiquidBallModel.shared.isTucked = true
        snapToNearestScreenEdge()
    }
    
    public func hide() {
        snapTimer?.invalidate()
        ballPanel?.orderOut(nil)
    }
    
    public func toggle() {
        if let panel = ballPanel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }
    
    public func toggleMainPopover() {
        if AppState.shared.isDetached {
            FloatingDropWindowController.shared.showFloatingWindow()
        } else {
            StatusBarController.sharedInstance?.showPopover(sender: nil)
        }
    }
    
    private func createPanel() {
        let initialRect = calculateInitialFrame()
        
        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "SqueezeBar Floating Basket"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.ignoresMouseEvents = false
        panel.delegate = self
        
        let hostingView = FloatingBallHostingView(rootView: FloatingBallView())
        hostingView.frame = NSRect(x: 0, y: 0, width: ballSize, height: ballSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        panel.contentView = hostingView
        
        self.ballPanel = panel
    }
    
    public func windowDidMove(_ notification: Notification) {
        saveCurrentPosition()
    }
    
    private func calculateInitialFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        let savedY = UserDefaults.standard.double(forKey: Keys.ballOriginY)
        let initialY: CGFloat
        if savedY > visibleFrame.minY + 20 && savedY < visibleFrame.maxY - ballSize - 20 {
            initialY = CGFloat(savedY)
        } else {
            initialY = visibleFrame.midY - (ballSize / 2)
        }
        
        let rawEdge = UserDefaults.standard.string(forKey: Keys.dockEdge) ?? "right"
        let dockEdge = LiquidBallModel.DockEdge(rawValue: rawEdge) ?? .right
        LiquidBallModel.shared.dockEdge = dockEdge
        
        let initialX: CGFloat = (dockEdge == .left) ? visibleFrame.minX - 51 : visibleFrame.maxX - 109
        
        return NSRect(x: initialX, y: initialY, width: ballSize, height: ballSize)
    }
}
