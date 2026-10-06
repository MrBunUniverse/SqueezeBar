import AppKit

// Renders the DMG window background (720x440 pt @2x) to the path in argv[1].
let w: CGFloat = 720, h: CGFloat = 440, scale: CGFloat = 2
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg_background.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(deviceRed: r/255, green: g/255, blue: b/255, alpha: a) }

// Light gradient: Finder draws icon labels in dark text, so the background must be light
NSGradient(colors: [c(214, 218, 228), c(246, 247, 250)])!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)

// Minimal arrow: one chevron
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 344, y: 255)); arrow.line(to: NSPoint(x: 366, y: 235)); arrow.line(to: NSPoint(x: 344, y: 215))
arrow.lineWidth = 4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
c(30, 32, 40, 0.55).setStroke()
arrow.stroke()

// Text
func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    (s as NSString).draw(in: NSRect(x: 0, y: y, width: w, height: size * 1.5),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p])
}
draw("Compress images, video, audio & PDF — 100% on-device", size: 13, weight: .regular, color: c(24, 26, 34, 0.55), y: 40)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
