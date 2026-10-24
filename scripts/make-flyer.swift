// Announcement flyer: marketing/disksweep-flyer.png (1080×1350 pt, rendered @2x).
// The storage card uses the example figures below; edit them, then: swift scripts/make-flyer.swift
//
// Product-marketing layout: glossy icon hero → two-tone headline → benefit line → the app on a scene
// with depth → the whole disk as a storage bar (reclaimable, other, free) → trust row.
import AppKit
import CoreImage

/// Illustrative 512 GB developer Mac (macOS reports 494.38 GB after formatting), using the categories
/// and colors of System Settings › General › Storage. The card is titled as an example.
let cardTitle = "Example: 512 GB Mac"
let diskSize = 494.38
let categories: [(name: String, gb: Double, color: UInt32)] = [
    ("macOS", 31.67, 0x8E8E93),
    ("System Data", 78.40, 0xAEAEB2),
    ("Documents", 96.20, 0xEF5350),
    ("Applications", 48.50, 0xF5A040),
    ("Developer", 22.30, 0xF2C94C),
    ("Photos", 12.40, 0xBF5AF2),
    ("iCloud Drive", 4.60, 0x0A84FF),
    ("Mail", 2.10, 0x64D2FF),
    ("Trash", 1.20, 0x4CAF50),
]
let freeSpace = diskSize - categories.reduce(0) { $0 + $1.gb }
/// Part of the free space that DiskSweep recovered — the number the card leads with.
let freedByApp = 101.40
let freeText = String(format: "%.2f GB", freeSpace)
let freedText = String(format: "%.1f GB", freedByApp)

/// Sizes the way macOS writes them: GB with two decimals, or MB below 1 GB.
func size(_ gb: Double) -> String {
    gb < 1 ? String(format: "%.1f MB", gb * 1000) : String(format: "%.2f GB", gb)
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let marketing = root.appendingPathComponent("marketing")
let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon-1024.png"))!
let shotRep = NSBitmapImageRep(data: try! Data(contentsOf: marketing.appendingPathComponent("screenshot-vscode-full.png")))!

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let ink = hex(0x0F172A), muted = hex(0x64748B), brand = hex(0x0D9488)

func font(_ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard rounded else { return base }
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func text(_ s: String, _ f: NSFont, _ color: NSColor, kern: CGFloat = 0, align: NSTextAlignment = .left, lineHeight: CGFloat? = nil) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    if let lineHeight { style.minimumLineHeight = lineHeight; style.maximumLineHeight = lineHeight }
    return NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .kern: kern, .paragraphStyle: style])
}

/// Renders `draw` into an image and Gaussian-blurs it — used for soft, out-of-focus shapes.
func blurred(_ size: NSSize, radius: CGFloat, _ draw: @escaping () -> Void) -> NSImage {
    let sharp = NSImage(size: size, flipped: true) { _ in draw(); return true }
    guard let tiff = sharp.tiffRepresentation, let input = CIImage(data: tiff),
          let filter = CIFilter(name: "CIGaussianBlur") else { return sharp }
    filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(radius, forKey: kCIInputRadiusKey)
    let result = NSImage(size: size)
    result.addRepresentation(NSCIImageRep(ciImage: filter.outputImage!.cropped(to: input.extent)))
    return result
}

func shadowed(_ color: NSColor, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -y)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func symbol(_ name: String, _ size: CGFloat, _ color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold).applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

let W: CGFloat = 1080, H: CGFloat = 1350

