import AppKit
import SwiftUI

/// 窗口里有东西正在滚。
///
/// 滚动时行从静止的指针底下一行行掠过，每掠过一行就是一进一出两次悬停 —— 每一次都要浮出、
/// 收起排期入口与删除（各带一个工具提示，日历入口还挂着面板的锚），一屏几十行连着翻，滚动就卡。
/// 所以滚着的时候悬停一概不亮，停下来再认指针此刻落在哪一行。
///
/// 信号取自整个 app 的滚轮事件（触控板、鼠标滚轮、惯性滑行都是这一种），不挂在哪一个滚动视图上 ——
/// 轴、未排期列、分类视图两列、收藏流同一个道理，一处听着就够。最后一个事件过去一小会儿才算停：
/// 惯性滑行的事件之间也有空档，等得太短，滑行途中会一闪一闪地亮起来。
@Observable
@MainActor
final class ScrollActivity {
    private(set) var isScrolling = false

    @ObservationIgnored private var settle: Task<Void, Never>?
    @ObservationIgnored private var monitor: Any?

    /// 最后一个滚轮事件过去这么久，才算停下来。
    private static let settleDelay: Duration = .milliseconds(150)

    init() {
        // 本地监听只看不拦：事件原样放行，滚动照常发生。监听跟着 app 活，不必摘。
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // 只认竖着滚的：行都住在竖滚的列里，横滑 tab 栏时行不会从指针底下掠过，
            // 不该让刚移过去的那一行白等一拍才亮。
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
                MainActor.assumeIsolated { self?.noteScroll() }
            }
            return event
        }
    }

    private func noteScroll() {
        // 只在翻面时写：一秒上百个滚轮事件，每次都写会让读它的行跟着白算上百遍。
        if !isScrolling { isScrolling = true }
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.isScrolling = false
        }
    }
}

extension View {
    /// 行上的悬停：指针进出照记，滚动中一概不亮 —— 停下来时指针落在哪一行，哪一行才亮。
    /// 凡是住在滚动视图里、悬停会浮出东西的行，都走这一个，不直接用 `onHover`。
    func rowHover(_ hovering: Binding<Bool>) -> some View {
        modifier(RowHover(hovering: hovering))
    }
}

private struct RowHover: ViewModifier {
    @Environment(ScrollActivity.self) private var scroll
    @Binding var hovering: Bool
    /// 指针此刻在不在这一行上，滚着也照记 —— 停下来时靠它认出该亮哪一行。
    /// 它只在回调里读写，不进 body，滚动途中翻来翻去也不惊动这一行。
    @State private var pointerInside = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pointerInside = inside
                light(inside && !scroll.isScrolling)
            }
            .onChange(of: scroll.isScrolling) { _, scrolling in
                light(pointerInside && !scrolling)
            }
    }

    /// 只在真变了时才写 —— 行的外观只认这一个值，写一样的值也会让它白算一遍。
    private func light(_ lit: Bool) {
        if hovering != lit { hovering = lit }
    }
}
