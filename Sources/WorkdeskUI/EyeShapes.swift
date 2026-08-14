import SwiftUI

// 「隐藏已完成」那只眼的自绘轮廓。SF Symbols 只有 eye / eye.slash、没有闭眼，
// 所以两副形态都自绘：同一条轮廓在睁闭之间连续变形，拨那一下是一次真的眨眼，
// 不是两张图的硬切。两端同一双眼 —— 纯几何，与呈现无关，所以住在共享层。

/// 眼睑的轮廓：`openness` 从 1（睁）到 0（闭）连续可变。睁着是杏仁形的上下睑，
/// 闭上时两条睑合到同一道下弯的弧上 —— 弧朝下，闭着的眼才不会被读成一条抿直的嘴。
public struct EyeLids: Shape {
    public var openness: CGFloat

    public init(openness: CGFloat) {
        self.openness = openness
    }

    public var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let left = CGPoint(x: rect.minX + 0.09 * rect.width, y: rect.minY + 0.47 * rect.height)
        let right = CGPoint(x: rect.maxX - 0.09 * rect.width, y: left.y)
        // 二次曲线的控制点：睁着时上睑弓到顶、下睑坠到底（都越出格子，弓出来的
        // 顶点才落在格内），闭上时两条一起落到同一个点 —— 那道下弯的弧。
        let closed = rect.minY + 0.66 * rect.height
        let top = closed + (rect.minY - 0.03 * rect.height - closed) * openness
        let bottom = closed + (rect.minY + 1.03 * rect.height - closed) * openness
        var path = Path()
        path.move(to: left)
        path.addQuadCurve(to: right, control: CGPoint(x: rect.midX, y: top))
        path.addQuadCurve(to: left, control: CGPoint(x: rect.midX, y: bottom))
        return path
    }
}

/// 闭眼时那三根睫毛。只在闭合时露面，露不露由外面的透明度管，形状本身不变。
public struct EyeLashes: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let lashes: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0.26, y: 0.59), CGPoint(x: 0.20, y: 0.71)),
            (CGPoint(x: 0.50, y: 0.63), CGPoint(x: 0.50, y: 0.76)),
            (CGPoint(x: 0.74, y: 0.59), CGPoint(x: 0.80, y: 0.71)),
        ]
        var path = Path()
        for (from, to) in lashes {
            path.move(to: CGPoint(x: rect.minX + from.x * rect.width, y: rect.minY + from.y * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + to.x * rect.width, y: rect.minY + to.y * rect.height))
        }
        return path
    }
}
