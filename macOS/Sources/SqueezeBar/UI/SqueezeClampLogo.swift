import SwiftUI
import AppKit

// MARK: - Striped "S" Mark
// Five rounded bars whose left/right stubs form an S. Same geometry as the app icon
// (see scripts/generate_app_icon.swift). Name kept from the old clamp logo.
public struct SqueezeClampShape: Shape {
    public init() {}

    /// Bars as (x0, x1, y) in a 1024 design grid; all bars are `barHeight` tall.
    private static let bars: [(CGFloat, CGFloat, CGFloat)] = [
        (290, 800, 170),
        (224, 484, 312),
        (224, 800, 454),
        (540, 800, 596),
        (224, 734, 738)
    ]
    private static let barHeight: CGFloat = 116
    private static let designRect = CGRect(x: 224, y: 170, width: 576, height: 684)

    public static let barCount = bars.count

    /// Path for a single bar, so callers can style each one separately.
    public func barPath(_ index: Int, in rect: CGRect) -> Path {
        let (x0, x1, y) = Self.bars[index]
        let design = Self.designRect
        let scale = min(rect.width / design.width, rect.height / design.height)
        let ox = rect.midX - design.width * scale / 2
        let oy = rect.midY - design.height * scale / 2
        let radius = Self.barHeight * scale / 2
        let bar = CGRect(
            x: ox + (x0 - design.minX) * scale,
            y: oy + (y - design.minY) * scale,
            width: (x1 - x0) * scale,
            height: Self.barHeight * scale
        )
        return Path(roundedRect: bar, cornerSize: CGSize(width: radius, height: radius))
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<Self.barCount { path.addPath(barPath(i, in: rect)) }
        return path
    }
}

// MARK: - Scanning Wave
/// The S mark with a slow, soft light that sweeps top to bottom: each bar brightens a little as the
/// wave passes, then eases back down. Static when Reduce Motion is on.
struct SqueezeWaveMark: View {
    /// Resting colour of the bars.
    var base: Color = .white
    /// Colour a bar glows toward as the wave passes over it.
    var lit: Color = .white
    var restOpacity: Double = 0.20
    var peakOpacity: Double = 0.50
    /// Seconds for one full sweep, including a short rest before the next.
    var period: Double = 6.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            restMarks
        } else {
            // Core Animation runs the sweep in the render server: no SwiftUI updates while it plays.
            // Inside a GeometryReader like the static marks, so both lay out (and baseline-align) the same.
            GeometryReader { _ in WaveLayers(mark: self).allowsHitTesting(false) }
        }
    }

    private var restMarks: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let shape = SqueezeClampShape()
            ZStack {
                ForEach(0..<SqueezeClampShape.barCount, id: \.self) { i in
                    shape.barPath(i, in: rect).fill(color(level: 0))
                }
            }
        }
    }

    /// Bar colour for a wave level (0 at rest, 1 at the peak).
    func color(level: Double) -> Color {
        base.mix(with: lit, by: level).opacity(restOpacity + (peakOpacity - restOpacity) * level)
    }

    /// 0 at rest, 1 when the wave is centred on bar `i`, eased in between. `phase` is 0...1 of one period.
    static func level(forBar i: Int, phase: Double) -> Double {
        let n = Double(SqueezeClampShape.barCount)
        // Wave centre travels from above the first bar to below the last, then rests.
        let sweep = min(phase / 0.75, 1.0)
        let centre = -1.0 + sweep * (n + 1.0)
        let d = abs(Double(i) - centre)
        let width = 1.3
        let t = max(0, 1 - d / width)
        return t * t * (3 - 2 * t)
    }
}

/// Hosts `WaveLayerView` and hands it the bar colours sampled along one period.
private struct WaveLayers: NSViewRepresentable {
    let mark: SqueezeWaveMark

    func makeNSView(context: Context) -> WaveLayerView { WaveLayerView() }

    func updateNSView(_ view: WaveLayerView, context: Context) {
        let env = context.environment
        let key: [AnyHashable] = [mark.base.resolve(in: env), mark.lit.resolve(in: env), mark.restOpacity, mark.peakOpacity, mark.period]
        guard view.key != key else { return }
        view.key = key
        // One keyframe per 1/30 s, the old timeline's frame rate, so the sweep keeps its exact shape.
        let samples = max(2, Int(mark.period * 30))
        view.setWave(
            rest: mark.color(level: 0).resolve(in: env).cgColor,
            frames: (0..<SqueezeClampShape.barCount).map { bar in
                (0...samples).map { k in
                    mark.color(level: SqueezeWaveMark.level(forBar: bar, phase: Double(k) / Double(samples))).resolve(in: env).cgColor
                }
            },
            period: mark.period
        )
    }
}

