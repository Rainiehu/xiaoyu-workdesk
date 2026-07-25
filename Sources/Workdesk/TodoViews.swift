import SwiftUI

// MARK: - 今日

struct TodayView: View {
    @Environment(Store.self) private var store
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var pending: [TodoItem] { store.todayTodos.filter { !$0.done } }
    private var finished: [TodoItem] { store.todayTodos.filter(\.done) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                inputBar

                if !store.overdueTodos.isEmpty {
                    todoGroup("早前未完成", items: store.overdueTodos, tint: .orange, showMoveToToday: true)
                }
                if !pending.isEmpty {
                    todoGroup("待完成", items: pending, tint: .teal)
                }
                if !finished.isEmpty {
                    todoGroup("已完成 \(finished.count)", items: finished, tint: .secondary.opacity(0.5))
                }
                if store.todayTodos.isEmpty && store.overdueTodos.isEmpty {
                    emptyHint
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.friendlyDay)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            if !store.todayTodos.isEmpty {
                Text("完成 \(finished.count) / \(store.todayTodos.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.teal)
                .imageScale(.large)
            TextField("添加一条今日待办…", text: $draft)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit {
                    store.addTodo(draft)
                    draft = ""
                    inputFocused = true
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
    }

    private func todoGroup(_ title: String, items: [TodoItem], tint: some ShapeStyle, showMoveToToday: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 2) {
                ForEach(items) { item in
                    TodoRow(item: item, tint: AnyShapeStyle(tint), showMoveToToday: showMoveToToday)
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max")
                .font(.system(size: 36))
                .foregroundStyle(.teal.opacity(0.6))
            Text("今天还没有待办，加一条开始吧")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - 单行

struct TodoRow: View {
    @Environment(Store.self) private var store
    let item: TodoItem
    var tint: AnyShapeStyle
    var showMoveToToday = false
    var showDate = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { store.toggleTodo(item) }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? AnyShapeStyle(.teal) : tint)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)

            Text(item.text)
                .strikethrough(item.done, color: .secondary)
                .foregroundStyle(item.done ? .secondary : .primary)

            Spacer()

            if showDate {
                Text(item.createdAt.friendlyDay)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if hovering {
                if showMoveToToday {
                    Button {
                        withAnimation { store.moveToToday(item) }
                    } label: {
                        Image(systemName: "arrow.uturn.down.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("挪到今天")
                }
                Button {
                    withAnimation { store.deleteTodo(item) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear))
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - 历史

struct HistoryView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("历史待办")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                if store.historyByDay.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("过往的待办会按天归档在这里")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }

                ForEach(store.historyByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(group.day.friendlyDay)
                                .font(.headline)
                            Text("\(group.items.filter(\.done).count)/\(group.items.count) 完成")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                        VStack(spacing: 2) {
                            ForEach(group.items) { item in
                                TodoRow(item: item, tint: AnyShapeStyle(.secondary))
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
