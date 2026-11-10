// Draws the DMG window background: "drag the app to Applications", with an arrow
// between the two icon positions used by build.sh (160,190) and (480,190).
// Usage: swift tools/make_dmg_background.swift <out-dir>
import AppKit

func render(scale: CGFloat) -> Data {
    let size = NSSize(width: 640, height: 400)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Same neutrals as the app's light theme.
    NSColor(srgbRed: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    // Arrow (y is flipped: Finder's 190 from top = 210 from bottom).
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 248, y: 210))
    arrow.line(to: NSPoint(x: 384, y: 210))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    let grey = NSColor(srgbRed: 0x5D / 255, green: 0x65 / 255, blue: 0x70 / 255, alpha: 1)
    grey.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 370, y: 224))
    head.line(to: NSPoint(x: 388, y: 210))
    head.line(to: NSPoint(x: 370, y: 196))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    func text(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                   .foregroundColor: color, .paragraphStyle: p])
            .draw(in: NSRect(x: 0, y: y, width: 640, height: size * 1.5))
    }
    text("Drag Temp Monitor to Applications to install", y: 64, size: 15, weight: .semibold,
         color: NSColor(srgbRed: 0x15 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 1))
    text("Then open Temp Monitor from your Applications folder", y: 38, size: 12, weight: .regular, color: grey)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