let canvas = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
    // Background: white with soft mint and sky shapes behind the hero.
    hex(0xFFFFFF).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    blurred(NSSize(width: W, height: 700), radius: 60) {
        hex(0xCCFBF1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 380, y: -260, width: 900, height: 760)).fill()
        hex(0xE0F2FE).setFill()
        NSBezierPath(ovalIn: NSRect(x: -260, y: 60, width: 640, height: 520)).fill()
    }.draw(in: NSRect(x: 0, y: 0, width: W, height: 700), from: .zero, operation: .sourceOver, fraction: 0.9, respectFlipped: true, hints: nil)

    // 1. Glossy icon hero on the left, two-tone headline on the right.
    shadowed(hex(0x0F766E, 0.35), blur: 40, y: 18) {
        icon.draw(in: NSRect(x: 40, y: 52, width: 300, height: 300))
    }
    let headline = NSMutableAttributedString(attributedString: text("I'm done with\nCleanMyMac.\n", font(58, .bold), ink, kern: -1.2, lineHeight: 64))
    headline.append(text("So I built my own.", font(58, .bold), brand, kern: -1.2, lineHeight: 64))
    headline.draw(in: NSRect(x: 372, y: 84, width: 660, height: 200))
    text("The Mac cleaner made for developers.", font(24, .medium), muted)
        .draw(at: NSPoint(x: 374, y: 292))

    // 2. The app on a scene with depth: tinted panel, window rising out of it, blurred foreground, result card.
    let panel = NSRect(x: 56, y: 470, width: W - 112, height: 440)
    let panelPath = NSBezierPath(roundedRect: panel, xRadius: 36, yRadius: 36)
    NSGraphicsContext.saveGraphicsState()
    panelPath.addClip()
    NSGradient(colors: [hex(0x99F6E4), hex(0x5EEAD4), hex(0x2DD4BF)])!.draw(in: panel, angle: -60)
    blurred(panel.size, radius: 30) {
        hex(0xFFFFFF, 0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: 600, y: -120, width: 520, height: 360)).fill()
        hex(0x0F766E, 0.35).setFill()
        NSBezierPath(ovalIn: NSRect(x: -120, y: 220, width: 520, height: 300)).fill()
    }.draw(in: panel, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    // Window: our own title bar (keeps the screenshot's "GB free" figure out), then the app content.
    let window = NSRect(x: 112, y: 404, width: W - 224, height: 476)
    let titleBar: CGFloat = 30
    let contentHeight = window.height - titleBar
    let cropHeight = Int(contentHeight / window.width * CGFloat(shotRep.pixelsWide))
    let crop = shotRep.cgImage!.cropping(to: CGRect(x: 0, y: 104, width: shotRep.pixelsWide, height: cropHeight))!
    let shot = NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
    let windowPath = NSBezierPath(roundedRect: window, xRadius: 14, yRadius: 14)
    shadowed(hex(0x042F2E, 0.45), blur: 50, y: 24) {
        hex(0x1C1C1E).setFill()
        windowPath.fill()
    }
    NSGraphicsContext.saveGraphicsState()
    windowPath.addClip()
    hex(0x2C2C2E).setFill()
    NSRect(x: window.minX, y: window.minY, width: window.width, height: titleBar).fill()
    for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        hex(UInt32(color)).setFill()
        NSBezierPath(ovalIn: NSRect(x: window.minX + 16 + CGFloat(i) * 20, y: window.minY + 9, width: 12, height: 12)).fill()
    }
    let title = text("DiskSweep", font(13, .semibold), hex(0xD1D5DB))
    title.draw(at: NSPoint(x: window.midX - title.size().width / 2, y: window.minY + 7))
    shot.draw(in: NSRect(x: window.minX, y: window.minY + titleBar, width: window.width, height: contentHeight),
              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    hex(0xFFFFFF, 0.15).setStroke()
    NSBezierPath(roundedRect: window.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14).stroke()

    // Out-of-focus foreground shapes overlapping the window's lower edge, clipped to the panel.
    NSGraphicsContext.saveGraphicsState()
    panelPath.addClip()
    blurred(NSSize(width: panel.width, height: 220), radius: 18) {
        for (x, y, r, c) in [(60.0, 150.0, 130.0, 0x99F6E4), (300, 175, 150, 0xCCFBF1), (560, 165, 140, 0x99F6E4),
                             (820, 175, 150, 0xCCFBF1)] as [(CGFloat, CGFloat, CGFloat, UInt32)] {
            hex(c, 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r / 2, width: r * 2, height: r * 1.6)).fill()
        }
    }.draw(in: NSRect(x: panel.minX, y: panel.maxY - 170, width: panel.width, height: 220),
           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    // 3. The whole disk, like macOS's Storage view: reclaimable categories, other data, free space.
    let storage = NSRect(x: 56, y: 954, width: W - 112, height: 228)
    shadowed(hex(0x0F172A, 0.08), blur: 24, y: 8) {
        hex(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: storage, xRadius: 28, yRadius: 28).fill()
    }
    hex(0xE2E8F0).setStroke()
    NSBezierPath(roundedRect: storage.insetBy(dx: 0.5, dy: 0.5), xRadius: 28, yRadius: 28).stroke()
    let inner = storage.insetBy(dx: 36, dy: 30)
    text(cardTitle, font(22, .bold), ink).draw(at: NSPoint(x: inner.minX, y: inner.minY))
    let free = NSMutableAttributedString(attributedString: text(freedText, font(26, .heavy, rounded: true), brand))
    free.append(text(" freed by DiskSweep", font(18, .semibold), muted))
    free.draw(at: NSPoint(x: inner.maxX - free.size().width, y: inner.minY + 1))

    let segments = categories + [("Freed by DiskSweep", freedByApp, 0x0D9488), ("Free", freeSpace - freedByApp, 0x99F6E4)]
    let bar = NSRect(x: inner.minX, y: inner.minY + 44, width: inner.width, height: 22)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: bar, xRadius: 11, yRadius: 11).addClip()
    var x = bar.minX
    for (i, part) in segments.enumerated() {
        let width = bar.width * CGFloat(part.gb / diskSize)
        hex(part.color).setFill()
        NSRect(x: x, y: bar.minY, width: max(width - (i < segments.count - 1 ? 2 : 0), 3), height: bar.height).fill()
        x += width
    }
    NSGraphicsContext.restoreGraphicsState()
    // Legend: four per row, same-width cells so labels line up in columns.
    let cellWidth = inner.width / 4
    var cell = 0
    for part in segments {
        // A label too long for one column takes two; wrap to the next row when it doesn't fit.
        let span = text(part.name + "  " + size(part.gb), font(15, .bold), ink).size().width + 26 > cellWidth ? 2 : 1
        if cell % 4 + span > 4 { cell += 4 - cell % 4 }
        let origin = NSPoint(x: inner.minX + CGFloat(cell % 4) * cellWidth, y: bar.maxY + 20 + CGFloat(cell / 4) * 32)
        cell += span
        hex(part.color).setFill()
        NSBezierPath(ovalIn: NSRect(x: origin.x, y: origin.y + 5, width: 11, height: 11)).fill()
        let label = NSMutableAttributedString(attributedString: text(part.name + "  ", font(15, .medium), muted))
        // Free uses the exact figure from the header so the two always read the same.
        label.append(text(size(part.gb), font(15, .bold), ink))
        label.draw(at: NSPoint(x: origin.x + 18, y: origin.y))
    }

    // 4. Trust row.
    let badges = [("trash", "Trash first,\nalways"), ("lock.fill", "Apps in use\nstay locked"),
                  ("checkmark.shield.fill", "Every risk\nclearly labelled"), ("swift", "Native\nSwiftUI app")]
    let badgeWidth = (W - 112) / CGFloat(badges.count)
    for (i, badge) in badges.enumerated() {
        let cx = 56 + badgeWidth * (CGFloat(i) + 0.5)
        symbol(badge.0, 24, brand)?.draw(in: NSRect(x: cx - 14, y: 1224, width: 28, height: 28))
        text(badge.1, font(16, .semibold), ink, align: .center, lineHeight: 20)
            .draw(in: NSRect(x: cx - badgeWidth / 2, y: 1262, width: badgeWidth, height: 44))
    }
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 2), pixelsHigh: Int(H * 2), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
canvas.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()
let out = marketing.appendingPathComponent("disksweep-flyer.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
