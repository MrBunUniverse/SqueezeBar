import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct FloatingBallView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var liquidModel = LiquidBallModel.shared
    
    @State private var isHovered: Bool = false
    @State private var isDropTargeted: Bool = false
    
    public init() {}
    
    private var isTuckedState: Bool {
        liquidModel.isTucked && !isHovered && !isDropTargeted && !state.isProcessing && !liquidModel.isMoving
    }
    
    private var isRightEdge: Bool {
        liquidModel.dockEdge == .right
    }
    
    private var currentRevealSpring: Animation {
        switch state.dropBallAnimationStyle {
        case .calm: return .spring(response: 0.38, dampingFraction: 0.82)
        case .standard: return .spring(response: 0.35, dampingFraction: 0.58, blendDuration: 0.05)
        case .exaggerated: return .spring(response: 0.40, dampingFraction: 0.44, blendDuration: 0.08)
        }
    }
    
    // Smooth X Offset: Tucked vs Popped/Revealed
    private var targetXOffset: CGFloat {
        if liquidModel.isMoving {
            return 0
        }
        let popoutOffset: CGFloat
        switch state.dropBallAnimationStyle {
        case .calm: popoutOffset = 10
        case .standard: popoutOffset = 16
        case .exaggerated: popoutOffset = 22
        }
        
        if isTuckedState {
            // Tucked: sphere rests as a sleek crystal glass bead handle on the screen edge
            return isRightEdge ? 20 : -20
        } else {
            // Popped out: sphere gracefully floats with space from the bezel
            return isRightEdge ? -popoutOffset : popoutOffset
        }
    }
    
    // Fluid Dynamic Scale (Stretch & Squash Physics)
    private var targetScaleX: CGFloat {
        let hoverScale: CGFloat
        switch state.dropBallAnimationStyle {
        case .calm: hoverScale = 1.04
        case .standard: hoverScale = 1.08
        case .exaggerated: hoverScale = 1.15
        }
        let base: CGFloat = isTuckedState ? 0.94 : (isDropTargeted ? (hoverScale * 1.08) : (isHovered ? hoverScale : 1.0))
        return base * liquidModel.scaleX
    }
    
    private var targetScaleY: CGFloat {
        let hoverScale: CGFloat
        switch state.dropBallAnimationStyle {
        case .calm: hoverScale = 1.04
        case .standard: hoverScale = 1.08
        case .exaggerated: hoverScale = 1.15
        }
        let base: CGFloat = isTuckedState ? 1.03 : (isDropTargeted ? (hoverScale * 1.08) : (isHovered ? hoverScale : 1.0))
        return base * liquidModel.scaleY
    }
    
    public var body: some View {
        ZStack {
            liquidGlassOrb
        }
        // 160x160 canvas provides ample headroom so exaggerated bounce/stretch never gets clipped
        .frame(width: 160, height: 160, alignment: .center)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                isHovered = hovering
                liquidModel.isHovered = hovering
            }
            if hovering {
                liquidModel.revealFromTuck()
            } else {
                liquidModel.scheduleAutoTuck(afterSeconds: 1.8)
            }
        }
        // File Drop Support (Desktop Basket)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted {
                liquidModel.revealFromTuck()
            }
        }
        .contextMenu {
            Button("Open SqueezeBar") {
                FloatingBallController.shared.toggleMainPopover()
            }
            
            Divider()
            
            Button("Hide DropBall") {
                withAnimation {
                    AppState.shared.floatingBallEnabled = false
                }
            }
        }
    }
    
    // MARK: - Pure Apple Liquid Glass Orb (Lumen Architecture)
    private var liquidGlassOrb: some View {
        ZStack {
            // Pure Apple Liquid Glass (Clean background so desktop optical refraction works directly)
            if #available(macOS 26.0, *) {
                glassPane
            } else {
                fallbackGlassPane
            }
            
            // Processing Circular Progress Arc
            if state.isProcessing {
                Circle()
                    .trim(from: 0.0, to: max(0.05, CGFloat(min(1.0, state.overallProgress))))
                    .stroke(
                        state.accentColor,
                        style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                    .animation(.linear(duration: 0.2), value: state.overallProgress)
            }
            
            // Floating Jewel Emblem suspended inside the Glass Core
            centerContent
                .offset(x: isTuckedState ? (isRightEdge ? -4 : 4) : 0)
        }
        .frame(width: 58, height: 58)
        .offset(x: targetXOffset)
        .scaleEffect(x: targetScaleX, y: targetScaleY)
        .rotationEffect(.degrees(liquidModel.rotationAngle))
        .opacity(isTuckedState ? 0.90 : 1.0)
        .animation(currentRevealSpring, value: liquidModel.isTucked)
        .animation(currentRevealSpring, value: isHovered)
        .animation(currentRevealSpring, value: isDropTargeted)
        .animation(currentRevealSpring, value: state.isProcessing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.dropBallGlassStyle)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.dropBallClarity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.dropBallFrost)
    }
    
    @available(macOS 26.0, *)
    private var glassPane: some View {
        let shape = Circle()
        let opacityTint = (1.0 - state.dropBallClarity) * 0.85
        return Rectangle()
            .fill(.clear)
            .glassEffect(Glass.clear, in: shape)
            .overlay(shape.fill(Color.black.opacity(opacityTint)).allowsHitTesting(false))
            .overlay(shape.fill(Color.white.opacity(state.dropBallFrost)).allowsHitTesting(false))
            .overlay(depthShading.clipShape(shape).allowsHitTesting(false))
            .overlay(sheenShading.clipShape(shape).allowsHitTesting(false))
            .overlay(
                Group {
                    if isDropTargeted {
                        shape.strokeBorder(state.accentColor, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    } else if state.dropBallGlassStyle.rimWidth > 0 && state.dropBallRim > 0 {
                        shape.strokeBorder(Color.primary.opacity(state.dropBallRim), lineWidth: state.dropBallGlassStyle.rimWidth)
                            .allowsHitTesting(false)
                    }
                }
            )
    }
    
    private var fallbackGlassPane: some View {
        let shape = Circle()
        let opacityTint = (1.0 - state.dropBallClarity) * 0.85
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.black.opacity(opacityTint)).allowsHitTesting(false))
            .overlay(shape.fill(Color.white.opacity(state.dropBallFrost)).allowsHitTesting(false))
            .overlay(depthShading.clipShape(shape).allowsHitTesting(false))
            .overlay(sheenShading.clipShape(shape).allowsHitTesting(false))
            .overlay(
                Group {
                    if isDropTargeted {
                        shape.strokeBorder(state.accentColor, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    } else if state.dropBallGlassStyle.rimWidth > 0 && state.dropBallRim > 0 {
                        shape.strokeBorder(Color.primary.opacity(state.dropBallRim), lineWidth: state.dropBallGlassStyle.rimWidth)
                            .allowsHitTesting(false)
                    }
                }
            )
    }
    
    private var depthShading: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.85),
                .black.opacity(0.05),
                .black.opacity(0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(state.dropBallDepth)
    }

    private var sheenShading: some View {
        RadialGradient(
            colors: [.white, .white.opacity(0)],
            center: UnitPoint(x: 0.18, y: 0.04),
            startRadius: 0,
            endRadius: 70
        )
        .opacity(state.dropBallSheen * 3.0)
    }
    
    @ViewBuilder
    private var centerContent: some View {
        if state.showSuccessBadge {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.green)
                .shadow(color: Color.green.opacity(0.60), radius: 6)
                .shadow(color: .black.opacity(0.30), radius: 2)
                .transition(.scale.combined(with: .opacity))
        } else if state.isProcessing {
            VStack(spacing: 1) {
                Text("\(Int(state.overallProgress * 100))%")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(state.accentColor)
                    .shadow(color: state.accentColor.opacity(0.60), radius: 4)
                
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(state.accentColor)
            }
        } else if isDropTargeted {
            VStack(spacing: 2) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(state.accentColor)
                    .shadow(color: state.accentColor.opacity(0.70), radius: 6)
                Text("DROP")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
        } else {
            // Bold vibrant emblem with luminous ambient glow
            Image(systemName: "archivebox.fill")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundColor(state.accentColor)
                .shadow(color: state.accentColor.opacity(0.65), radius: 6, x: 0, y: 1)
                .shadow(color: .black.opacity(0.40), radius: 3, x: 0, y: 1.5)
        }
    }
    
    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            
            if self.state.hapticEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            
            Task {
                await MediaCompressionEngine.shared.processDroppedURLs(urls)
            }
        }
        
        return true
    }
}
