// Generates the app icon (AppIcon.iconset) — used by build.sh.
import AppKit

let side: CGFloat = 1024
let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
    let box = r.insetBy(dx: 100, dy: 100)
    let shape = NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.80, blue: 0.56, alpha: 1),
               ending: NSColor(calibratedRed: 0.04, green: 0.42, blue: 0.72, alpha: 1))!
        .draw(in: shape, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: 360, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let white = NSImage(size: symbol.size, flipped: false) { rr in
            symbol.draw(in: rr)
            NSColor.white.set()
            rr.fill(using: .sourceAtop)
            return true
        }
        let t = symbol.size
        white.draw(in: NSRect(x: (side - t.width) / 2, y: (side - t.height) / 2 - 20, width: t.width, height: t.height))
    }
    return true
}

let dest = CommandLine.arguments[1]
let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(dest)/icon_\(name).png"))
}
