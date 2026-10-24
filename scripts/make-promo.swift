// Composes the announcement image marketing/disksweep-announcement.png (1080×1350 pt, rendered @2x)
// from the app icon and a screenshot. Usage: swift scripts/make-promo.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let marketing = root.appendingPathComponent("marketing")
let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon-1024.png"))!
let shotRep = NSBitmapImageRep(data: try! Data(contentsOf: marketing.appendingPathComponent("screenshot-vscode-full.png")))!
// Crop off the bottom bar, which the offscreen capture draws over the last rows.
let cropHeight = 1475
let cropped = shotRep.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: shotRep.pixelsWide, height: cropHeight))!
let shot = NSImage(cgImage: cropped, size: NSSize(width: shotRep.pixelsWide, height: cropHeight))

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, lineHeight: CGFloat? = nil) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    if let lineHeight { style.minimumLineHeight = lineHeight; style.maximumLineHeight = lineHeight }
    return NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                      .foregroundColor: color, .paragraphStyle: style, .kern: -0.3])
}

let W: CGFloat = 1080, H: CGFloat = 1350, pad: CGFloat = 72
/// Total from the Overview of a real scan; pass a different value as the first argument.
let statText = CommandLine.arguments.dropFirst().first ?? "26 GB"
let canvas = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
    // Background: deep teal, lighter toward the top.
    NSGradient(starting: hex(0x0E5A53), ending: hex(0x04201D))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)
    hex(0x2DD4BF, 0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: W - 520, y: -260, width: 760, height: 760)).fill()

    // Brand row.
    icon.draw(in: NSRect(x: pad - 18, y: pad - 18, width: 150, height: 150))
    text("DiskSweep", 46, .bold, .white).draw(at: NSPoint(x: pad + 140, y: pad + 12))
    text("A Mac cleaner made for developers", 23, .medium, hex(0x99F6E4)).draw(at: NSPoint(x: pad + 142, y: pad + 70))

    // Headline.
    let headline = NSMutableAttributedString(attributedString: text("I'm done with CleanMyMac.\n", 60, .heavy, .white, lineHeight: 70))
    headline.append(text("So I built my own.", 60, .heavy, hex(0x5EEAD4), lineHeight: 70))
    headline.draw(in: NSRect(x: pad, y: 236, width: W - pad * 2, height: 150))

    // Screenshot card.
    let cardWidth = W - pad * 2
    let card = NSRect(x: pad, y: 420, width: cardWidth, height: cardWidth * CGFloat(cropHeight) / CGFloat(shotRep.pixelsWide))
    let shadow = NSShadow()
    shadow.shadowColor = hex(0x000000, 0.55)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    hex(0x1F1F1F).setFill()
    NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).addClip()
    shot.draw(in: card, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    hex(0xFFFFFF, 0.12).setStroke()
    let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
    border.lineWidth = 1
    border.stroke()

    // Feature chips, wrapped onto rows.
    let chips = ["node_modules · .next · target · venv", "Simulators & Xcode", "Browser & app caches",
                 "Unused extensions: VS Code, Cursor, JetBrains…", "Every risk clearly labelled"]
    var x = pad, y = card.maxY + 34
    for chip in chips {
        let label = text(chip, 21, .semibold, hex(0xCCFBF1))
        let size = label.size()
        let width = size.width + 36
        if x + width > W - pad { x = pad; y += 56 }
        let rect = NSRect(x: x, y: y, width: width, height: 44)
        hex(0x14B8A6, 0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).fill()
        hex(0x5EEAD4, 0.45).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22).stroke()
        label.draw(at: NSPoint(x: x + 18, y: y + (44 - size.height) / 2))
        x += width + 12
    }

    // Footer: the headline number and the safety promise.
    let footerY = H - pad - 118
    hex(0x5EEAD4, 0.25).setFill()
    NSRect(x: pad, y: footerY - 22, width: W - pad * 2, height: 1).fill()
    let stat = text(statText, 72, .heavy, hex(0x5EEAD4))
    stat.draw(at: NSPoint(x: pad, y: footerY + 2))
    let statWidth = stat.size().width
    text("reclaimable space\nfound on my Mac", 24, .semibold, .white, lineHeight: 30)
        .draw(in: NSRect(x: pad + statWidth + 20, y: footerY + 22, width: 240, height: 64))
    let promise = text("Everything goes to the Trash first.\nApps you're running are never touched.", 19, .medium, hex(0x99F6E4), lineHeight: 26)
    let promiseWidth = promise.boundingRect(with: NSSize(width: 400, height: 80), options: .usesLineFragmentOrigin).width
    promise.draw(in: NSRect(x: W - pad - promiseWidth, y: footerY + 24, width: promiseWidth + 2, height: 60))
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 2), pixelsHigh: Int(H * 2), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
canvas.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()
let out = marketing.appendingPathComponent("disksweep-announcement.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
