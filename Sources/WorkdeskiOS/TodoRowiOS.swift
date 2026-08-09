#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 三处待办行共用的那几样东西，iOS 版。结构与 Mac 完全同一副：
///
///     圈 → 正文 → Spacer → 日期/排期入口 → 分类 tag
///
/// 差别只在「哪几格是空的」，与 Mac 同一条规矩；悬停没有了，替换成触屏的总规矩
/// （见 CONTEXT-iOS.md）：左滑＝删除，排期入口常驻，单击正文＝就地改写，长按菜单 ≙ 右键菜单。
enum TodoRowLayout {
    static let spacing: CGFloat = 10
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 8
    static let cornerRadius: CGFloat = 8
}

/// 一条待办的完成状态圈。空心圈是还没做，实心勾圈是做完了，点一下就翻面。
/// 过期只换描边成琥珀 —— 安静的记号，不是警报。画哪个状态由调用方给，
/// 与 Mac 同一条理由：未排期面板里打完勾要先亮一拍。
struct TodoToggle: View {
    let done: Bool
    var overdue: Bool = false
    let tint: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(circleStyle)
                // 圈本身 18pt，手指要的可点范围比这大 —— 内缩摊进按钮里。
                .padding(6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var circleStyle: AnyShapeStyle {
        if done { return AnyShapeStyle(tint) }
        return overdue ? AnyShapeStyle(Color.overdueAmber) : AnyShapeStyle(.tertiary)
    }
}

/// 待办所属分类的 tag，与 Mac 的 `CategoryTag` 同两副样子：
/// 带胶囊的用在未排期面板的组头上；光板的用在轴上每一行 —— 一屏几十行，
/// 每行挂一个彩色胶囊就成了噪点，而那儿该抢眼的是「今天」。
struct CategoryTag: View {
    let category: Category
    var chip: Bool = true

    var body: some View {
        if chip {
            Text(category.name)
                .font(.caption)
                .foregroundStyle(category.color.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(category.color.tint.chipFill))
                .overlay(Capsule().stroke(category.color.tint.chipStroke, lineWidth: 1))
        } else {
            Text(category.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// 一行待办的内缩。三处都从这儿走，改一处三处一起动。
    func todoRowChrome() -> some View {
        padding(.horizontal, TodoRowLayout.horizontalInset)
            .padding(.vertical, TodoRowLayout.verticalInset)
    }
}

/// 拖起来时手上跟着的那一小块：就是这条待办的正文。与 Mac 同一副 ——
/// 整行连着底色一起拖会盖住下面的落点，只带一句字轻便得多。
struct TodoDragPreview: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius).fill(tint.opacity(0.15))
            )
    }
}

extension View {
    /// 落点指示：青色描边。「松手会落在这儿」在轴上、tab 条上、主列行上是同一句话，
    /// 与 Mac 同一个颜色、同一个说法。
    func dropTargetStroke(_ targeted: Bool, cornerRadius: CGFloat = TodoRowLayout.cornerRadius) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.teal.opacity(targeted ? 0.7 : 0), lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

/// 一行待办正在改写时的那点状态。与 Mac 同一副：草稿先装上原文，同一下才翻成改写中。
struct TodoEditing {
    private(set) var active = false
    var draft = ""

    mutating func begin(_ todo: TodoItem) {
        draft = todo.text
        active = true
    }

    mutating func end() {
        active = false
    }
}

/// 一行待办的正文。平时是一行字，改写时就地变成输入框 —— 改写发生在原位，不弹窗、不跳转。
/// 三处共用。点到别处去（失焦）也算改完 —— 一次改写没有「没保存」这个下场。
struct TodoText: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    @Binding var editing: TodoEditing

    @FocusState private var focused: Bool

    var body: some View {
        if editing.active {
            TextField("", text: $editing.draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(commit)
                .submitLabel(.done)
                .onChange(of: focused) { _, focused in if !focused { commit() } }
                .onAppear { focused = true }
        } else {
            Text(todo.text)
                .multilineTextAlignment(.leading)
        }
    }

    /// 收下这次改写。空白正文由 `Store` 挡掉，那时原文留着 —— 删除是另一条路。
    private func commit() {
        guard editing.active else { return }
        editing.end()
        store.editTodo(todo, to: editing.draft)
    }
}

/// 「移到分类」：列出别的分类，选一个这条待办就归到那儿去。与 Mac 同一副。
struct TodoMoveMenu: View {
    @Environment(Store.self) private var store
    let todo: TodoItem

    var body: some View {
        let others = store.categories(besides: todo.categoryID)
        if others.isEmpty {
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

extension View {
    /// 行上的编辑入口：单击整行进就地改写，长按菜单是「改写 / 移到分类 / 删除」——
    /// 对应 Mac 的右键菜单（删除在菜单里也有一份，左滑是它的快捷路径）。
    /// 三处一模一样 —— 一行待办能做什么，不看它在哪一列，见 ADR-0003。
    func todoRowActions(
        _ todo: TodoItem, editing: Binding<TodoEditing>, delete: @escaping () -> Void
    ) -> some View {
        contextMenu {
            Button("改写") { editing.wrappedValue.begin(todo) }
            TodoMoveMenu(todo: todo)
            Divider()
            Button("删除", role: .destructive, action: delete)
        }
        .onTapGesture {
            if !editing.wrappedValue.active { editing.wrappedValue.begin(todo) }
        }
    }
}

/// 左滑删除。往左一划，身后露出琥珀灰的垃圾桶；划过门槛松手就是删 ——
/// 与 Mac 的悬停垃圾桶同一个分寸：不弹确认（删除本就郑重，没有撤销），
/// 但静止时一点痕迹也不留。没过门槛就弹回去，什么也不发生。
struct SwipeToDelete: ViewModifier {
    let delete: () -> Void
    @State private var offset: CGFloat = 0
    @GestureState private var dragging = false

    /// 划过这个距离松手就是删。
    private let threshold: CGFloat = 90

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < -4 {
                    RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius)
                        .fill(past ? Color.red : Color.red.opacity(0.35))
                        .overlay(alignment: .trailing) {
                            Image(systemName: "trash")
                                .foregroundStyle(.white)
                                .padding(.trailing, 22)
                        }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 25)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        // 只认往左划；往右不是这儿的手势。
                        guard value.translation.width < 0,
                              abs(value.translation.width) > abs(value.translation.height) else { return }
                        offset = max(value.translation.width, -threshold * 1.4)
                    }
                    .onEnded { value in
                        if offset < -threshold {
                            withAnimation(.easeOut(duration: 0.15)) { offset = -600 }
                            delete()
                        } else {
                            withAnimation(.spring(duration: 0.25)) { offset = 0 }
                        }
                    }
            )
            .animation(.easeOut(duration: 0.1), value: past)
    }

    private var past: Bool { offset < -threshold }
}

extension View {
    func swipeToDelete(_ delete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(delete: delete))
    }
}
#endif
