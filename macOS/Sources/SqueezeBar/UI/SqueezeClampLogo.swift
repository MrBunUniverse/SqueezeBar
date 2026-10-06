import SwiftUI
import AppKit

// MARK: - Minimalist Flat White C-Clamp Shape
public struct SqueezeClampShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let scale = min(w, h)
        let ox = rect.midX - scale / 2.0
        let oy = rect.midY - scale / 2.0
        
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * scale, y: oy + y * scale)
        }
        
        func r(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ cr: CGFloat = 0) -> CGRect {
            CGRect(x: ox + x * scale, y: oy + y * scale, width: rw * scale, height: rh * scale)
        }
        
        // 1. Outer C-Frame
        // Main C bracket spine & arms
        var cFrame = Path()
        let outerR: CGFloat = 0.22 * scale
        let innerR: CGFloat = 0.12 * scale
        
        // Top arm right tip -> top left curve -> spine -> bottom left curve -> bottom arm right tip
        cFrame.move(to: p(0.66, 0.20))
        cFrame.addLine(to: p(0.66, 0.28))
        cFrame.addLine(to: p(0.56, 0.28))
        cFrame.addLine(to: p(0.44, 0.28))
        // Inner curve top-left
        cFrame.addArc(
            tangent1End: p(0.36, 0.28),
            tangent2End: p(0.36, 0.40),
            radius: innerR
        )
        // Inner spine
        cFrame.addLine(to: p(0.36, 0.60))
        // Inner curve bottom-left
        cFrame.addArc(
            tangent1End: p(0.36, 0.72),
            tangent2End: p(0.48, 0.72),
            radius: innerR
        )
        cFrame.addLine(to: p(0.56, 0.72))
        cFrame.addLine(to: p(0.56, 0.80))
        cFrame.addLine(to: p(0.44, 0.80))
        // Outer curve bottom-left
        cFrame.addArc(
            tangent1End: p(0.20, 0.80),
            tangent2End: p(0.20, 0.58),
            radius: outerR
        )
        // Outer spine
        cFrame.addLine(to: p(0.20, 0.42))
        // Outer curve top-left
        cFrame.addArc(
            tangent1End: p(0.20, 0.20),
            tangent2End: p(0.42, 0.20),
            radius: outerR
        )
        cFrame.closeSubpath()
        path.addPath(cFrame)
        
        // 2. Top Anvil Head
        // Vertical post
        path.addRoundedRect(in: r(0.57, 0.27, 0.08, 0.08), cornerSize: CGSize(width: 0.015 * scale, height: 0.015 * scale))
        // Wide upper anvil press plate
        path.addRoundedRect(in: r(0.51, 0.35, 0.20, 0.045), cornerSize: CGSize(width: 0.018 * scale, height: 0.018 * scale))
        
        // 3. Bottom Press Plate & Threaded Screw
        // Wide lower clamp plate
        path.addRoundedRect(in: r(0.46, 0.58, 0.30, 0.05), cornerSize: CGSize(width: 0.02 * scale, height: 0.02 * scale))
        
        // Screw thread ridges (horizontal teeth)
        let threadX: CGFloat = 0.55
        let threadW: CGFloat = 0.12
        let threadH: CGFloat = 0.022
        for i in 0..<3 {
            let ty: CGFloat = 0.64 + CGFloat(i) * 0.040
            path.addRoundedRect(in: r(threadX, ty, threadW, threadH), cornerSize: CGSize(width: 0.01 * scale, height: 0.01 * scale))
        }
        
        // Bottom screw handle / knob
        path.addRoundedRect(in: r(0.53, 0.77, 0.16, 0.035), cornerSize: CGSize(width: 0.015 * scale, height: 0.015 * scale))
        
        return path
    }
}

// MARK: - AppKit Drawing Helper
public extension NSImage {
    static func squeezeClampImage(size: CGFloat = 18, color: NSColor = .white) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let shape = SqueezeClampShape()
        let path = shape.path(in: rect)
        
        color.setFill()
        let cgContext = NSGraphicsContext.current?.cgContext
        cgContext?.addPath(path.cgPath)
        cgContext?.fillPath()
        
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
