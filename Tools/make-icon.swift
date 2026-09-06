// 生成 App 图标:一枚液态玻璃质感的"译"字键帽。用法:
//   swift Tools/make-icon.swift <输出目录>
// 产出 <输出目录>/AppIcon-1024.png 与 AppIcon-256.png,再由 `make icon` 转 .icns
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixels)
    let u = s / 1024 // 以 1024 为基准的比例单位

    // 键帽
    let capRect = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let cap = NSBezierPath(roundedRect: capRect, xRadius: 196 * u, yRadius: 196 * u)

    // 投影
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -16 * u), blur: 44 * u,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
        NSColor(calibratedRed: 0.26, green: 0.38, blue: 0.95, alpha: 1).setFill()
        cap.fill()
        ctx.restoreGState()
    }

    // 玻璃机身:亮蓝 → 深靛渐变(上透下沉,通透对比)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.56, green: 0.74, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.36, green: 0.50, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.18, green: 0.27, blue: 0.90, alpha: 1),
    ])!.draw(in: cap, angle: -90)

    // 液态玻璃高光弧面:一块宽椭圆和键帽的交集,下缘呈"微笑"弧线
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        cap.addClip()
        let glossRect = NSRect(x: 0 * u, y: 470 * u, width: 1024 * u, height: 780 * u)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.42),
            NSColor.white.withAlphaComponent(0.20),
            NSColor.white.withAlphaComponent(0.06),
        ])!.draw(in: NSBezierPath(ovalIn: glossRect), angle: -90)
        ctx.restoreGState()
    }

    // 底部反射光(玻璃底边的环境反光)
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        cap.addClip()
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.20),
            NSColor.white.withAlphaComponent(0.0),
        ])!.draw(in: NSBezierPath(rect: NSRect(x: capRect.minX, y: capRect.minY,
                                               width: capRect.width, height: 170 * u)),
                 angle: 90)
        ctx.restoreGState()
    }

    // 液态玻璃厚边:上亮下暗的发光环(标志性特征),用奇偶填充的环形区域画渐变
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        let ring = NSBezierPath(roundedRect: capRect.insetBy(dx: 4 * u, dy: 4 * u),
                                xRadius: 193 * u, yRadius: 193 * u)
        ring.append(NSBezierPath(roundedRect: capRect.insetBy(dx: 20 * u, dy: 20 * u),
                                 xRadius: 180 * u, yRadius: 180 * u))
        ring.windingRule = .evenOdd
        ring.addClip()
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.85),
            NSColor.white.withAlphaComponent(0.30),
            NSColor.white.withAlphaComponent(0.14),
            NSColor.white.withAlphaComponent(0.38),
        ])!.draw(in: NSBezierPath(roundedRect: capRect, xRadius: 196 * u, yRadius: 196 * u),
                 angle: -90)
        ctx.restoreGState()
    }

    // “译”字
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.40, alpha: 0.35)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -10 * u)
    glyphShadow.shadowBlurRadius = 24 * u
    let font = NSFont(name: "PingFangSC-Semibold", size: 520 * u)
        ?? NSFont.systemFont(ofSize: 520 * u, weight: .semibold)
    let glyph = NSAttributedString(string: "译", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
        .shadow: glyphShadow,
    ])
    let gs = glyph.size()
    glyph.draw(at: NSPoint(x: (s - gs.width) / 2, y: (s - gs.height) / 2 + 14 * u))

    // 回车角标(键帽语义)
    let enter = NSAttributedString(string: "⏎", attributes: [
        .font: NSFont.systemFont(ofSize: 120 * u, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.42),
    ])
    enter.draw(at: NSPoint(x: capRect.maxX - 236 * u, y: capRect.minY + 84 * u))

    return rep
}

for pixels in [1024, 256] {
    let rep = render(pixels: pixels)
    let png = rep.representation(using: .png, properties: [:])!
    let path = "\(outDir)/AppIcon-\(pixels).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
