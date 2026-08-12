#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 子待办的树在 iPhone 上的呈现。概念与 Mac 全同（见 CONTEXT.md 与 Mac 的
/// `SubTodoTree.swift`）：父行上的进度记号就是展开入口，三处都能就地展开、默认收起，
/// 展开状态随偏好落盘、两端共用 `Store` 的同一份 API；树尾一行「＋ 添一步」接住连写流；
/// 子行有打勾、删除、改写、拖拽四样，排期入口与「移到分类」那两格空着 —— 无此事。
///
/// 这一版 iOS 刻意欠着两件事，都记在账上：
/// - **入怀与升降级**：iOS 的拖拽是「悬到哪当场换到哪」的活重排，没有「落在身上」这一态；
///   长按菜单的总开关也关着（与拖拽的长按识别打架，等磨玻璃自绘那一轮）。
///   兄弟之间拖着换位置照样行（`reorderTodo` 只认同一窝），跨层挪动先回 Mac。
/// - **第一步的出生口**：树一旦有了步骤，展开就有「添一步」；还没有步骤的行上
///   眼下没有入口 —— 挂在哪儿（长按菜单？右滑？）是个要单独拍板的呈现决定。

/// 父行上那个安静的进度，同时是展开/收起的入口：「3/5 ›」。与 Mac 同一副，
/// 点一下轻震一记 —— 触屏上「点着了」得让手知道。
struct TodoTreeBadge: View {
    @Environment(Store.self) private var store
    let todo: TodoItem

    var body: some View {
        if let progress = store.childProgress(of: todo.id) {
            let expanded = store.isExpanded(todo.id)
            Button {
                Buzz.light.impactOccurred()
                withAnimation(.easeOut(duration: 0.18)) { store.toggleExpanded(todo.id) }
            } label: {
                HStack(spacing: 3) {
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(.quaternary.opacity(0.45)))
                // 手指要的可点范围比胶囊大一圈。
                .padding(.vertical, 3)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "收起步骤" : "展开步骤")
        }
    }
}

/// 一条待办名下展开的子树：子行一层层铺，每层缩进一档，末尾一行淡淡的追加入口。
struct SubTodoTree: View {
    @Environment(Store.self) private var store
    let parentID: TodoItem.ID
    /// 子行打勾后圈填的颜色，随所在那一屏 —— 与顶层行同一条纪律，树不另立规矩。
    let tint: Color

    /// 每层缩进这么多。比 Mac 收一点 —— 手机一行本来就窄，任意嵌套的树
    /// 缩得太阔，几层下去正文就没地方站了。
    static let indent: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.children(of: parentID)) { child in
                if child.isDeleted {
                    DeletedTodoRow(todo: child)
                } else {
                    SubTodoRow(todo: child, tint: tint)
                    if store.isExpanded(child.id) {
                        SubTodoTree(parentID: child.id, tint: tint)
                    }
                }
            }
            SubTodoAppendRow(parentID: parentID, tint: tint)
        }
        .padding(.leading, Self.indent)
    }
}

/// 子待办的一行：圈 → 正文 → 进度记号 → Spacer。排期入口与分类 tag 那两格空着 ——
/// 步骤没有自己的计划日和分类，不是禁用，是无此事。
/// 单击改写、左滑亮删、拖着在兄弟间换位置，与三处的行同一套本事。
private struct SubTodoRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let tint: Color

    @State private var editing = TodoEditing()

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, tint: tint) {
                store.toggleTodo(todo)
            }

            TodoText(todo: todo, editing: $editing)
                .foregroundStyle(todo.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

            TodoTreeBadge(todo: todo)

            Spacer(minLength: 8)
        }
        .todoRowChrome()
        .contentShape(Rectangle())
        .todoRowActions(todo, editing: $editing)
        .todoDragSource(todo)
        // 兄弟之间的活重排：悬到哪当场换到哪，列表本身就是预览 —— 与主列同一副手感。
        // 悬过来的不是同窝兄弟时 `reorderTodo` 拒绝，什么也不动。
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
        .swipeToDelete { withAnimation { store.deleteTodo(todo) } }
    }
}

/// 树尾那行淡淡的追加入口：平时是「＋ 添一步」，点了当场变成输入框。
/// 回车记下这一步、原位再开一行 —— 连写流；写了一半收场也照样记下。
private struct SubTodoAppendRow: View {
    @Environment(Store.self) private var store
    let parentID: TodoItem.ID
    let tint: Color

    @State private var composing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if composing {
            HStack(spacing: TodoRowLayout.spacing) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
                    .padding(6)
                TextField("下一步…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .submitLabel(.next)
                    .onChange(of: focused) { _, now in if !now { blur() } }
                    .onAppear { focused = true }
            }
            .todoRowChrome()
        } else {
            Button {
                Buzz.light.impactOccurred()
                composing = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("添一步")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, TodoRowLayout.horizontalInset)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 回车：记下这一步，清空草稿、焦点留住 —— 下一步接着写。空白回车就是写完了，收场。
    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            close()
            return
        }
        store.addSubTodo(text, under: parentID)
        draft = ""
        focused = true
    }

    /// 点到别处去了：写了一半的字照样记下，然后收场 —— 记事没有「没保存」这个下场。
    private func blur() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { store.addSubTodo(text, under: parentID) }
        close()
    }

    private func close() {
        draft = ""
        composing = false
    }
}
#endif
