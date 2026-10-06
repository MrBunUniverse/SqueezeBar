#!/usr/bin/env swift
import Foundation
import AppKit
import CoreGraphics

// Flat "striped S" icon: full-bleed royal-blue square, five rounded bars (middle one orange).
// Bars are (x0, x1, y) on a 1024 design grid.
let bars: [(CGFloat, CGFloat, CGFloat)] = [
    (290, 800, 170), (224, 484, 312), (224, 800, 454), (540, 800, 596), (224, 734, 738)
]
let barHeight: CGFloat = 116

func createIconImage(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    // Full-bleed square: macOS 26 applies its own icon mask. Drawing our own rounded tile with
    // transparent margin makes the system wrap the icon in a dark plate.
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.setFillColor(NSColor(red: 0x3D / 255, green: 0x4D / 255, blue: 0xFF / 255, alpha: 1).cgColor)
    ctx.fill(full)

    // Map the 1024 design grid onto the canvas, centred on the bars' centre (512, 512); design y is down.
    let k = size / 1024 * 1.12
    for (i, bar) in bars.enumerated() {
        let (x0, x1, y) = bar
        let rect = CGRect(
            x: size / 2 + (x0 - 512) * k,
            y: size / 2 - (y + barHeight - 512) * k,
            width: (x1 - x0) * k,
            height: barHeight * k
        )
        let r = rect.height / 2
        ctx.setFillColor(i == 2
            ? NSColor(red: 1, green: 0x8A / 255, blue: 0x3D / 255, alpha: 1).cgColor
            : NSColor.white.cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
    }

    img.unlockFocus()
    return img
}

// Transparent 1024 layer holding a subset of the bars, for the Icon Composer (.icon) package.
func createLayerImage(orange: Bool) -> NSImage {
    let size: CGFloat = 1024
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
        let k = 1.12 as CGFloat
        for (i, bar) in bars.enumerated() where (i == 2) == orange {
            let (x0, x1, y) = bar
            let rect = CGRect(x: size / 2 + (x0 - 512) * k, y: size / 2 - (y + barHeight - 512) * k, width: (x1 - x0) * k, height: barHeight * k)
            let r = rect.height / 2
            ctx.setFillColor(orange ? NSColor(red: 1, green: 0x8A / 255, blue: 0x3D / 255, alpha: 1).cgColor : NSColor.white.cgColor)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.fillPath()
        }
    }
    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, to url: URL) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to get PNG data")
        return
    }
    try? pngData.write(to: url)
}

let fm = FileManager.default
let resourcesDir = URL(fileURLWithPath: "Resources")
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Sizes for iconset
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let img = createIconImage(size: size)
    let fileURL = iconsetDir.appendingPathComponent(name)
    savePNG(image: img, to: fileURL)
}

// Master 1024x1024
let master = createIconImage(size: 1024)
savePNG(image: master, to: resourcesDir.appendingPathComponent("AppIcon.png"))

print("Generating AppIcon.icns via iconutil...")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir.path, "-o", resourcesDir.appendingPathComponent("AppIcon.icns").path]
try? task.run()
task.waitUntilExit()

print("AppIcon.icns created successfully!")

// Layered icon for macOS 26 (compiled to Assets.car by bundle_app.sh via actool).
let iconPkg = resourcesDir.appendingPathComponent("SqueezeBar.icon")
let iconAssets = iconPkg.appendingPathComponent("Assets")
try? fm.createDirectory(at: iconAssets, withIntermediateDirectories: true)
savePNG(image: createLayerImage(orange: false), to: iconAssets.appendingPathComponent("bars-white.png"))
savePNG(image: createLayerImage(orange: true), to: iconAssets.appendingPathComponent("bar-orange.png"))
let iconJSON = """
{
  "fill" : { "solid" : "srgb:0.23922,0.30196,1.00000,1.00000" },
  "groups" : [
    {
      "layers" : [
        { "image-name" : "bar-orange.png", "name" : "bar-orange" },
        { "image-name" : "bars-white.png", "name" : "bars-white" }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : "shared" }
}
"""
try? iconJSON.write(to: iconPkg.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("SqueezeBar.icon written")
