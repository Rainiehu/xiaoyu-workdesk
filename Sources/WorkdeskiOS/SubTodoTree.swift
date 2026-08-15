#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 子待办的树在 iPhone 上的呈现。概念与 Mac 全同（见 CONTEXT.md 与 Mac 的
/// `SubTodoTree.swift`）：树**常开**，子树就摊在父行底下，四处（分类屏、轴、
/// 未排期面板、已完成面板）一个样 —— 没有折叠、没有进度记号、没有常驻的追加入口。
/// 子行有打勾、删除、改写、拖拽四样，排期入口与「移到分类」那两格空着 —— 无此事。
///
/// **回车「再开一行」**与 Mac 同款、同一条边界：改写中写了字回车，当场生一条真的
/// 同级空行、光标就位；空着回车就是写完；没写字就走的空行悄悄收走
/// （`Store.discardEmptyTodo`）。
///
/// 这一版 iOS 仍欠着三件，都记在账上（CONTEXT-iOS.md）：**入怀、升降级、添步骤** ——
/// 拖拽是「悬到哪当场换到哪」的活重排，没有「落在身上」这一态；行上按 y 分三段
/// （缝换位、身入怀）照 Mac 那套试过一轮，手感不对，退了回来。长按菜单总开关也关着
/// （与拖拽的长按识别打架，等磨玻璃自绘那一轮），Mac 上「添加子待办」走的右键在
/// 这儿没有对应物。兄弟之间拖着换位置照样行（`reorderTodo` 只认同一窝）。

/// 树上跨行的那一点会话态：等着接过光标的那一行。不落盘。
///
/// 回车新生会让 SwiftUI 新建行视图，改写状态接不过去 —— 把 id 记在这儿，
/// 那一行一露面就进入改写、光标就位。与 Mac 的同名类同一副。
@Observable
@MainActor
final class TreeComposer {
    var resumeEditingID: TodoItem.ID?
}

/// 接上光标的接力：`TreeComposer.resumeEditingID` 说好要续上改写的那一行，
/// 出现时（回车新生刚上屏，`onAppear`）就地开编。两处列表同一份。
///
/// `onChange` 那一路眼下走不到 —— iOS 只有回车会写这根接力棒，写的必是刚生的新行。
/// 留着是防 SwiftUI 把现成的行视图挪去认领新 id（那时 `onAppear` 不再响），
/// 也让这一副与 Mac 的同名件保持逐字同形。
private struct ResumesTreeEditing: ViewModifier {
    @Environment(TreeComposer.self) private var composer
    let todo: TodoItem
    @Binding var editing: TodoEditing

    func body(content: Content) -> some View {
        content
            .onAppear {
                if composer.resumeEditingID == todo.id {
                    composer.resumeEditingID = nil
                    editing.begin(todo)
                }
            }
            .onChange(of: composer.resumeEditingID) { _, id in
                if id == todo.id {
                    composer.resumeEditingID = nil
                    editing.begin(todo)
                }
            }
    }
}

extension View {
    func resumesTreeEditing(_ todo: TodoItem, editing: Binding<TodoEditing>) -> some View {
        modifier(ResumesTreeEditing(todo: todo, editing: editing))
    }
}

/// 一条待办名下的子树：子行一层层铺，每层缩进一档。没有孩子就整个不占地方。
struct SubTodoTree: View {
    @Environment(Store.self) private var store
    let parentID: TodoItem.ID
    /// 子行打勾后圈填的颜色，随所在那一屏 —— 与顶层行同一条纪律，树不另立规矩。
    let tint: Color

    /// 每层缩进这么多。比 Mac 收一点 —— 手机一行本来就窄，任意嵌套的树
    /// 缩得太阔，几层下去正文就没地方站了。
    static let indent: CGFloat = 24

    var body: some View {
        let children = store.children(of: parentID)
        if !children.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(children) { child in
                    if child.isDeleted {
                        DeletedTodoRow(todo: child, tint: tint)
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

/// 子待办的一行：圈 → 正文 → Spacer。排期入口与分类 tag 那两格空着 ——
/// 步骤没有自己的计划日和分类，不是禁用，是无此事。
/// 单击改写、左滑亮删、拖着在兄弟间换位置，与四处的行同一套本事；
/// 另有改写中的回车「再开一行」—— 顶层行只在分类屏接，子树的行四处都接
/// （树是同一份，顺序又都由人手排，新行落在哪儿不含糊）。
private struct SubTodoRow: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let todo: TodoItem
    let tint: Color

    @State private var editing = TodoEditing()

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, tint: tint) {
                store.toggleTodo(todo)
            }

            TodoText(todo: todo, editing: $editing, tree: store, composer: composer)
                .foregroundStyle(todo.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

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
        // 光标的接力（回车新生）收在 `resumesTreeEditing` 一处。
        .resumesTreeEditing(todo, editing: $editing)
        .swipeToDelete { withAnimation { store.deleteTodo(todo) } }
    }
}
#endif
