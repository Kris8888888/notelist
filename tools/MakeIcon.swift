import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((h>>16)&255)/255, green: CGFloat((h>>8)&255)/255, blue: CGFloat(h&255)/255, alpha: a) }
func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024
    let body = NSRect(x: 100*u, y: 100*u, width: 824*u, height: 824*u)
    let shadow = NSShadow(); shadow.shadowBlurRadius = 30*u; shadow.shadowOffset = NSSize(width: 0, height: -12*u); shadow.shadowColor = hex(0x000000, 0.25)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    let path = NSBezierPath(roundedRect: body, xRadius: 185*u, yRadius: 185*u)
    hex(0xF5E9C8).setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    path.addClip()
    hex(0xB4862A, 0.18).setFill(); NSRect(x: body.minX, y: body.maxY - 44*u, width: body.width, height: 44*u).fill()
    hex(0xB4862A).setFill(); NSRect(x: body.minX, y: body.maxY - 44*u, width: body.width * 0.62, height: 44*u).fill()
    let ink = hex(0xB4862A), text = hex(0x3B3222)
    let rows: [(Bool, CGFloat)] = [(true, 0.55), (true, 0.40), (false, 0.50)]
    for (i, r) in rows.enumerated() {
        let cy = body.maxY - 270*u - CGFloat(i) * 175*u
        let c = NSRect(x: 230*u, y: cy - 48*u, width: 96*u, height: 96*u)
        let circ = NSBezierPath(ovalIn: c.insetBy(dx: 7*u, dy: 7*u))
        if r.0 {
            ink.setFill(); NSBezierPath(ovalIn: c).fill()
            let ck = NSBezierPath(); ck.lineWidth = 16*u; ck.lineCapStyle = .round; ck.lineJoinStyle = .round
            ck.move(to: NSPoint(x: c.minX + 26*u, y: c.midY)); ck.line(to: NSPoint(x: c.minX + 43*u, y: c.midY - 18*u)); ck.line(to: NSPoint(x: c.maxX - 24*u, y: c.midY + 20*u))
            hex(0xF5E9C8).setStroke(); ck.stroke()
        } else { circ.lineWidth = 14*u; ink.setStroke(); circ.stroke() }
        let bar = NSBezierPath(roundedRect: NSRect(x: 380*u, y: cy - 16*u, width: 430*u * r.1 / 0.55, height: 32*u), xRadius: 16*u, yRadius: 16*u)
        (r.0 ? text.withAlphaComponent(0.28) : text.withAlphaComponent(0.85)).setFill(); bar.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (n, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(n).png"))
}
