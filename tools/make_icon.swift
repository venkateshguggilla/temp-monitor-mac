// Renders the app icon at every macOS size and packs it into Resources/AppIcon.icns.
// Usage: swift tools/make_icon.swift
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Draws on a 1024-unit canvas. Below 64 px the bars would just be smudges, so small
/// sizes show the thermometer alone, centred and larger.
func render(px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)
    let small = px < 64

    // Tile: macOS icon grid (824 pt body inside 1024, continuous-ish corners).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x1A1F26))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let shade = CGGradient(colorsSpace: nil, colors: [color(0x232A33), color(0x111418)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    ctx.addPath(tilePath)
    ctx.setStrokeColor(color(0x2E3641))
    ctx.setLineWidth(6)
    ctx.strokePath()

    // Thermometer.
    let cx: CGFloat = small ? 512 : 400
    let k: CGFloat = small ? 1.18 : 1        // scale for the small variant
    let tubeW = 120 * k, bulbR = 112 * k
    let bulbC = CGPoint(x: cx, y: 512 - 230 * k)
    let tubeTop = 512 + 290 * k
    let outline = CGMutablePath()
    outline.addRoundedRect(in: CGRect(x: cx - tubeW / 2, y: bulbC.y, width: tubeW, height: tubeTop - bulbC.y),
                           cornerWidth: tubeW / 2, cornerHeight: tubeW / 2)
    outline.addEllipse(in: CGRect(x: bulbC.x - bulbR, y: bulbC.y - bulbR, width: bulbR * 2, height: bulbR * 2))
    ctx.addPath(outline)
    ctx.setFillColor(color(0xE8ECF1))
    ctx.fillPath()

    // Mercury: green → amber → red, bottom to top.
    let inset = 26 * k
    let mercTop = 512 + 170 * k
    let merc = CGMutablePath()
    let mw = tubeW - inset * 2
    merc.addRoundedRect(in: CGRect(x: cx - mw / 2, y: bulbC.y, width: mw, height: mercTop - bulbC.y),
                        cornerWidth: mw / 2, cornerHeight: mw / 2)
    let mr = bulbR - inset
    merc.addEllipse(in: CGRect(x: bulbC.x - mr, y: bulbC.y - mr, width: mr * 2, height: mr * 2))
    ctx.saveGState()
    ctx.addPath(merc)
    ctx.clip()
    let heat = CGGradient(colorsSpace: nil, colors: [color(0x3DD68C), color(0xF5B83D), color(0xFF5C5C)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(heat, start: CGPoint(x: cx, y: bulbC.y - mr), end: CGPoint(x: cx, y: mercTop), options: [])
    ctx.restoreGState()

    if !small {
        // Tick marks beside the tube.
        ctx.setStrokeColor(color(0x8A94A3))
        ctx.setLineCap(.round)
        ctx.setLineWidth(18)
        for i in 0..<4 {
            let y = 512 - 60 + CGFloat(i) * 95
            ctx.move(to: CGPoint(x: cx + tubeW / 2 + 28, y: y))
            ctx.addLine(to: CGPoint(x: cx + tubeW / 2 + (i % 2 == 0 ? 84 : 60), y: y))
        }
        ctx.strokePath()

        // Usage: three rising bars.
        let base: CGFloat = 512 - 300
        let heights: [CGFloat] = [190, 330, 480]
        for (i, h) in heights.enumerated() {
            let x = 590 + CGFloat(i) * 92
            let bar = CGPath(roundedRect: CGRect(x: x, y: base, width: 66, height: h),
                             cornerWidth: 20, cornerHeight: 20, transform: nil)
            ctx.addPath(bar)
            ctx.setFillColor(color(0x4C9AFF, i == 2 ? 1 : 0.55 + CGFloat(i) * 0.2))
            ctx.fillPath()
        }
    }

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(px: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(px: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(px: 1024).write(to: root.appendingPathComponent("Resources/icon-1024.png"))
print("wrote \(iconset.path)")
