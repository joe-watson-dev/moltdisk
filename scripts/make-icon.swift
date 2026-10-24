// Draws the DiskSweep app icon (a broom sweeping over a drive) and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

/// The artwork is designed on a 100×100 grid; the icon body (4…96) fills Apple's 824 px of a 1024 canvas.
func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext

    let scale = CGFloat(size) / 1024
    let unit = 824.0 / 92.0 * scale
    // Flip to a top-left origin and map grid units to pixels.
    cg.translateBy(x: 0, y: CGFloat(size))
    cg.scaleBy(x: 1, y: -1)
    cg.translateBy(x: 100 * scale - 4 * unit, y: 100 * scale - 4 * unit)
    cg.scaleBy(x: unit, y: unit)

    // Body with a soft drop shadow and a gentle top-to-bottom gradient.
    let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 92, height: 92), xRadius: 21, yRadius: 21)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 1.2), blur: 3, color: hex(0x000000, 0.35).cgColor)
    hex(0x0F766E).setFill()
    body.fill()
    cg.restoreGState()
    cg.saveGState()
    body.addClip()
    NSGradient(starting: hex(0x0B5F59), ending: hex(0x14B8A6))!.draw(in: body, angle: -90)
    cg.restoreGState()

    // Drive.
    hex(0x042F2E, 0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: 20, y: 60, width: 60, height: 20), xRadius: 5, yRadius: 5).fill()
    hex(0xCCFBF1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 20, y: 58, width: 60, height: 20), xRadius: 5, yRadius: 5).fill()
    hex(0x5EEAD4).setFill()
    NSBezierPath(roundedRect: NSRect(x: 26, y: 66, width: 22, height: 4), xRadius: 2, yRadius: 2).fill()
    hex(0x0F766E).setFill()
    NSBezierPath(ovalIn: NSRect(x: 67, y: 65, width: 6, height: 6)).fill()

    // Broom handle.
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 67, y: 15))
    handle.line(to: NSPoint(x: 47, y: 45))
    handle.lineWidth = 5
    handle.lineCapStyle = .round
    hex(0xFDE68A).setStroke()
    handle.stroke()
    // Binding where the handle meets the bristles.
    let band = NSBezierPath()
    band.move(to: NSPoint(x: 40.5, y: 41.5))
    band.line(to: NSPoint(x: 52.5, y: 47.5))
    band.lineWidth = 4
    band.lineCapStyle = .round
    hex(0xB45309).setStroke()
    band.stroke()

    // Bristles.
    let bristles = NSBezierPath()
    bristles.move(to: NSPoint(x: 39, y: 43))
    bristles.line(to: NSPoint(x: 53, y: 50))
    bristles.line(to: NSPoint(x: 46, y: 61))
    bristles.line(to: NSPoint(x: 27, y: 54))
    bristles.close()
    hex(0xFBBF24).setFill()
    bristles.fill()
    hex(0xD97706).setStroke()
    for t in stride(from: 0.2, through: 0.8, by: 0.2) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 39 + (53 - 39) * t, y: 43 + (50 - 43) * t))
        line.line(to: NSPoint(x: 27 + (46 - 27) * t, y: 54 + (61 - 54) * t))
        line.lineWidth = 1.1
        line.lineCapStyle = .round
        line.stroke()
    }

    // Sparkles: what's been swept clean.
    func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx, y: cy - r))
        p.curve(to: NSPoint(x: cx + r, y: cy), controlPoint1: NSPoint(x: cx + r * 0.15, y: cy - r * 0.15), controlPoint2: NSPoint(x: cx + r * 0.15, y: cy - r * 0.15))
        p.curve(to: NSPoint(x: cx, y: cy + r), controlPoint1: NSPoint(x: cx + r * 0.15, y: cy + r * 0.15), controlPoint2: NSPoint(x: cx + r * 0.15, y: cy + r * 0.15))
        p.curve(to: NSPoint(x: cx - r, y: cy), controlPoint1: NSPoint(x: cx - r * 0.15, y: cy + r * 0.15), controlPoint2: NSPoint(x: cx - r * 0.15, y: cy + r * 0.15))
        p.curve(to: NSPoint(x: cx, y: cy - r), controlPoint1: NSPoint(x: cx - r * 0.15, y: cy - r * 0.15), controlPoint2: NSPoint(x: cx - r * 0.15, y: cy - r * 0.15))
        p.fill()
    }
    hex(0xF0FDFA).setFill()
    star(24, 30, 6)
    star(34, 19, 3.5)
    star(80, 40, 3)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(size: base * factor).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(size: 1024).representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
