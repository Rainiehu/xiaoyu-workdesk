import SwiftUI
import UniformTypeIdentifiers
import WorkdeskCore

/// 子待办的树在 Mac 上的全部家当：常开的子树、回车/右键开出的临时输入行、
/// 以及「落间换位、落身入怀」的落点判定。
///
/// 树**常开**：子树就摊在父行底下，三处（分类视图两列、轴、未排期列）一个样 ——
/// 没有折叠、没有进度记号（步骤都在眼前，数字是重复），也没有常驻的追加入口
/// （加步骤走右键「添加子待办」，点了才浮出一行输入）。
/// 子行有打勾、删除、改写、拖拽四样，与普通行一致；排期入口和「移到分类」在子行上
/// **不存在** —— 不是禁用置灰，是那一格空着，沿用「三处的行同一副结构，差别只在
/// 哪几格是空的」。

/// 树上跨行的那点会话态。都是「这一屏此刻」的事，不落盘 ——
/// 与展开状态（那是习惯，随偏好落盘）不同。
@Observable
@MainActor
final class TreeComposer {
    /// 哪个父的追加输入正开着。一次只开一处 —— 步骤是一串一串写的，不是几棵树同时长。
    var composingUnder: TodoItem.ID?
    /// Tab/Shift+Tab 把一行挪了位置，SwiftUI 会重建那一行的视图，改写状态就断了。
    /// 挪完把 id 记在这儿，新长出来的那一行一露面就接着改 ——
    /// 「光标不离开文字」的手感靠这一棒接力。
    var resumeEditingID: TodoItem.ID?
    /// 改写中回车「再开一行」：输入行开在哪一行（和它展开的子树）底下。
    /// 记下一条就顺着挪到新行底下，连写不断。一次只开一处，与追加输入同一个道理。
    var insertingAfter: TodoItem.ID?
}

// MARK: - 常开的子树

/// 一条待办名下的子树：子行一层层铺，每层缩进一档。常开 —— 没有折叠这回事。
/// 没有孩子、也没在添步骤时，整个不占地方。
/// 删除态的子行是原位占位，与三处的行同一条规矩（ADR-0007）。
struct SubTodoTree: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let parentID: TodoItem.ID
    /// 子行打勾后圈填的颜色，随所在那一屏：分类视图与未排期列是分类色，轴上是青 ——
    /// 与顶层行同一条纪律，树不另立规矩。
    let tint: Color

    /// 每层缩进这么多：恰好一个勾圈加行内距 —— 子行的圈落在父行正文的起笔处，
    /// 步骤读起来就长在那句话底下。
    static let indent: CGFloat = TodoRowLayout.spacing + 16

    var body: some View {
        let children = store.children(of: parentID)
        if !children.isEmpty || composer.composingUnder == parentID {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(children) { child in
                    if child.isDeleted {
                        DeletedTodoRow(todo: child)
                    } else {
                        SubTodoRow(todo: child, tint: tint)
                        SubTodoTree(parentID: child.id, tint: tint)
                        SiblingInsertRow(anchor: child)
                    }
                }
                SubTodoAppendRow(parentID: parentID)
            }
            .padding(.leading, Self.indent)
        }
    }
}

/// 子待办的一行：圈 → 正文 → 进度记号 → Spacer → 删除。
/// 排期入口与「移到分类」这两格是空的 —— 步骤没有自己的计划日和分类，不是禁用，是无此事。
/// 打勾、删除、改写、拖拽与普通行一致；改写中 Tab 缩进、Shift+Tab 升一级。
private struct SubTodoRow: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let todo: TodoItem
    let tint: Color
    @State private var hovering = false
    @State private var editing = TodoEditing()

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, tint: tint) { store.toggleTodo(todo) }

            TodoText(
                todo: todo, editing: $editing,
                onIndent: { if store.indentTodo(todo.id) { composer.resumeEditingID = todo.id } },
                onOutdent: { if store.promoteTodo(todo.id) { composer.resumeEditingID = todo.id } },
                onReturn: { composer.insertingAfter = todo.id }
            )
            .foregroundStyle(todo.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

            Spacer(minLength: 8)

            // 改写时不浮出删除：手正放在字上，旁边不该还摆着一个删得掉整条的按钮。
            if hovering && !editing.active {
                TodoDeleteButton { withAnimation { store.deleteTodo(todo) } }
            }
        }
        .todoRowChrome(hovering: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .todoRowEditing(todo, editing: $editing)
        .draggable(DraggedTodo(id: todo.id)) { TodoDragPreview(text: todo.text, tint: tint) }
        .todoTreeDropTarget(todo, allowsGaps: true)
        .onAppear {
            // Tab/Shift+Tab 挪完位置的那一行在这儿续上改写 —— 见 `TreeComposer.resumeEditingID`。
            if composer.resumeEditingID == todo.id {
                composer.resumeEditingID = nil
                editing.begin(todo)
            }
        }
    }
}

