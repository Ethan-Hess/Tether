#!/usr/bin/env swift
// Draws Tether's placeholder app icon and writes Packaging/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [output-dir]   (default: Packaging)
// Replace the result with real artwork any time; nothing else depends on how it was made.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Packaging"
let iconset = NSTemporaryDirectory() + "AppIcon-\(UUID().uuidString).iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: the artwork fills about 80% of the canvas.
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.07, green: 0.55, blue: 0.62, alpha: 1), NSColor(red: 0.20, green: 0.16, blue: 0.52, alpha: 1)])!
        .draw(in: shape, angle: -60)

    // Two interlocked links: a tether.
    NSColor.white.setStroke()
    for (dx, dy) in [(-0.11, 0.07), (0.11, -0.07)] {
        let link = NSBezierPath(roundedRect: NSRect(x: s * (0.5 + dx - 0.2), y: s * (0.5 + dy - 0.12), width: s * 0.4, height: s * 0.24),
                                xRadius: s * 0.12, yRadius: s * 0.12)
        var t = AffineTransform(translationByX: s * 0.5, byY: s * 0.5)
        t.rotate(byDegrees: 35)
        t.translate(x: -s * 0.5, y: -s * 0.5)
        link.transform(using: t)
        link.lineWidth = s * 0.055
        link.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                              ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes { try draw(px).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png")) }

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
guard p.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(outDir)/AppIcon.icns")
