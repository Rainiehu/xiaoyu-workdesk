import SwiftUI
import WorkdeskCore

/// 「移到分类」：列出别的分类，选一个这条待办就归到那儿去。
/// 移走只改归属 —— 计划日、创建日、完成日与完成状态都不变，这条由 `Store` 保证。
/// 它同时是腾空一个分类的那条路：非空分类删不掉，没有它就永远删不掉。
/// Mac 挂在右键菜单里、iOS 挂在长按菜单里 —— 菜单件本身两端逐字同款，只此一份。
public struct TodoMoveMenu: View {
    @Environment(Store.self) private var store
    let todo: TodoItem

    public init(todo: TodoItem) {
        self.todo = todo
    }

    public var body: some View {
        let others = store.categories(besides: todo.categoryID)
        if others.isEmpty {
            // 只有这一个分类时无处可移。菜单项照样在，只是灰着 —— 免得点开之后空空如也。
            Button("移到分类") {}
                .disabled(true)
        } else {
            Menu("移到分类") {
                ForEach(others) { category in
                    Button(category.name) { store.moveTodo(todo, to: category.id) }
                }
            }
        }
    }
}
