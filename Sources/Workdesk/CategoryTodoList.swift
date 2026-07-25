import SwiftUI

/// 一个分类里的待办，左右分列：左边待完成，右边已完成，同屏可见、互不干扰。
/// 左列突出、右列整体淡化 —— 注意力自然落在还没做的事情上，做完的事退成可查的背景。
///
/// 两列的顺序都由 `Store.columns(in:)` 定，这里一行排序也不做。左列的两段（已排期、未排期）
/// 直接拼在一起，不设分组标题 —— 靠日期标签的有无自然区分。
///
/// 时间在这个视图里刻意弱化：日期只是行尾一个低对比度的次要标签，不构成组织结构 ——
/// 在分类里关心的是「有哪些事」，不是「排在哪天」。
struct CategoryTodoList: View {
    @Environment(Store.self) private var store
    let category: Category

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    /// 右列的宽度。定死一个值而不是按比例分 —— 左列于是随窗口一起长，
    /// 「哪边是主角」不随窗口宽度动摇。
    private let finishedColumnWidth: CGFloat = 264

    /// 左列的内容宽度上限。窗口再宽，一行字也不跟着摊开。
    private let unfinishedColumnMaxWidth: CGFloat = 620

    /// 输入框那一条的高度。写成常量而不是由内容撑开：右列要照着它在顶上留出一段，
    /// 好让两列的第一行齐平 —— 两列因此看着是一块板，不是两块各自开始的东西。
    private let inputHeight: CGFloat = 42

    /// 两列共同的上留白。
    private let topInset: CGFloat = 28

    var body: some View {
        let columns = store.columns(in: category.id)

        HStack(alignment: .top, spacing: 0) {
            unfinishedColumn(columns.unfinished, blank: columns.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // 一件事都没有的时候不分列：那时没有「已完成」可谈，整个界面就是一段引导。
            if !columns.isEmpty {
                Divider()
                finishedColumn(columns.finished)
                    .frame(width: finishedColumnWidth)
            }
        }
    }

    /// 左列：记事的入口留在顶上，下面是还没完成的事。
    private func unfinishedColumn(_ todos: [TodoItem], blank: Bool) -> some View {
        VStack(spacing: 0) {
            // 输入框在 ScrollView 外面：待办再多也留在顶上，记事随时都在手边。
            input
                .padding(.horizontal, 28)
                .padding(.top, topInset)
                .frame(maxWidth: unfinishedColumnMaxWidth)

            if blank {
                empty
            } else {
                list(todos)
                    .frame(maxWidth: unfinishedColumnMaxWidth, alignment: .leading)
                    .overlay { if todos.isEmpty { hint("都做完了") } }
            }
        }
    }

    /// 右列：已经完成的事，按完成日从新到旧。整列淡化、字号小一号，
    /// 但仍然读得清楚 —— 完成的事情是可查的记录，不是被划掉的废稿。
    private func finishedColumn(_ todos: [TodoItem]) -> some View {
        list(todos)
            .font(.callout)
            // 顶上让出输入框那一条，右列的第一行于是与左列的第一行齐平。
            .padding(.top, topInset + inputHeight)
            .opacity(0.62)
            .overlay { if todos.isEmpty { hint("打勾的事落到这边") } }
    }

    private func list(_ todos: [TodoItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(todos) { todo in
                    TodoRow(todo: todo, tint: category.color.tint)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var input: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(category.color.tint.opacity(0.8))
                .imageScale(.large)
            TextField("记一件事，回车记下…", text: $draft)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(record)
        }
        .padding(.horizontal, 14)
        .frame(height: inputHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
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

    /// 一列空着时的一句话。轻到几乎不占分量 —— 它说明这列是干什么的，不催人做事。
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    /// 记下草稿里的那件事。空白输入交给 `Store` 挡掉，这里只管清空并留住焦点，好让记事可以一条接一条。
    private func record() {
        store.addTodo(draft, in: category.id)
        draft = ""
        inputFocused = true
    }
}

/// 一行待办：左边的圆圈打勾/取消，悬停时右边浮出删除。
/// 已完成的不带删除线 —— 完成的事情读起来该仍然清晰体面。淡化交给所在那一列，行本身不管。
private struct TodoRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let tint: Color
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.toggleTodo(todo)
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(todo.done ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(todo.done ? "取消完成" : "标记完成")

            Text(todo.text)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            // 完成了的行上，日期是完成日，而且只是个标签 —— 它说明右列为什么这么排。
            // 排期入口留给还没做的事：做完了再改期没有意义，真要改，取消打勾就回到左列。
            // 有完成日就等于完成了，这条由 `Store` 保证，所以这儿只问一次。
            if let completedAt = todo.completedAt {
                Text(completedAt.dayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                PlannedDayControl(todo: todo, rowHovering: hovering)
            }

            if hovering {
                Button {
                    withAnimation { store.deleteTodo(todo) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.35)) : AnyShapeStyle(.clear))
        )
        .onHover { hovering = $0 }
    }
}
