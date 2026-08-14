import SwiftUI
import UniformTypeIdentifiers
import WorkdeskCore

/// 子待办的树在 Mac 上的全部家当：常开的子树，和「落间换位、落身入怀」的落点判定。
///
/// 树**常开**：子树就摊在父行底下，三处（分类视图两列、轴、未排期列）一个样 ——
/// 没有折叠、没有进度记号（步骤都在眼前，数字是重复），也没有任何虚拟输入行：
/// 回车「再开一行」与右键「添加子待办」都当场生一条**真的**空待办，光标就位 ——
/// 先有行、后有字；没写字就走的空行被悄悄收走（`Store.discardEmptyTodo`）。
/// 子行有打勾、删除、改写、拖拽四样，与普通行一致；排期入口和「移到分类」在子行上
/// **不存在** —— 不是禁用置灰，是那一格空着，沿用「三处的行同一副结构，差别只在
/// 哪几格是空的」。

/// 树上跨行的那一点会话态：等着接过光标的那一行。不落盘。
///
/// 两处用它接力：Tab/Shift+Tab 挪动或回车新生都会让 SwiftUI 重建（新建）行视图，
/// 改写状态接不过去 —— 把 id 记在这儿，那一行一露面就进入改写、光标就位。
@Observable
@MainActor
final class TreeComposer {
    var resumeEditingID: TodoItem.ID?
}

// MARK: - 常开的子树

/// 一条待办名下的子树：子行一层层铺，每层缩进一档。常开 —— 没有折叠这回事。
/// 没有孩子就整个不占地方。
/// 删除态的子行是原位占位，与三处的行同一条规矩（ADR-0007）。
struct SubTodoTree: View {
    @Environment(Store.self) private var store
    let parentID: TodoItem.ID
    /// 子行打勾后圈填的颜色，随所在那一屏：分类视图与未排期列是分类色，轴上是青 ——
    /// 与顶层行同一条纪律，树不另立规矩。
    let tint: Color

    /// 每层缩进这么多：恰好一个勾圈加行内距 —— 子行的圈落在父行正文的起笔处，
    /// 步骤读起来就长在那句话底下。
    static let indent: CGFloat = TodoRowLayout.spacing + 16

    var body: some View {
        let children = store.children(of: parentID)
        if !children.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(children) { child in
                    if child.isDeleted {
                        DeletedTodoRow(todo: child)
                    } else {
                        SubTodoRow(todo: child, tint: tint)
                        SubTodoTree(parentID: child.id, tint: tint)
                    }
                }
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
                onReturn: {
                    if let newID = store.addTodo("", after: todo.id) {
                        composer.resumeEditingID = newID
                    }
                }
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
