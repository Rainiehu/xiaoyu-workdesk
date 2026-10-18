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
                        DeletedTodoRow(todo: todo, tint: category.color.tint)
                    } else if todo.isHeading {
                        HeadingRow(heading: todo, tint: category.color.tint)
                    } else {
                        CategoryRow(todo: todo, tint: category.color.tint)
                        // 子树常开，就摊在行底下 —— 与 Mac 同一条规矩。
                        SubTodoTree(parentID: todo.id, tint: category.color.tint)
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
    @Environment(TreeComposer.self) private var composer
    let todo: TodoItem
    let tint: Color

    @State private var editing = TodoEditing()

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, overdue: todo.isOverdue(today: clock.today), tint: tint) {
                store.toggleTodo(todo)
            }

            TodoText(todo: todo, editing: $editing, tree: store, composer: composer)

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
        // 光标的接力（回车新生）收在 `resumesTreeEditing` 一处。
        .resumesTreeEditing(todo, editing: $editing)
        .swipeToDelete(deleteTodo)
    }

    private func deleteTodo() {
        withAnimation { store.deleteTodo(todo) }
    }
}

/// 一个小标题：分类色胶囊，与 Mac 同一副 —— 它下面、到下一个小标题之前的待办就是这一节，
/// 节没有容器，只是手排顺序里的一道分界，见 ADR-0009。
///
/// 单击改名（回车收下并在这一节顶上开一行新待办）、左滑删除（只删这道分界，下面的待办并入上一节）；
/// 拖着的待办悬上来就换到它的位置 —— 越过它就换了一节。这一版欠着两件，与 `SubTodoTree.swift`
/// 头上那几笔同一本账：**新建**的入口跟长按菜单那一轮一起回来（Mac 走右键）；
/// **拖小标题整节跟着走**等自绘拖拽那一轮 —— 「悬到哪当场换到哪」的活重排拖着一整节，
/// 一路上会把别的节拦腰截开，得等落点能吸到节与节的交界上再做。
private struct HeadingRow: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let heading: TodoItem
    let tint: Color

    @State private var editing = TodoEditing()

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoText(todo: heading, editing: $editing, tree: store, composer: composer)
                .font(.caption.weight(.semibold))
                // 改名时胶囊随字伸缩，不铺满整行 —— 留一点底宽，空着时也看得出是个胶囊。
                .fixedSize(horizontal: editing.active, vertical: false)
                .frame(minWidth: editing.active ? 48 : nil, alignment: .leading)
                .categoryChip(tint)
            Spacer(minLength: 8)
        }
        // 胶囊不额外内缩，左缘与下面每一行的内缩起点对齐 —— 一节读起来是一块。
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // 改名走单击，不挂长按菜单：行上那份菜单只剩「移到分类」，小标题无此事。
        .onTapGesture {
            if !editing.active { editing.begin(heading) }
        }
        .todoDropTarget(entered: { id in
            guard id != heading.id else { return }
            withAnimation(.spring(duration: 0.2)) {
                if store.reorderTodo(id, onto: heading.id) {
                    Buzz.light.impactOccurred(); Buzz.warm()
                }
            }
        }, perform: { _ in
            Buzz.notify.notificationOccurred(.success)
            return true
        })
        .resumesTreeEditing(heading, editing: $editing)
        .swipeToDelete { withAnimation { store.deleteTodo(heading) } }
        // 节与节之间多留的那一段，放在左滑与落点外面：拖的、划的都是胶囊这一行。
        .padding(.top, 10)
    }
}
#endif
