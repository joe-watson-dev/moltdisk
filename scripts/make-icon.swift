// Draws the MoltDisk app icon (a drive shedding its old skin) and writes Resources/AppIcon.icns.
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

    // The old skin: a pale outline of the drive, lifted up and to the left, peeling away.
    let skin = NSRect(x: 13, y: 29, width: 60, height: 22)
    cg.saveGState()
    cg.translateBy(x: skin.midX, y: skin.midY)
    cg.rotate(by: -0.12)
    cg.translateBy(x: -skin.midX, y: -skin.midY)
    let skinPath = NSBezierPath(roundedRect: skin, xRadius: 6, yRadius: 6)
    hex(0xCCFBF1, 0.14).setFill()
    skinPath.fill()
    skinPath.lineWidth = 2.4
    let dash: [CGFloat] = [5, 3.2]
    skinPath.setLineDash(dash, count: 2, phase: 0)
    hex(0xCCFBF1, 0.75).setStroke()
    skinPath.stroke()
    // Curled corner where the skin comes off.
    let curl = NSBezierPath()
    curl.move(to: NSPoint(x: skin.maxX - 15, y: skin.maxY))
    curl.curve(to: NSPoint(x: skin.maxX, y: skin.maxY - 13),
               controlPoint1: NSPoint(x: skin.maxX - 4, y: skin.maxY + 1), controlPoint2: NSPoint(x: skin.maxX + 1, y: skin.maxY - 4))
    curl.line(to: NSPoint(x: skin.maxX - 9, y: skin.maxY - 7))
    curl.close()
    hex(0x99F6E4, 0.9).setFill()
    curl.fill()
    cg.restoreGState()

    // The fresh drive underneath, bright and new.
    hex(0x042F2E, 0.3).setFill()
    NSBezierPath(roundedRect: NSRect(x: 24, y: 55, width: 60, height: 22), xRadius: 6, yRadius: 6).fill()
    let drive = NSBezierPath(roundedRect: NSRect(x: 24, y: 52.5, width: 60, height: 22), xRadius: 6, yRadius: 6)
    cg.saveGState()
    drive.addClip()
    NSGradient(starting: hex(0xF0FDFA), ending: hex(0xCCFBF1))!.draw(in: drive, angle: -90)
    cg.restoreGState()
    hex(0x2DD4BF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 31, y: 61.5, width: 24, height: 4.5), xRadius: 2.25, yRadius: 2.25).fill()
    hex(0x0F766E).setFill()
    NSBezierPath(ovalIn: NSRect(x: 70.5, y: 60.5, width: 6.5, height: 6.5)).fill()

    // Two small sparkles: what's new and clean.
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
    star(80, 30, 5.5)
    star(71, 20, 3)

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
