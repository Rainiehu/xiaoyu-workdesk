#if os(iOS)
import SwiftUI
import UIKit
import WorkdeskCore

extension UIColor {
    /// 0xRRGGBB。与 Mac 端同一种写法 —— 色值本身定在核心的 `PaletteValues.swift` 一处。
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension CategoryColor {
    /// 色名到 iOS 的动态颜色：浅色外观下用深的那副，深色外观下用浅的那副。
    /// 数值取自核心的 `rgbValues`，与 Mac 永远是同一张表。
    var tint: Color {
        let (light, dark) = rgbValues
        return Color(UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    /// 过期记号的琥珀。数值与 Mac 同一处（`OverdueAmber`），分寸也一样：弱提醒，不抢戏。
    static let overdueAmber = Color(UIColor { trait in
        UIColor(rgb: trait.userInterfaceStyle == .dark ? OverdueAmber.dark : OverdueAmber.light)
    })

    /// 胶囊的底色与描边。tab 的选中态和未排期面板的组头都从这儿取 ——
    /// 与 Mac 端同一个公式，两端因此永远是同一副胶囊。
    var chipFill: Color { opacity(0.15) }
    var chipStroke: Color { opacity(0.5) }
}
#endif
