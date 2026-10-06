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

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let design = Self.designRect
        let scale = min(rect.width / design.width, rect.height / design.height)
        let ox = rect.midX - design.width * scale / 2
        let oy = rect.midY - design.height * scale / 2
        let radius = Self.barHeight * scale / 2

        for (x0, x1, y) in Self.bars {
            let bar = CGRect(
                x: ox + (x0 - design.minX) * scale,
                y: oy + (y - design.minY) * scale,
                width: (x1 - x0) * scale,
                height: Self.barHeight * scale
            )
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
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
