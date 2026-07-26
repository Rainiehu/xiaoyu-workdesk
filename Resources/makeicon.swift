import AppKit
import CoreGraphics
import Foundation

/// macOS 图标的圆角方形其实是超椭圆，不是圆角矩形 —— n≈5 时最接近系统那一套。
func squircle(rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        // |x/a|^n + |y/b|^n = 1 的参数式
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// 画一个尺寸的图标。所有几何都按 1024 的比例算，于是每个尺寸都是矢量重绘，不是缩放。
func drawIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let k = s / 1024  // 比例尺

    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // 圆角方形：1024 画布里占 824，四边各留 100 —— 与系统图标的留白一致。
    let plate = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = squircle(rect: plate)

    // 不烤投影进来 —— Dock 和 Finder 会自己给图标加，烤进来只会在边上多出一圈暗环。
    // 青色渐变：左上亮、右下沉。延续 app 整体的青色主调。
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.40, green: 0.82, blue: 0.87, alpha: 1),
        CGColor(red: 0.11, green: 0.51, blue: 0.62, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: plate.minX, y: plate.maxY),
                           end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    ctx.restoreGState()

    let cx = s / 2, cy = s / 2
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

    // 沙漏：上下两个三角在腰部收拢，几乎相接 —— 缝太宽就读成两个三角，不是沙漏了。
    let halfW = 130 * k       // 上下沿的半宽
    let halfH = 208 * k       // 上下沿离中心的距离
    let waist = 7 * k         // 腰部的缝隙半高
    for sign in [CGFloat(1), -1] {
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: cx - halfW, y: cy + sign * halfH))
        tri.addLine(to: CGPoint(x: cx + halfW, y: cy + sign * halfH))
        tri.addLine(to: CGPoint(x: cx, y: cy + sign * waist))
        tri.closeSubpath()
        ctx.addPath(tri)
        ctx.fillPath()
    }

    // 上下两道横杠，沙漏的框。
    let capW = 156 * k, capH = 22 * k
    for sign in [CGFloat(1), -1] {
        let cap = CGRect(x: cx - capW, y: cy + sign * halfH - (sign > 0 ? 0 : capH),
                         width: capW * 2, height: capH)
        ctx.addPath(CGPath(roundedRect: cap, cornerWidth: capH / 2, cornerHeight: capH / 2,
                           transform: nil))
        ctx.fillPath()
    }

    // 今天那条线：横穿腰部，两头都伸出沙漏之外 —— 横轴（分类）与纵轴（时间）在这儿交叉，
    // 而今天就锚在正中间。刻意画得细、半透明：一眼看见的该是沙漏，这条线是second read。
    let lineW = 268 * k, lineH = 13 * k
    let line = CGRect(x: cx - lineW, y: cy - lineH / 2, width: lineW * 2, height: lineH)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.82))
    ctx.addPath(CGPath(roundedRect: line, cornerWidth: lineH / 2, cornerHeight: lineH / 2,
                       transform: nil))
    ctx.fillPath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments[1]
// .icns 要的十张：五个逻辑尺寸各配一张 @2x。
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (size, name) in sizes {
    try drawIcon(size: size).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("✓ \(sizes.count) 张")
