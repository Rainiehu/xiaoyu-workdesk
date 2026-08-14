#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 子待办的树在 iPhone 上的呈现。概念与 Mac 全同（见 CONTEXT.md 与 Mac 的
/// `SubTodoTree.swift`）：树**常开**，子树就摊在父行底下，四处（分类屏、轴、
/// 未排期面板、已完成面板）一个样 —— 没有折叠、没有进度记号、没有常驻的追加入口。
/// 子行有打勾、删除、改写、拖拽四样，排期入口与「移到分类」那两格空着 —— 无此事。
///
/// 这一版 iOS 刻意欠着，都记在账上（CONTEXT-iOS.md）：**入怀、升降级、添步骤** ——
/// 拖拽是「悬到哪当场换到哪」的活重排，没有「落在身上」这一态；长按菜单总开关
/// 也关着（与拖拽的长按识别打架，等磨玻璃自绘那一轮），Mac 上「添加子待办」
/// 走的右键在这儿没有对应物。兄弟之间拖着换位置照样行（`reorderTodo` 只认同一窝）。

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

/// 子待办的一行：圈 → 正文 → Spacer。排期入口与分类 tag 那两格空着 ——
/// 步骤没有自己的计划日和分类，不是禁用，是无此事。
/// 单击改写、左滑亮删、拖着在兄弟间换位置，与四处的行同一套本事。
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
#endif
