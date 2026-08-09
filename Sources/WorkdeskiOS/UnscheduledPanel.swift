#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 沙漏屏拉出的那块副列：所有还没排期的未完成待办，按分类分组，
/// 组的顺序就是 tab 条的顺序。轴答「排在哪天」，它答「还有什么没安排」。
/// 分组由 `Store.unscheduled` 给出，这里不自己聚合、一行排序也不做。
struct UnscheduledPanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "未排期")
            groups
        }
    }

    @ViewBuilder
    private var groups: some View {
        let groups = store.unscheduled
        if groups.isEmpty {
            Text("每件事都排上了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        UnscheduledGroupView(group: group)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}

/// 面板里的一组：一个分类的彩色胶囊当组头，下面是它名下还没排期的待办。
/// 组头是这个面板里唯一着色的 tag —— 一组的颜色就是这一组的标题。
private struct UnscheduledGroupView: View {
    let group: UnscheduledGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CategoryTag(category: group.category)
                .padding(.leading, TodoRowLayout.horizontalInset)
                .padding(.bottom, 2)
            ForEach(group.todos) { todo in
                // 删除态的行是原位占位：撤销窗口开着的那几秒它还站在这儿，见 ADR-0007。
                if todo.isDeleted {
                    DeletedTodoRow(todo: todo)
                        .font(.callout)
                } else {
                    UnscheduledRow(todo: todo, tint: group.category.color.tint)
                }
            }
        }
    }
}

/// 面板里的一行：与另外两处同一副结构、同一套本事（打勾、左滑删、长按菜单、
/// 单击改写、排期入口）。窄列用 callout。
///
/// 打勾让它离开这一列，只是没有看得见的去处，所以那一下走得慢一点：
/// 圈先填实亮一拍，再淡出 —— 与 Mac 的未排期列同一副。
private struct UnscheduledRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let tint: Color

    @State private var editing = TodoEditing()
    /// 刚在这一行上打了勾，这条正在离开这一列。那一拍里圈画的是「已完成」
    /// 而待办本身还没变，所以状态记在这儿，不去问 `todo.done`。
    @State private var completing = false

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: completing, tint: tint, toggle: complete)

            TodoText(todo: todo, editing: $editing)
                .font(.callout)

            Spacer(minLength: 8)

            PlannedDayEntry(todo: todo)
        }
        .todoRowChrome()
        .contentShape(Rectangle())
        .todoRowActions(todo, editing: $editing, delete: deleteTodo)
        // 抓的是同一样东西 —— 拖出面板落到轴上露着的那条主列上也是排期，
        // 只是面板盖着轴，这条路窄；主要路径是行上的排期入口。
        .draggable(DraggedTodo(id: todo.id)) {
            TodoDragPreview(text: todo.text, tint: tint)
        }
        .swipeToDelete(deleteTodo)
    }

    /// 打勾：圈先亮起来，过一拍这条才真的记成完成、跟着淡出这一列。
    /// 中间那一拍是说给人看的 —— 没有它，点下去只看得见一行凭空消失。
    private func complete() {
        guard !completing else { return }
        completing = true
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.2)) { store.toggleTodo(todo) }
        }
    }

    private func deleteTodo() {
        withAnimation { store.deleteTodo(todo) }
    }
}
#endif
