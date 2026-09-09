import AppKit
import SwiftUI
import Testing
import WorkdeskCore
@testable import Workdesk

@MainActor
@Suite("悬停不改变待办行的布局")
struct HoverLayoutTests {
    @Test("删除按钮隐藏时仍留着同样的空间")
    func deleteKeepsItsSize() {
        let hidden = size(TodoDeleteButton(visible: false) {})
        let visible = size(TodoDeleteButton(visible: true) {})
        #expect(hidden.width > 0)
        #expect(hidden == visible)
    }

    @Test("排期入口与日期切换时不挤正文", arguments: [false, true], [false, true])
    func schedulingKeepsItsSize(planned: Bool, showsDate: Bool) {
        let day = Date(timeIntervalSince1970: 1_783_036_800)
        let todo = TodoItem(text: "待办", categoryID: UUID(), plannedOn: planned ? day : nil)
        let clock = TodayClock(now: day)
        func control(_ hovering: Bool) -> some View {
            PlannedDayControl(todo: todo, rowHovering: hovering, showsDate: showsDate)
                .environment(clock)
        }
        #expect(size(control(false)) == size(control(true)))

        // 用窄列和长正文量真实换行，避免只验证按钮自己的尺寸却漏掉整行的变化。
        for width: CGFloat in [180, 240, 400] {
            func row(_ hovering: Bool) -> some View {
                HStack(spacing: TodoRowLayout.spacing) {
                    Text("这是一条需要换行的待办，滚动时鼠标掠过也应保持正文的位置。")
                    Spacer(minLength: 8)
                    control(hovering)
                    TodoDeleteButton(visible: hovering) {}
                }
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
            }
            #expect(size(row(false)) == size(row(true)))
        }
    }

    private func size<V: View>(_ view: V) -> NSSize {
        let host = NSHostingView(rootView: view)
        return host.fittingSize
    }
}