/// One shape layer per bar with a looping fill-colour animation. The animation is only attached while
/// the window is on screen, and its start is tied to the wall clock so every mark sweeps in step.
final class WaveLayerView: NSView {
    var key: [AnyHashable] = []
    let bars = (0..<SqueezeClampShape.barCount).map { _ in CAShapeLayer() }
    private(set) var frames: [[CGColor]] = []
    private var period = 6.0
    private var observer: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Same y-down space as the SwiftUI shape.
    override var isFlipped: Bool { true }
    // Decorative: clicks and window drags go to whatever is behind.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setWave(rest: CGColor, frames: [[CGColor]], period: Double) {
        self.frames = frames
        self.period = period
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.fillColor = rest }
        CATransaction.commit()
        restart()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.frame = bounds
            bar.contentsScale = window?.backingScaleFactor ?? 2
            bar.path = SqueezeClampShape().barPath(i, in: bounds).cgPath
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let window {
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            }
        }
        needsLayout = true
        restart()
    }

    private func restart() {
        bars.forEach { $0.removeAnimation(forKey: "wave") }
        guard window?.occlusionState.contains(.visible) == true, frames.count == bars.count else { return }
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        for (bar, colors) in zip(bars, frames) {
            let wave = CAKeyframeAnimation(keyPath: "fillColor")
            wave.values = colors
            wave.duration = period
            wave.repeatCount = .infinity
            wave.beginTime = bar.convertTime(CACurrentMediaTime(), from: nil) - phase
            // A slow glow: 20 fps is plenty and keeps the window compositor mostly idle.
            wave.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 20)
            bar.add(wave, forKey: "wave")
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

/// Reports whether the hosting window is on screen and not fully covered.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if let window {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            // Deferred: this runs inside SwiftUI's view update, where state can't change.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report() {
            onChange?(window?.occlusionState.contains(.visible) ?? false)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

// MARK: - Progress Fill
/// The S mark as a progress indicator: dim at rest, each bar brightening in turn from the top as `progress` goes 0 to 1.
struct SqueezeProgressMark: View {
    var progress: Double
    var color: Color = .white
    /// Unlit bars. A neutral tone reads better than a faded `color` on glass.
    var restColor: Color = Color.white.opacity(0.28)

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            ZStack {
                SqueezeClampShape().fill(restColor)
                ForEach(0..<SqueezeClampShape.barCount, id: \.self) { i in
                    SqueezeClampShape().barPath(i, in: rect)
                        .fill(color.opacity(SqueezeClampShape.barLevel(i, progress: progress)))
                }
            }
        }
        // Progress arrives at most every ProgressGate.minInterval; a linear step of that length keeps the fill moving evenly.
        .animation(.linear(duration: ProgressGate.minInterval), value: progress)
    }
}

public extension SqueezeClampShape {
    /// How lit bar `index` is (0...1) for a job progress. Bars light one after another; the first is
    /// never fully dark so a new job reads as started.
    static func barLevel(_ index: Int, progress: Double) -> Double {
        let p = min(max(progress, 0.04), 1.0)
        return min(max(p * Double(barCount) - Double(index), 0), 1)
    }

    /// Single-colour variant: opacity from `rest` up to 1.
    static func barOpacity(_ index: Int, progress: Double, rest: Double = 0.28) -> Double {
        rest + (1 - rest) * barLevel(index, progress: progress)
    }
}

// MARK: - AppKit Drawing Helper
public extension NSImage {
    static func squeezeClampImage(size: CGFloat = 18, color: NSColor = .white) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        // Shape paths are y-down; the lockFocus context is y-up.
        let flip = CGAffineTransform(translationX: 0, y: size).scaledBy(x: 1, y: -1)
        let path = SqueezeClampShape().path(in: rect).cgPath.copy(using: [flip]) ?? SqueezeClampShape().path(in: rect).cgPath

        color.setFill()
        let cgContext = NSGraphicsContext.current?.cgContext
        cgContext?.addPath(path)
        cgContext?.fillPath()

        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    /// AppKit twin of `SqueezeProgressMark` for the menu bar.
    static func squeezeProgressImage(size: CGFloat = 18, color: NSColor = .white, progress: Double) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        // Shape paths are y-down; the lockFocus context is y-up.
        var flip = CGAffineTransform(translationX: 0, y: size).scaledBy(x: 1, y: -1)
        let context = NSGraphicsContext.current?.cgContext
        for i in 0..<SqueezeClampShape.barCount {
            let bar = SqueezeClampShape().barPath(i, in: rect).cgPath
            context?.addPath(bar.copy(using: &flip) ?? bar)
            context?.setFillColor(color.withAlphaComponent(SqueezeClampShape.barOpacity(i, progress: progress)).cgColor)
            context?.fillPath()
        }
        img.unlockFocus()
        return img
    }
}
