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
    var base: Color = .white
    var restOpacity: Double = 0.20
    var peakOpacity: Double = 0.50
    /// Seconds for one full sweep, including a short rest before the next.
    var period: Double = 6.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            marks(time: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                marks(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func marks(time: Double?) -> some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let shape = SqueezeClampShape()
            ZStack {
                ForEach(0..<SqueezeClampShape.barCount, id: \.self) { i in
                    shape.barPath(i, in: rect)
                        .fill(base.opacity(opacity(forBar: i, time: time)))
                }
            }
        }
    }

    private func opacity(forBar i: Int, time: Double?) -> Double {
        guard let time else { return restOpacity }
        let n = Double(SqueezeClampShape.barCount)
        // Wave centre travels from above the first bar to below the last, then rests.
        let phase = (time.truncatingRemainder(dividingBy: period)) / period
        let sweep = min(phase / 0.75, 1.0)
        let centre = -1.0 + sweep * (n + 1.0)
        let d = abs(Double(i) - centre)
        let width = 1.3
        let t = max(0, 1 - d / width)
        let eased = t * t * (3 - 2 * t)
        return restOpacity + (peakOpacity - restOpacity) * eased
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
}
