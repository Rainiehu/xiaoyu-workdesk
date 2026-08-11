#if os(iOS)
import SwiftUI
import UIKit

/// 纸与墨。整个 iOS 端的底是一张纸：logo 的纸色铺底、罩一层纸纤维的噪点，
/// 内容浮成白卡片，正文用 logo 的墨色 —— 色值与 `Resources/makeicon.swift`
/// 画图标用的 paper/ink 同源，app 和它的图标是同一张纸上的东西。
enum PaperTheme {
    /// logo 的纸色。深色外观是同一张纸的墨夜版。
    static let paper = dynamicColor(light: 0xFDFCF9, dark: 0x201F1C)
    /// logo 的墨色，正文用它 —— 纯黑太硬，这是磨出来的墨。
    static let ink = dynamicColor(light: 0x1B1A18, dark: 0xECEAE4)
    /// 浮在纸上的卡片面。浅色下就是纯白：纸底压不深，卡片靠「净 / 纹」区分。
    static let card = dynamicColor(light: 0xFFFFFF, dark: 0x2A2925)

    private static func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension View {
    /// 一屏的纸底：纸色平铺到底。试过罩噪点做纤维肌理，屏上看是脏灰，撤了 ——
    /// 纸味交给色温，层次交给卡片的描边与影。
    func paperGround() -> some View {
        background(PaperTheme.paper.ignoresSafeArea())
    }

    /// 滚动内容的顶缘淡出：与内容区之间不画线（tab 条下、面板头下都一样），
    /// 行滑到分界处是渐渐隐进纸里，不是被一刀切掉 —— 与云标前胶囊的淡出同一个语汇。
    func topEdgeFade(_ height: CGFloat = 18) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
                Color.black
            }
        }
    }

    /// 一块浮在纸上的卡片：白面、一圈淡墨描边、一道薄影。行和分组不用它 ——
    /// 内容融在纸里不描框（试过全面卡片化，屏上是一格一格的框，撤了）；
    /// 眼下只有输入栏这一件「工具」浮着。
    func paperCard(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(PaperTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(PaperTheme.ink.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: PaperTheme.ink.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }
}
#endif
