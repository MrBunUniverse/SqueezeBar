import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct FloatingBallView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var jobs = AppState.shared.jobs
    @ObservedObject private var liquidModel = LiquidBallModel.shared
    
    @State private var isHovered: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var burstProgress: CGFloat = 0
    
    @Environment(\.displayScale) private var displayScale

    // On 1x displays a hairline rim centered on the orb's edge splits across two pixel rows and
    // reads as a flat cut where the circle is tangent to the pixel grid. Draw it wider and fully
    // inside the edge there so it antialiases as a curve.
    private var rimLineWidth: CGFloat { displayScale < 2 ? 1.5 : 0.9 }
    private var rimInset: CGFloat { displayScale < 2 ? rimLineWidth / 2 : 0 }

    public init() {}
    
    private var isTuckedState: Bool {
        liquidModel.isTucked && !isHovered && !isDropTargeted && !jobs.isProcessing && !liquidModel.isMoving
    }
    
    private var isRightEdge: Bool {
        liquidModel.dockEdge == .right
    }

    private var orbShape: DockedBallShape {
        DockedBallShape(tuckProgress: isTuckedState ? 1 : 0, isRightEdge: isRightEdge)
    }
    
    private var currentRevealSpring: Animation {
        .spring(response: 0.40, dampingFraction: 0.44, blendDuration: 0.08)
    }
    
    // Smooth X Offset: Tucked vs Popped/Revealed
    private var targetXOffset: CGFloat {
        if liquidModel.isMoving {
            return 0
        }
        let popoutOffset: CGFloat = 22

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
        let hoverScale: CGFloat = 1.15
        let base: CGFloat = isTuckedState ? FloatingBallController.tuckedScaleX : (isDropTargeted ? (hoverScale * 1.08) : (isHovered ? hoverScale : 1.0))
        return base * liquidModel.scaleX
    }
    
    private var targetScaleY: CGFloat {
        let hoverScale: CGFloat = 1.15
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

                    Divider()

                    Button("Quit SqueezeBar") {
                        NSApplication.shared.terminate(nil)
                    }
                }

            if liquidModel.isBurst {
                // Centred on where the orb was drawn, in its outline and at its size.
                PopBurst(progress: burstProgress, shape: orbShape, scaleX: targetScaleX, scaleY: targetScaleY, accent: state.accentColor)
                    .offset(x: targetXOffset * targetScaleX)
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: LiquidBallModel.burstDuration)) {
                            burstProgress = 1
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
            if jobs.isProcessing {
                Circle()
                    .trim(from: 0.0, to: max(0.05, CGFloat(min(1.0, jobs.overallProgress))))
                    .stroke(
                        state.accentColor,
                        style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                    .animation(.linear(duration: 0.2), value: jobs.overallProgress)
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
        .opacity(liquidModel.isBurst ? 0 : (isTuckedState ? 0.90 : 1.0))
        .animation(currentRevealSpring, value: isTuckedState)
        .animation(currentRevealSpring, value: isHovered)
        .animation(currentRevealSpring, value: isDropTargeted)
        .animation(currentRevealSpring, value: jobs.isProcessing)
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
        } else if jobs.isProcessing {
            if state.areAllPausableJobsPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(state.accentColor)
            } else {
                SqueezeProgressMark(progress: jobs.overallProgress, color: state.accentColor, restColor: Color.white.opacity(0.45))
                    .frame(width: 28, height: 33)
                    .shadow(color: state.accentColor.opacity(0.55), radius: 5)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                    .accessibilityLabel("\(Int(jobs.overallProgress * 100))%")
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
            SqueezeClampShape()
                .fill(state.accentColor)
                .frame(width: 28, height: 33)
                .shadow(color: state.accentColor.opacity(0.65), radius: 6, x: 0, y: 1)
                .shadow(color: .black.opacity(0.40), radius: 3, x: 0, y: 1.5)
        }
    }
    
    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
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

// The quit pop: the bubble's outline snaps outward while droplets scatter and fade.
// `progress` runs 0...1 at a constant rate; each part applies its own easing to it.
struct PopBurst: View, Animatable {
    var progress: CGFloat
    let shape: DockedBallShape
    let scaleX: CGFloat
    let scaleY: CGFloat
    let accent: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    // Fixed layout so every pop looks the same: angle in degrees, droplet diameter, travel distance.
    private static let droplets: [(angle: Double, size: CGFloat, travel: CGFloat)] = [
        (8, 5.5, 24), (49, 3.5, 18), (86, 6, 26), (128, 4, 20), (171, 5, 23),
        (212, 3.5, 19), (253, 6, 25), (297, 4, 21), (334, 5, 22)
    ]

    var body: some View {
        let radius = FloatingBallController.orbSize / 2
        // Fast off the rim, slowing as it goes.
        let flight = 1 - pow(1 - progress, 3)
        // Stays bright for the first half, gone by the end.
        let fade = 1 - progress * progress
        ZStack {
            shape
                .stroke(.white.opacity(0.75 * (1 - progress)), lineWidth: 1.4 - progress)
                .frame(width: radius * 2, height: radius * 2)
                .scaleEffect(x: scaleX * (1 + 0.32 * flight), y: scaleY * (1 + 0.32 * flight))

            ForEach(Self.droplets.indices, id: \.self) { index in
                let droplet = Self.droplets[index]
                let radians = droplet.angle * .pi / 180
                let travel = droplet.travel * flight
                Circle()
                    .fill(index % 3 == 0 ? accent : Color.white.opacity(0.85))
                    .frame(width: droplet.size, height: droplet.size)
                    .scaleEffect(1 - 0.65 * progress)
                    .offset(
                        x: cos(radians) * (radius * scaleX + travel),
                        // Droplets sag as they fly, as if they had weight.
                        y: sin(radians) * (radius * scaleY + travel) + 5 * progress * progress
                    )
                    .opacity(fade)
            }
        }
        // Keeps the white parts readable on a light wallpaper, as the orb's own shadow does.
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
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