/// 右键「添加子待办」开出的那行输入，落在孩子们的末尾。平时什么也不画 ——
/// 树上没有常驻的追加入口，入口在菜单里。
/// 回车记下这一步、原位再开一行 —— 「先这个、再这个、然后那个」的连写流靠它接住；
/// Esc 或点到别处收场，写了一半的字照样记下（记事没有「没保存」这个下场）。
private struct SubTodoAppendRow: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let parentID: TodoItem.ID
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var composing: Bool { composer.composingUnder == parentID }

    var body: some View {
        if composing {
            HStack(spacing: TodoRowLayout.spacing) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                TextField("下一步…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { close() }
                    .onChange(of: focused) { _, now in if !now { blur() } }
                    .onAppear { focused = true }
            }
            .padding(.horizontal, TodoRowLayout.horizontalInset)
            .padding(.vertical, TodoRowLayout.verticalInset)
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

    /// 点到别处去了：写了一半的字照样记下，然后收场。
    private func blur() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { store.addSubTodo(text, under: parentID) }
        close()
    }

    private func close() {
        draft = ""
        if composing { composer.composingUnder = nil }
    }
}

/// 改写中回车开出的那行输入：开在刚才那一行（和它展开的子树）底下，记的是**同级**的下一条。
/// 回车记下、输入行顺着挪到新行底下接着写 —— 与顶上的记事栏各管一头：
/// 记事栏记「最要紧的新事」（落顶上），这儿记「顺着写下去」（落在手边）。
/// Esc 收场；点到别处写了一半的字照样记下 —— 记事没有「没保存」这个下场。
/// 平时什么也不画：它只在 `TreeComposer.insertingAfter` 指着自己的锚点时露面。
struct SiblingInsertRow: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let anchor: TodoItem
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var open: Bool { composer.insertingAfter == anchor.id }

    var body: some View {
        if open {
            HStack(spacing: TodoRowLayout.spacing) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                TextField("接着记…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { close() }
                    .onChange(of: focused) { _, now in if !now { blur() } }
                    .onAppear { focused = true }
            }
            .padding(.horizontal, TodoRowLayout.horizontalInset)
            .padding(.vertical, TodoRowLayout.verticalInset)
        }
    }

    /// 回车：记在锚点后面，输入行挪到新行底下连写。空白回车就是写完了，收场。
    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            close()
            return
        }
        guard let newID = store.addTodo(text, after: anchor.id) else {
            close()
            return
        }
        draft = ""
        composer.insertingAfter = newID
    }

    private func blur() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { _ = store.addTodo(text, after: anchor.id) }
        close()
    }

    /// 只收自己名下的这一行 —— 连写把输入挪去新行底下之后，旧实例的失焦不该
    /// 反手把新开的那行关掉。
    private func close() {
        draft = ""
        if open { composer.insertingAfter = nil }
    }
}

// MARK: - 落点：落间换位、落身入怀

/// 一次拖拽此刻悬在一行的哪一段。
enum TodoDropZone {
    /// 上缝：放到这一行前头当兄弟。
    case before
    /// 身上：钻进这一行肚子里当末子。
    case into
    /// 下缝：放到这一行后头当兄弟。
    case after
}

