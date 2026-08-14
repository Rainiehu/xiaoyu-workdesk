#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 分类屏拉出的那块副列：已经完成的事，按完成日从新到旧 —— 那是一份记录，不由人排。
/// 整列淡化、字号小一号，但仍然读得清楚：完成的事情是可查的记录，不是被划掉的废稿。
struct FinishedPanel: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock
    let category: Category

    var body: some View {
        let finished = store.columns(in: category.id).finished

        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "已完成")
            if finished.isEmpty {
                Text("打勾的事落到这边")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(finished) { todo in
                            // 删除态的行是原位占位：撤销窗口开着的那几秒它还站在这儿，见 ADR-0007。
                            if todo.isDeleted {
                                DeletedTodoRow(todo: todo, tint: category.color.tint)
                                    .font(.callout)
                            } else {
                                FinishedRow(todo: todo, tint: category.color.tint, today: clock.today)
                                // 完成的事带着它的步骤一起退到背景里，树照样常开。
                                SubTodoTree(parentID: todo.id, tint: category.color.tint)
                                    .font(.callout)
                            }
                        }
                    }
                    .padding(.horizontal, ScreenLayout.panelEdge)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .topEdgeFade()
                .opacity(0.62)
            }
        }
    }
}

/// 面板里的一行：勾圈亮着分类色，行尾常驻完成日标签 —— 它解释这一列为什么这么排。
/// 排期入口照样有（改期对完成行的意义是修记录），只是不再画计划日标签：
/// 一行上一个日期就够了。其余本事与三处的行一致。
private struct FinishedRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let tint: Color
    let today: Date

    @State private var editing = TodoEditing()

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, tint: tint) {
                store.toggleTodo(todo)
            }

            TodoText(todo: todo, editing: $editing)
                .font(.callout)

            Spacer(minLength: 8)

            if let completedAt = todo.completedAt {
                Text(completedAt.dayLabel(relativeTo: today))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PlannedDayEntry(todo: todo, showsDate: false)
        }
        .todoRowChrome()
        .contentShape(Rectangle())
        .todoRowActions(todo, editing: $editing)
        .todoDragSource(todo)
        .swipeToDelete(deleteTodo)
    }

    private func deleteTodo() {
        withAnimation { store.deleteTodo(todo) }
    }
}
#endif
