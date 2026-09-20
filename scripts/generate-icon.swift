// Rebuild the vector-drawn app icon: swift scripts/generate-icon.swift
import AppKit

let root = URL(fileURLWithPath: "Sources/VolumeFoldApp/Assets.xcassets")
let destination = root.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24,
                      color: NSColor.black.withAlphaComponent(0.2).cgColor)
    NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.85, alpha: 1).setFill()
    tile.fill()
    context.restoreGState()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.64, blue: 1, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.94, alpha: 1),
        NSColor(calibratedRed: 0.34, green: 0.23, blue: 0.79, alpha: 1)
    ])!.draw(in: tile, angle: -65)
    NSColor.white.withAlphaComponent(0.25).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    // A slightly folded display with three descending volume bars.
    let display = NSBezierPath()
    display.move(to: NSPoint(x: 280, y: 727))
    display.curve(to: NSPoint(x: 256, y: 701), controlPoint1: NSPoint(x: 263, y: 727), controlPoint2: NSPoint(x: 255, y: 717))
    display.line(to: NSPoint(x: 279, y: 406))
    display.line(to: NSPoint(x: 745, y: 406))
    display.line(to: NSPoint(x: 768, y: 701))
    display.curve(to: NSPoint(x: 744, y: 727), controlPoint1: NSPoint(x: 769, y: 717), controlPoint2: NSPoint(x: 761, y: 727))
    display.close()
    NSColor.white.withAlphaComponent(0.10).setFill()
    display.fill()
    NSColor.white.setStroke()
    display.lineWidth = 27
    display.lineJoinStyle = .round
    display.stroke()

    for (index, height) in [158.0, 112.0, 66.0].enumerated() {
        NSColor.white.withAlphaComponent(1 - Double(index) * 0.15).setFill()
        NSBezierPath(roundedRect: NSRect(x: 367 + Double(index) * 100, y: 470, width: 58, height: height),
                     xRadius: 20, yRadius: 20).fill()
    }

    let base = NSBezierPath()
    base.move(to: NSPoint(x: 276, y: 366))
    base.line(to: NSPoint(x: 748, y: 366))
    base.line(to: NSPoint(x: 812, y: 306))
    base.curve(to: NSPoint(x: 785, y: 282), controlPoint1: NSPoint(x: 817, y: 289), controlPoint2: NSPoint(x: 800, y: 282))
    base.line(to: NSPoint(x: 239, y: 282))
    base.curve(to: NSPoint(x: 212, y: 306), controlPoint1: NSPoint(x: 224, y: 282), controlPoint2: NSPoint(x: 207, y: 289))
    base.close()
    NSColor.white.setFill()
    base.fill()
    NSColor(calibratedRed: 0.25, green: 0.40, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 456, y: 338, width: 112, height: 15), xRadius: 7, yRadius: 7).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(pixels: size * scale).write(to: destination.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: destination.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("Contents.json"))
print("Generated all macOS app icon sizes.")