extension View {
    /// 给一行待办装上「落间换位、落身入怀」的落点：缝亮一条线，身亮一圈 ——
    /// 预渲染高亮先把「松手会发生什么」说清楚。
    ///
    /// - Parameters:
    ///   - allowsGaps: 缝接不接。手排的地方（分类视图左列、未排期列、树里）接；
    ///     轴上和右列不接 —— 那两处的顺序不由人排，行上只剩「入怀」一件事。
    ///   - gap: 缝里那一落怎么处理。不传就是挪位置（`placeTodo`）。
    func todoTreeDropTarget(
        _ todo: TodoItem, allowsGaps: Bool,
        gap: ((TodoItem.ID, TodoDropZone) -> Bool)? = nil
    ) -> some View {
        modifier(TodoTreeDropTarget(todo: todo, allowsGaps: allowsGaps, gap: gap))
    }
}

private struct TodoTreeDropTarget: ViewModifier {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let allowsGaps: Bool
    let gap: ((TodoItem.ID, TodoDropZone) -> Bool)?

    @State private var zone: TodoDropZone?
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .overlay { indicator }
            .onDrop(
                of: [.workdeskTodo],
                delegate: TodoRowDropDelegate(
                    zone: $zone, height: height, allowsGaps: allowsGaps, perform: land
                )
            )
            .animation(.easeOut(duration: 0.12), value: zone == nil)
    }

    /// 落下时真正做的事。挪不动（挂进自己肚子里、目标已删）就是 `false`，拖拽弹回去。
    private func land(_ dropped: TodoItem.ID, in zone: TodoDropZone) -> Bool {
        guard dropped != todo.id else { return false }
        switch zone {
        case .into:
            return store.nestTodo(dropped, under: todo.id)
        case .before:
            return gap?(dropped, .before) ?? store.placeTodo(dropped, before: todo.id)
        case .after:
            return gap?(dropped, .after) ?? store.placeTodo(dropped, after: todo.id)
        }
    }

    /// 预渲染高亮：身上是一圈青描边（与 tab 栏、轴上分组的落点同一句话），
    /// 缝是上/下边缘一条青线 —— 两态一眼分得开，松手前就知道会发生什么。
    @ViewBuilder
    private var indicator: some View {
        switch zone {
        case .into:
            RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius)
                .strokeBorder(.teal.opacity(0.7), lineWidth: 2)
        case .before:
            gapLine.frame(maxHeight: .infinity, alignment: .top)
        case .after:
            gapLine.frame(maxHeight: .infinity, alignment: .bottom)
        case nil:
            EmptyView()
        }
    }

    private var gapLine: some View {
        Capsule()
            .fill(.teal.opacity(0.8))
            .frame(height: 2.5)
            .padding(.horizontal, 2)
    }
}

/// 行上落点的判定：按悬停的纵向位置分上缝、身上、下缝。
/// 用 `DropDelegate` 而不是 `dropDestination` —— 只有它一路报着位置，
/// 预渲染高亮才能跟着手走。
private struct TodoRowDropDelegate: DropDelegate {
    @Binding var zone: TodoDropZone?
    let height: CGFloat
    let allowsGaps: Bool
    let perform: (TodoItem.ID, TodoDropZone) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.workdeskTodo])
    }

    func dropEntered(info: DropInfo) {
        zone = zone(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        zone = zone(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        zone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let landed = zone(at: info.location)
        zone = nil
        guard let provider = info.itemProviders(for: [.workdeskTodo]).first else { return false }
        _ = provider.loadDataRepresentation(for: .workdeskTodo) { data, _ in
            guard let data,
                  let dragged = try? JSONDecoder().decode(DraggedTodo.self, from: data) else { return }
            Task { @MainActor in
                _ = perform(dragged.id, landed)
            }
        }
        return true
    }

    /// 缝窄身宽：上下各三成是缝，中间四成多是身 —— 「入怀」是行上的主菜，
    /// 缝只要伸得进指尖就够。不接缝的行整行都是身。
    private func zone(at location: CGPoint) -> TodoDropZone {
        guard allowsGaps, height > 0 else { return .into }
        let y = location.y / height
        if y < 0.3 { return .before }
        if y > 0.7 { return .after }
        return .into
    }
}
