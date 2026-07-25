import SwiftUI

/// 一个分类的待办清单：顶部输入框记事，下面是这个分类的待办。
/// 朴素的单列，待完成与已完成只靠左侧圆圈区分 —— 分列与排序是后面的事。
struct CategoryTodoList: View {
    @Environment(Store.self) private var store
    let category: Category

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var todos: [TodoItem] { store.todos(in: category.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                input

                if todos.isEmpty {
                    empty
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(todos) { todo in
                            TodoRow(todo: todo, tint: category.color.tint)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // 换一个分类就是换一份清单，半句草稿不跟着走 —— 否则它会被记到另一个分类里去。
        .onChange(of: category.id) { draft = "" }
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
        .padding(.vertical, 11)
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
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// 记下草稿里的那件事。空白输入交给 `Store` 挡掉，这里只管清空并留住焦点，好让记事可以一条接一条。
    private func record() {
        store.addTodo(draft, in: category.id)
        draft = ""
        inputFocused = true
    }
}

/// 一行待办：左边的圆圈打勾/取消，悬停时右边浮出删除。
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
                .lineLimit(2)

            Spacer(minLength: 8)

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
