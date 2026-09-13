// Generates AppIcon.appiconset PNGs. Run: swift Scripts/gen-icon.swift
import AppKit

let outDir = URL(fileURLWithPath: "MDReader/Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: artwork occupies ~80% of the canvas.
    let inset = s * 0.10
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Shadow
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Background: diagonal indigo gradient
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.42, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.24, green: 0.33, blue: 0.92, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.62, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -60)

    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    // Soft radial glow top-left (no hard edges)
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0.0)])!
    let glowCenter = NSPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.22)
    let glowRect = NSRect(x: glowCenter.x - rect.width * 0.9, y: glowCenter.y - rect.width * 0.9,
                          width: rect.width * 1.8, height: rect.width * 1.8)
    glow.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
    // Faint bottom vignette
    let vignette = NSGradient(colors: [NSColor.black.withAlphaComponent(0.0), NSColor.black.withAlphaComponent(0.16)])!
    vignette.draw(in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.45), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Inner rim for depth
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.006, dy: s * 0.006),
                           xRadius: radius - s * 0.006, yRadius: radius - s * 0.006)
    rim.lineWidth = s * 0.008
    NSColor.white.withAlphaComponent(0.18).setStroke()
    rim.stroke()

    // Glyph shadow
    NSGraphicsContext.current?.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    glyphShadow.shadowBlurRadius = s * 0.025
    glyphShadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    glyphShadow.set()

    // "M" glyph with down arrow (Markdown logo motif)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let font = NSFont.systemFont(ofSize: rect.height * 0.62, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor.white, .paragraphStyle: para,
        .kern: -rect.width * 0.02,
    ]
    let str = NSAttributedString(string: "M", attributes: attrs)
    let size = str.size()
    let textRect = NSRect(x: rect.minX - rect.width * 0.08,
                          y: rect.midY - size.height / 2 + rect.height * 0.02,
                          width: rect.width, height: size.height)
    str.draw(in: textRect)

    // Arrow
    let arrow = NSBezierPath()
    let ax = rect.maxX - rect.width * 0.20
    let ay = rect.midY - rect.height * 0.02
    let aw = rect.width * 0.09
    let ah = rect.height * 0.22
    arrow.lineWidth = rect.width * 0.075
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: ax, y: ay + ah / 2))
    arrow.line(to: NSPoint(x: ax, y: ay - ah / 2))
    arrow.move(to: NSPoint(x: ax - aw, y: ay - ah / 2 + aw))
    arrow.line(to: NSPoint(x: ax, y: ay - ah / 2))
    arrow.line(to: NSPoint(x: ax + aw, y: ay - ah / 2 + aw))
    NSColor.white.setStroke()
    arrow.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (pt, scale) in sizes {
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try! render(px: pt * scale).write(to: outDir.appendingPathComponent(name))
    images.append(["size": "\(pt)x\(pt)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(outDir.path)")
