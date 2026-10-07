// Draws the Shelf app icon and builds Resources/AppIcon.icns.
// Run: swift scripts/make_icon.swift
import AppKit

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func drawIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824 pt body inside a 1024 canvas.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: color(72, 72, 76), ending: color(28, 28, 30))!.draw(in: body, angle: -90)

    // Three cards on a shelf, back to front.
    let cardW: CGFloat = 250, cardH: CGFloat = 340, step: CGFloat = 120, y: CGFloat = 330
    let startX = 512 - (cardW + 2 * step) / 2
    for (i, alpha) in [0.22, 0.5, 1.0].enumerated() {
        let rect = NSRect(x: startX + CGFloat(i) * step, y: y, width: cardW, height: cardH)
        color(255, 255, 255, alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 38, yRadius: 38).fill()
    }

    // Content lines on the front card.
    let front = NSRect(x: startX + 2 * step, y: y, width: cardW, height: cardH)
    let left = front.minX + 36
    color(44, 44, 46).setFill()
    NSBezierPath(roundedRect: NSRect(x: left, y: front.maxY - 74, width: 110, height: 26), xRadius: 13, yRadius: 13).fill()
    color(205, 205, 210).setFill()
    for (i, w) in [178.0, 150, 168, 120].enumerated() {
        let lineY = front.maxY - 134 - CGFloat(i) * 44
        NSBezierPath(roundedRect: NSRect(x: left, y: lineY, width: w, height: 18), xRadius: 9, yRadius: 9).fill()
    }

    // The shelf.
    color(255, 255, 255, 0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 282, width: 560, height: 22), xRadius: 11, yRadius: 11).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let master = root.appendingPathComponent("Resources/AppIcon-1024.png")
try! drawIcon().representation(using: .png, properties: [:])!.write(to: master)

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let px = size * scale
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        task.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path]
        task.standardOutput = FileHandle.nullDevice
        try! task.run(); task.waitUntilExit()
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run(); iconutil.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
