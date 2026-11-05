// 生成 Rake 图标：沙地底上一块深色卵石和三道耙纹。用法：swift make_icon.swift <输出.iconset 目录>
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    let ground = NSColor(srgbRed: 0xef/255, green: 0xeb/255, blue: 0xe1/255, alpha: 1)
    let ink = NSColor(srgbRed: 0x2a/255, green: 0x29/255, blue: 0x26/255, alpha: 1)
    let rake = NSColor(srgbRed: 0xcd/255, green: 0xc7/255, blue: 0xb8/255, alpha: 1)
    ground.setFill(); NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()
    rake.setStroke()
    for i in 0..<4 {
        let r = CGFloat(140 + i * 46)
        let p = NSBezierPath(ovalIn: NSRect(x: 640 - r, y: 600 - r * 0.78, width: r * 2, height: r * 1.56)); p.lineWidth = 14; p.stroke()
    }
    ink.setFill()
    let stone = NSBezierPath()
    stone.move(to: NSPoint(x: 250, y: 330)); stone.curve(to: NSPoint(x: 560, y: 250), controlPoint1: NSPoint(x: 330, y: 230), controlPoint2: NSPoint(x: 470, y: 220))
    stone.curve(to: NSPoint(x: 600, y: 470), controlPoint1: NSPoint(x: 650, y: 290), controlPoint2: NSPoint(x: 660, y: 420))
    stone.curve(to: NSPoint(x: 280, y: 520), controlPoint1: NSPoint(x: 520, y: 560), controlPoint2: NSPoint(x: 330, y: 590))
    stone.curve(to: NSPoint(x: 250, y: 330), controlPoint1: NSPoint(x: 220, y: 470), controlPoint2: NSPoint(x: 200, y: 380))
    stone.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
