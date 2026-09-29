// Draws Show Mode's app icon — two theatre masks on the Stoatworks navy — and writes
// Resources/AppIcon.icns. The masks are drawn here from scratch: the menu-bar icon is the
// SF Symbol `theatermasks`, but Apple's SF Symbols licence does not allow them in app icons.
//
//   swift scripts/make-icon.swift            # writes Resources/AppIcon.icns
//   swift scripts/make-icon.swift preview.png  # also writes the 1024 px master there
import AppKit

let navy = NSColor(srgbRed: 0x0f / 255, green: 0x1b / 255, blue: 0x2d / 255, alpha: 1)
let navyLight = NSColor(srgbRed: 0x1d / 255, green: 0x33 / 255, blue: 0x52 / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf4 / 255, alpha: 1)
let cyan = NSColor(srgbRed: 0x4c / 255, green: 0xc9 / 255, blue: 0xf0 / 255, alpha: 1)

/// A mask in its own unit space: 1 wide, about 1.2 tall, y up, chin at the bottom.
func maskOutline() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 0.10, y: 1.18))
    p.curve(to: NSPoint(x: 0.90, y: 1.18), controlPoint1: NSPoint(x: 0.35, y: 1.24), controlPoint2: NSPoint(x: 0.65, y: 1.24))
    p.curve(to: NSPoint(x: 1.00, y: 1.06), controlPoint1: NSPoint(x: 0.96, y: 1.17), controlPoint2: NSPoint(x: 1.00, y: 1.13))
    p.curve(to: NSPoint(x: 0.50, y: 0.00), controlPoint1: NSPoint(x: 1.00, y: 0.50), controlPoint2: NSPoint(x: 0.86, y: 0.00))
    p.curve(to: NSPoint(x: 0.00, y: 1.06), controlPoint1: NSPoint(x: 0.14, y: 0.00), controlPoint2: NSPoint(x: 0.00, y: 0.50))
    p.curve(to: NSPoint(x: 0.10, y: 1.18), controlPoint1: NSPoint(x: 0.00, y: 1.13), controlPoint2: NSPoint(x: 0.04, y: 1.17))
    p.close()
    return p
}

/// Comedy: eyes squeezed shut in arcs, and a wide open smile.
func comedyFeatures() -> [(NSBezierPath, Bool)] {
    var out: [(NSBezierPath, Bool)] = []
    for x in [0.30, 0.70] {
        let eye = NSBezierPath()
        eye.appendArc(withCenter: NSPoint(x: x, y: 0.74), radius: 0.11, startAngle: 20, endAngle: 160)
        eye.lineWidth = 0.075
        eye.lineCapStyle = .round
        out.append((eye, false))
    }
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: 0.20, y: 0.50))
    mouth.curve(to: NSPoint(x: 0.80, y: 0.50), controlPoint1: NSPoint(x: 0.40, y: 0.45), controlPoint2: NSPoint(x: 0.60, y: 0.45))
    mouth.curve(to: NSPoint(x: 0.20, y: 0.50), controlPoint1: NSPoint(x: 0.74, y: 0.18), controlPoint2: NSPoint(x: 0.26, y: 0.18))
    mouth.close()
    out.append((mouth, true))
    return out
}

/// Tragedy: round eyes and a downturned mouth.
func tragedyFeatures() -> [(NSBezierPath, Bool)] {
    var out: [(NSBezierPath, Bool)] = []
    for x in [0.31, 0.69] {
        out.append((NSBezierPath(ovalIn: NSRect(x: x - 0.075, y: 0.66, width: 0.15, height: 0.15)), true))
    }
    let mouth = NSBezierPath()
    mouth.appendArc(withCenter: NSPoint(x: 0.5, y: 0.14), radius: 0.28, startAngle: 50, endAngle: 130)
    mouth.lineWidth = 0.075
    mouth.lineCapStyle = .round
    out.append((mouth, false))
    return out
}

/// Draws one mask at a centre, size and tilt; features are cut out in the background colour.
func drawMask(features: [(NSBezierPath, Bool)], centre: NSPoint, width: CGFloat, degrees: CGFloat,
              fill: NSColor, gap: CGFloat) {
    let t = NSAffineTransform()
    t.translateX(by: centre.x, yBy: centre.y)
    t.rotate(byDegrees: degrees)
    t.scale(by: width)
    t.translateX(by: -0.5, yBy: -0.6)

    let outline = t.transform(maskOutline())
    // A navy border around each mask, so where they overlap the front one reads cleanly.
    navy.setStroke()
    outline.lineWidth = gap
    outline.lineJoinStyle = .round
    outline.stroke()
    fill.setFill()
    outline.fill()

    navy.set()
    for (path, filled) in features {
        let p = t.transform(path)
        if filled { p.fill() } else { p.lineWidth = path.lineWidth * width; p.lineCapStyle = .round; p.stroke() }
    }
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)   // draw in 1024-point space at any pixel size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // The macOS icon grid: an 824 pt rounded square inset 100 pt, with a soft shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    navy.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: navyLight, ending: navy)!.draw(in: tilePath, angle: -90)

    // Tragedy behind, tinted; comedy in front — the same arrangement as the menu-bar icon.
    drawMask(features: tragedyFeatures(), centre: NSPoint(x: 648, y: 462), width: 318, degrees: -16,
             fill: cyan, gap: 44)
    drawMask(features: comedyFeatures(), centre: NSPoint(x: 382, y: 566), width: 336, degrees: 12,
             fill: paper, gap: 44)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
if CommandLine.arguments.count > 1 {
    try! render(1024).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
