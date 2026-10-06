import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct FloatingBallView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var liquidModel = LiquidBallModel.shared
    
    @State private var isHovered: Bool = false
    @State private var isDropTargeted: Bool = false
    
    @Environment(\.displayScale) private var displayScale

    // On 1x displays a hairline rim centered on the orb's edge splits across two pixel rows and
    // reads as a flat cut where the circle is tangent to the pixel grid. Draw it wider and fully
    // inside the edge there so it antialiases as a curve.
    private var rimLineWidth: CGFloat { displayScale < 2 ? 1.5 : 0.9 }
    private var rimInset: CGFloat { displayScale < 2 ? rimLineWidth / 2 : 0 }

    public init() {}
    
    private var isTuckedState: Bool {
        liquidModel.isTucked && !isHovered && !isDropTargeted && !state.isProcessing && !liquidModel.isMoving
    }
    
    private var isRightEdge: Bool {
        liquidModel.dockEdge == .right
    }

    private var orbShape: DockedBallShape {
        DockedBallShape(tuckProgress: isTuckedState ? 1 : 0, isRightEdge: isRightEdge)
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
            // Keep the sides compressed while letting more of the rounded tip show.
            return isRightEdge ? FloatingBallController.tuckedOffset : -FloatingBallController.tuckedOffset
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
        let base: CGFloat = isTuckedState ? FloatingBallController.tuckedScaleX : (isDropTargeted ? (hoverScale * 1.08) : (isHovered ? hoverScale : 1.0))
        return base * liquidModel.scaleX
    }
    
    private var targetScaleY: CGFloat {
        let hoverScale: CGFloat
        switch state.dropBallAnimationStyle {
        case .calm: hoverScale = 1.04
        case .standard: hoverScale = 1.08
        case .exaggerated: hoverScale = 1.15
        }
        let base: CGFloat = isTuckedState ? 1.06 : (isDropTargeted ? (hoverScale * 1.08) : (isHovered ? hoverScale : 1.0))
        return base * liquidModel.scaleY
    }
    
    public var body: some View {
        ZStack {
            liquidGlassOrb
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("SqueezeBar DropBall")
                .accessibilityHint("Drop files here to compress them. Click to open SqueezeBar.")
                .contentShape(orbShape)
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
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                    handleDroppedProviders(providers)
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
        .frame(width: FloatingBallController.panelSize, height: FloatingBallController.panelSize)
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted {
                liquidModel.revealFromTuck()
            }
        }
        .font(.system(.body, design: .rounded))
    }
    
    // MARK: - Pure Apple Liquid Glass Orb (Lumen Architecture)
    private var liquidGlassOrb: some View {
        ZStack {
            glassPane
            
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
                .scaleEffect(x: isTuckedState ? 0.84 : 1, y: isTuckedState ? 0.90 : 1)
        }
        .frame(width: FloatingBallController.orbSize, height: FloatingBallController.orbSize)
        .offset(x: targetXOffset)
        .scaleEffect(x: targetScaleX, y: targetScaleY)
        .rotationEffect(.degrees(liquidModel.rotationAngle))
        .opacity(isTuckedState ? 0.90 : 1.0)
        .animation(currentRevealSpring, value: isTuckedState)
        .animation(currentRevealSpring, value: isHovered)
        .animation(currentRevealSpring, value: isDropTargeted)
        .animation(currentRevealSpring, value: state.isProcessing)
    }
    
    // Clear bubble-like glass without blur: whatever is behind the ball stays sharp.
    // A faint body, a soft edge glow, a thin rim and two small highlights keep it natural.
    private var glassPane: some View {
        let shape = orbShape
        return shape
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.07), .white.opacity(0.01), .white.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                // Soft edge glow where the bubble curves away.
                shape
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.0), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 5
                    )
                    .clipShape(shape)
                    .allowsHitTesting(false)
            )
            .overlay(
                // Soft highlight where light enters.
                RadialGradient(
                    colors: [.white.opacity(0.42), .white.opacity(0.06), .clear],
                    center: UnitPoint(x: 0.26, y: 0.12),
                    startRadius: 0,
                    endRadius: 20
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            .overlay(
                // Faint bounce at the lower-right.
                RadialGradient(
                    colors: [.white.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.78, y: 0.92),
                    startRadius: 0,
                    endRadius: 18
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            .overlay(
                Group {
                    if isDropTargeted {
                        shape.stroke(state.accentColor, lineWidth: 1.5)
                            .padding(rimInset)
                    } else {
                        shape.stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.65), .white.opacity(0.08), .white.opacity(0.32)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: rimLineWidth
                        )
                        .padding(rimInset)
                    }
                }
                .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
    }
    
    @ViewBuilder
    private var centerContent: some View {
        if state.showFailureBadge {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.red)
                .shadow(color: Color.red.opacity(0.60), radius: 6)
                .shadow(color: .black.opacity(0.30), radius: 2)
                .transition(.scale.combined(with: .opacity))
        } else if state.showSuccessBadge {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .bold, design: .rounded))
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
                
                Image(systemName: state.areAllPausableJobsPaused ? "pause.fill" : "bolt.horizontal.fill")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(state.accentColor)
            }
        } else if isDropTargeted {
            VStack(spacing: 2) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
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

struct DockedBallShape: Shape {
    var tuckProgress: CGFloat
    var isRightEdge: Bool

    var animatableData: CGFloat {
        get { tuckProgress }
        set { tuckProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(1, max(0, tuckProgress))
        func blend(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * t }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        let topX = blend(0.5, 0.72)
        let shoulderTop = blend(0.5, 0.14)
        let shoulderBottom = 1 - shoulderTop
        var path = Path()
        path.move(to: point(topX, 0))
        path.addCurve(to: point(1, shoulderTop), control1: point(blend(0.776, 0.82), 0), control2: point(1, blend(0.224, 0.04)))
        path.addLine(to: point(1, shoulderBottom))
        path.addCurve(to: point(topX, 1), control1: point(1, blend(0.776, 0.96)), control2: point(blend(0.776, 0.82), 1))
        path.addCurve(to: point(0, 0.5), control1: point(blend(0.224, 0.28), 1), control2: point(0, blend(0.776, 0.76)))
        path.addCurve(to: point(topX, 0), control1: point(0, blend(0.224, 0.24)), control2: point(blend(0.224, 0.28), 0))
        path.closeSubpath()

        return isRightEdge ? path : path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }
}
