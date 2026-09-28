// Draws the app icon: Slate's own (a dark square, three amber lines, from
// msalty/slate public/favicon.svg) with a calendar in the corner the short
// third line leaves free — Slate, plus what this app brings into it.
//
//   swift scripts/make-icon.swift OUT.iconset
//   iconutil -c icns OUT.iconset -o AppIcon.icns
//
// Drawn on macOS's 1024-point icon grid: the body is the 824-point square
// inside it, with the room around it that every Mac app icon has.

import AppKit
import CoreGraphics

let dark = CGColor(srgbRed: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255, alpha: 1)
let amber = CGColor(srgbRed: 0xe0 / 255, green: 0xa8 / 255, blue: 0x0d / 255, alpha: 1)

func draw(_ c: CGContext) {
    // 1024-point canvas, y down, like the SVG it follows.
    c.translateBy(x: 0, y: 1024)
    c.scaleBy(x: 1, y: -1)

    // The body, with a soft shadow as macOS icons have.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
    c.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                     cornerWidth: 185, cornerHeight: 185, transform: nil))
    c.setFillColor(dark)
    c.fillPath()
    c.restoreGState()

    // Slate's three lines: its 64-point drawing scaled onto the body.
    let k = 824.0 / 64
    func line(_ x1: Double, _ x2: Double, _ y: Double) {
        c.move(to: CGPoint(x: 100 + x1 * k, y: 100 + y * k))
        c.addLine(to: CGPoint(x: 100 + x2 * k, y: 100 + y * k))
    }
    c.setStrokeColor(amber)
    c.setLineCap(.round)
    c.setLineWidth(5 * k)
    line(18, 46, 20)
    line(18, 46, 30)
    line(18, 36, 40)
    c.strokePath()

    // The calendar, in the corner beside the short line.
    let cal = CGRect(x: 650, y: 660, width: 206, height: 176)
    c.setFillColor(amber)
    c.setLineWidth(28)
    c.setLineJoin(.round)
    c.addPath(CGPath(roundedRect: cal, cornerWidth: 34, cornerHeight: 34, transform: nil))
    c.strokePath()
    // Its header band.
    c.addPath(CGPath(roundedRect: CGRect(x: cal.minX, y: cal.minY, width: cal.width, height: 56),
                     cornerWidth: 34, cornerHeight: 34, transform: nil))
    c.fillPath()
    c.fill(CGRect(x: cal.minX, y: cal.minY + 28, width: cal.width, height: 28))
    // The two rings it hangs from.
    c.setLineWidth(28)
    for x in [cal.minX + 56, cal.maxX - 56] {
        c.move(to: CGPoint(x: x, y: cal.minY - 32))
        c.addLine(to: CGPoint(x: x, y: cal.minY + 12))
    }
    c.strokePath()
    // Days.
    for row in 0..<2 {
        for col in 0..<3 {
            let d = CGRect(x: cal.minX + 40 + Double(col) * 50, y: cal.minY + 82 + Double(row) * 42,
                           width: 26, height: 22)
            c.addPath(CGPath(roundedRect: d, cornerWidth: 7, cornerHeight: 7, transform: nil))
        }
    }
    c.fillPath()
}

func png(size: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.scaleBy(x: Double(size) / 1024, y: Double(size) / 1024)
    draw(c)
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
