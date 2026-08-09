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

/// 手绘的抖动：两个不同频的正弦叠加，相位由 seed 决定，每一笔抖得都不一样。
/// 全部在 1024 的坐标系里算完再缩放 —— 十个尺寸抖的是同一只手，小图不会另抖出一套。
func wobble(_ t: Double, seed: Double) -> Double {
    3.2 * sin(t * 7.1 + seed * 1.93) + 2.1 * sin(t * 13.7 + seed * 3.71)
}

/// 一支会抖的钢笔。设计坐标沿用 y 向下的习惯（与草图一致），落笔时翻回 CG 的 y 向上。
struct Pen {
    let ctx: CGContext
    let k: CGFloat

    private func pt(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * Double(k), y: (1024 - y) * Double(k))
    }

    /// 沿一条二次贝塞尔画一笔，笔迹沿法向轻微抖动。
    func quad(_ p0: (Double, Double), _ c: (Double, Double), _ p1: (Double, Double),
              width: Double, seed: Double) {
        let path = CGMutablePath()
        let steps = 48
        for i in 0...steps {
            let t = Double(i) / Double(steps), mt = 1 - t
            var x = mt * mt * p0.0 + 2 * mt * t * c.0 + t * t * p1.0
            var y = mt * mt * p0.1 + 2 * mt * t * c.1 + t * t * p1.1
            let dx = 2 * mt * (c.0 - p0.0) + 2 * t * (p1.0 - c.0)
            let dy = 2 * mt * (c.1 - p0.1) + 2 * t * (p1.1 - c.1)
            let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
            // 两端把抖动收到零：端点要落准（四条斜边在腰部几乎相接，端点一偏就交叉成 X），
            // 手绘味交给中段。
            let off = wobble(t, seed: seed) * min(1, 1.8 * sin(.pi * t))
            x -= dy / len * off
            y += dx / len * off
            i == 0 ? path.move(to: pt(x, y)) : path.addLine(to: pt(x, y))
        }
        stroke(path, width: width)
    }

    /// 手抖版超椭圆环，半径随角度轻微起伏。抖动只用整数倍角频率，转一圈正好接回起点。
    func squircleRing(r: Double, width: Double, seed: Double) {
        let path = CGMutablePath()
        let steps = 300
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let rr = r + 3.0 * sin(3 * t + seed * 1.7) + 2.2 * sin(7 * t + seed * 2.9)
            let ct = cos(t), st = sin(t)
            let x = 512 + rr * pow(abs(ct), 2 / 5.0) * (ct < 0 ? -1 : 1)
            let y = 512 + rr * pow(abs(st), 2 / 5.0) * (st < 0 ? -1 : 1)
            i == 0 ? path.move(to: pt(x, y)) : path.addLine(to: pt(x, y))
        }
        path.closeSubpath()
        stroke(path, width: width)
    }

    func dot(_ x: Double, _ y: Double, r: Double) {
        let c = pt(x, y)
        let rr = CGFloat(r) * k
        ctx.fillEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
    }

    private func stroke(_ path: CGPath, width: Double) {
        ctx.setLineWidth(CGFloat(width) * k)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }
}

/// 画一个尺寸的图标。所有几何都按 1024 的比例算，于是每个尺寸都是矢量重绘，不是缩放。
/// - Parameter fullBleed: iOS 要的全出血方形 —— 纸底铺满整个画布（圆角由系统的遮罩切），
///   图案按 1024/824 放大，好让沙漏在两个平台上占同样的视觉比例。macOS 传 false：
///   1024 画布里留白的超椭圆纸片。
func drawIcon(size: Int, fullBleed: Bool = false) -> Data {
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

    // 不烤投影进来 —— Dock 和 Finder 会自己给图标加，烤进来只会在边上多出一圈暗环。
    // 黑白手绘钢笔线稿：暖白的纸底，墨色的线。
    let paper = CGColor(red: 0.992, green: 0.988, blue: 0.976, alpha: 1)
    let ink = CGColor(red: 0.106, green: 0.102, blue: 0.094, alpha: 1)
    if fullBleed {
        ctx.setFillColor(paper)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        // 图案放大到原来纸片的比例：以画布中心为轴，824 的纸片撑满 1024。
        let scale = 1024.0 / 824.0
        ctx.translateBy(x: s / 2, y: s / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -s / 2, y: -s / 2)
    } else {
        ctx.addPath(squircle(rect: plate))
        ctx.setFillColor(paper)
        ctx.fillPath()
    }

    ctx.setStrokeColor(ink)
    ctx.setFillColor(ink)
    let pen = Pen(ctx: ctx, k: k)

    // 手绘的边框圈，替系统的圆角方形在纸上再描一遍 —— 白底图标在浅色 Dock 里靠它定形。
    pen.squircleRing(r: 372, width: 15, seed: 1)

    // 沙漏：上下两道横杠是框，四条斜边在腰部收拢。
    pen.quad((356, 302), (512, 291), (668, 305), width: 24, seed: 2)
    pen.quad((356, 724), (512, 734), (668, 720), width: 24, seed: 3)
    pen.quad((384, 314), (448, 410), (506, 501), width: 24, seed: 4)
    pen.quad((640, 312), (576, 410), (518, 501), width: 24, seed: 5)
    pen.quad((384, 710), (448, 616), (506, 523), width: 24, seed: 6)
    pen.quad((640, 712), (576, 616), (518, 523), width: 24, seed: 7)

    // 下半的沙堆一弧，腰口落下的沙三点。
    pen.quad((446, 700), (512, 648), (578, 701), width: 22, seed: 8)
    pen.dot(512, 552, r: 9)
    pen.dot(508, 592, r: 8)
    pen.dot(515, 632, r: 7)

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments[1]

// `--ios` 只出一张 1024 的全出血方形 —— iOS 的资产目录就要这一张，圆角系统自己切。
if CommandLine.arguments.contains("--ios") {
    try drawIcon(size: 1024, fullBleed: true)
        .write(to: URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon-1024.png"))
    print("✓ 1 张（iOS 全出血）")
} else {
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
}
