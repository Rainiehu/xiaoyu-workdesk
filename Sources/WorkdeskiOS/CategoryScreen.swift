#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 分类屏：一条主列（待完成，突出），已完成折进右缘拉出的面板（阶段 3c 补上）。
/// 主列的顺序是使用者自己拖出来的，已排期与未排期混在一列里，
/// 靠日期标签的有无自然区分，见 ADR-0002。
///
/// 时间在这个屏里刻意弱化：日期只是行尾一个低对比度的次要标签，不构成组织结构。
struct CategoryScreen: View {
    @Environment(Store.self) private var store
    let category: Category

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    /// 已完成面板拉开着。
    @State private var finishedOpen = false

    var body: some View {
        let columns = store.columns(in: category.id)

        Group {
            if columns.isEmpty {
                empty
            } else {
                list(columns.unfinished)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { input }
        // 已完成是分类屏的副列，从右缘拉出 —— 与沙漏屏的未排期同一副把手。
        // 一件事都没有时不挂把手：那时没有「已完成」可谈，整屏是一段引导。
        .pullOutPanel(enabled: !columns.isEmpty, isOpen: $finishedOpen) {
            FinishedPanel(category: category)
        }
    }

    private func list(_ todos: [TodoItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(todos) { todo in
                    // 删除态的行是原位占位：撤销窗口开着的那几秒它还站在这儿，见 ADR-0007。
                    if todo.isDeleted {
                        DeletedTodoRow(todo: todo)
                    } else {
                        CategoryRow(todo: todo, tint: category.color.tint)
                    }
                }
            }
            .padding(.horizontal, ScreenLayout.screenEdge)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .topEdgeFade()
        .overlay { if todos.isEmpty { hint("都做完了") } }
    }

    private var input: some View {
        InputBar(
            tint: category.color.tint,
            prompt: "记一件事，记下…",
            text: $draft,
            focused: $inputFocused,
            submit: record
        ) {
            // 分类屏里记到哪个分类是不问自明的 —— 眼下这个分类就是了。
            EmptyView()
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 34))
                .foregroundStyle(category.color.tint.opacity(0.5))
            Text("「\(category.name)」还是空的")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    private func record() {
        store.addTodo(draft, in: category.id)
        draft = ""
        inputFocused = true
    }
}

/// 主列里的一行：打勾的圈（打勾点亮成分类色）、正文、行尾低对比度的计划日标签。
private struct CategoryRow: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock
    let todo: TodoItem
    let tint: Color

    @State private var editing = TodoEditing()

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, overdue: todo.isOverdue(today: clock.today), tint: tint) {
                store.toggleTodo(todo)
            }

            TodoText(todo: todo, editing: $editing)

            Spacer(minLength: 8)

            // 已排期的行，日期标签自己就是排期入口；未排期的是一枚日历图标。
            PlannedDayEntry(todo: todo)
        }
        .todoRowChrome()
        .contentShape(Rectangle())
        .todoRowActions(todo, editing: $editing)
        .todoDragSource(todo)
        // 主列的顺序归使用者自己拖：拖着的行悬到哪一行上，当场就换到那个位置 ——
        // 列表本身就是预览，松手即所见即所得，见 ADR-0002。
        .todoDropTarget(entered: { id in
            guard id != todo.id else { return }
            withAnimation(.spring(duration: 0.2)) {
                if store.reorderTodo(id, onto: todo.id) {
                    Buzz.light.impactOccurred(); Buzz.warm()
                }
            }
        }, perform: { _ in
            Buzz.notify.notificationOccurred(.success)
            return true
        })
        .swipeToDelete(deleteTodo)
    }

    private func deleteTodo() {
        withAnimation { store.deleteTodo(todo) }
    }
}
#endif
