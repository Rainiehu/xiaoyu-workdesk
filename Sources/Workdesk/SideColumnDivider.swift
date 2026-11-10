import AppKit
import SwiftUI

/// 右列的宽度：分类视图的「已完成」列与沙漏视图的「未排期」列共用这一个数。
/// 两处的右列看着是同一块东西，就该真是同一个数 —— 在哪边拖宽了，切过去另一边也是这么宽。
/// 存在 UserDefaults 里，下次打开还是上回拖出来的样子；它是这台机器上的版面偏好，不进同步。
enum SideColumnWidth {
    static let key = "sideColumnWidth"
    static let defaultValue: Double = 264

    /// 再窄，日期标签就要挤着字了；再宽，右列就开始跟左列抢主角。
    static let range: ClosedRange<CGFloat> = 200...520

    /// 左列至少要留下的宽度。窗口窄的时候，右列让步，不是左列。
    static let mainMinWidth: CGFloat = 360

    /// 窗口给这一排的总宽是 `total` 时，右列实际能取到的宽度。
    /// 存下来的值不跟着窗口变：窗口缩窄时右列临时让步，窗口拉回来它就回到原样。
    static func clamped(_ width: Double, total: CGFloat) -> CGFloat {
        let upper = max(range.lowerBound, min(range.upperBound, total - mainMinWidth))
        return min(max(CGFloat(width), range.lowerBound), upper)
    }
}

/// 左右两列之间那道竖线，抓住可以左右拖，改的是右列的宽度。
/// 线还是那根 1pt 的细线；能抓住的是它两侧各几个点的一条窄带，鼠标进去变成左右箭头 ——
/// 平时看不出它能拖，手一碰到就知道。双击回到默认宽度。
struct SideColumnDivider: View {
    @AppStorage(SideColumnWidth.key) private var width = SideColumnWidth.defaultValue
    /// 这一排的总宽，用来在拖的时候就把右列限住，不让它把左列挤没。
    let total: CGFloat

    /// 拖动开始那一刻的宽度。手势给的是从起点算的位移，宽度要从这个数上加减，
    /// 不能从「上一帧的宽度」上累加 —— 那样位移被算了一遍又一遍。
    @State private var widthAtDragStart: CGFloat?
    @State private var hovering = false

    /// 抓得住的那条带子的宽度。
    private let grabWidth: CGFloat = 9

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: grabWidth)
                    .contentShape(Rectangle())
                    // 推与弹必须成对：鼠标停在线上时换了视图，也要把箭头弹掉，否则它会一直留在别处。
                    .onHover { inside in
                        guard inside != hovering else { return }
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .onDisappear {
                        if hovering { NSCursor.pop(); hovering = false }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                // 从屏上实际的宽度起拖：窗口窄时右列正在让步，存的值比看到的宽。
                                let start = widthAtDragStart ?? SideColumnWidth.clamped(width, total: total)
                                widthAtDragStart = start
                                // 线往左拖，右列变宽。
                                width = Double(SideColumnWidth.clamped(Double(start - value.translation.width), total: total))
                            }
                            .onEnded { _ in widthAtDragStart = nil }
                    )
                    .onTapGesture(count: 2) {
                        width = SideColumnWidth.defaultValue
                    }
            }
            // 抓手带子伸出线外几个点，压在右列上面；不抬高一层，右半边会被后画的右列接走。
            .zIndex(1)
    }
}
