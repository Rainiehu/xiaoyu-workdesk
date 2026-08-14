import SwiftUI
import WorkdeskCore

/// 三处待办行共用的那几样东西：度量、打勾的圈、悬停浮出的删除、拖起来时手上跟着的那一小块。
///
/// 分类视图、沙漏视图的轴、未排期列，三处的行是同一副结构：
///
///     圈 → 正文 → Spacer → 日期/排期入口 → 删除 → 分类 tag
///
/// 差别只在「哪几格是空的」：分类视图不画 tag（在哪个分类里是不言自明的），未排期列的 tag
/// 在组头上，轴上的排期入口只有图标、不带日期标签（那天写在组头上）。顺序与度量都定在这儿，
/// 三处照着来 —— 先前没有这么一处共同的定义，三行才各自漂移成了三副模样。
///
/// 行上能做的事也一样：打勾、删除、排期、就地改写、移到分类，在哪一列都是同一套，
/// 也不看完没完成，见 ADR-0003。悬停浮出的东西因此四处相同：底色、排期入口、删除。
/// 改写那点状态与「移到分类」那个菜单因此也收在这儿 —— 三份抄写迟早会漂成三副脾气。

/// 一行待办的度量。三处共用，改一处三处一起动。
enum TodoRowLayout {
    /// 行内元素之间的距离。
    static let spacing: CGFloat = 10
    static let horizontalInset: CGFloat = 10
    /// 竖直内缩。比横向留得多一点 —— 行里最高的是那个 16pt 的圈，它得有呼吸。
    static let verticalInset: CGFloat = 8
    static let cornerRadius: CGFloat = 8
}

/// 一条待办的完成状态：空心圈是还没做，实心勾圈是做完了，点一下就翻面。
///
/// 已完成的圈填成这条待办所属分类的颜色 —— 打勾于是把这一行「点亮」成它的分类色。
/// 未完成的是灰圈：那时颜色还没什么好说的，而一行上只该有一处彩色抢眼。
/// 唯一的例外是过期（未完成且计划日已过，见 ADR-0004）：描边换成琥珀 ——
/// 过期是完成状态的一层，所以记号长在说完成状态的这个圈上，打勾那一下顺手把它抹掉。
///
/// 画哪个状态由调用方给，不自己去问 `todo.done` —— 未排期列里打完勾的那条要先亮一下再走，
/// 那一拍里圈画的是「已完成」，而待办本身还没变。
struct TodoToggle: View {
    let done: Bool
    /// 过期了。只换没打勾时描边的颜色，别的一概不动 —— 这是个安静的记号，不是警报。
    /// 未排期列不传：那儿的待办没有计划日，谈不上过没过。
    var overdue: Bool = false
    /// 打勾之后填的颜色，就是这条待办所属分类的颜色。
    let tint: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(circleStyle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(done ? "取消完成" : "标记完成")
    }

    private var circleStyle: AnyShapeStyle {
        if done { return AnyShapeStyle(tint) }
        return overdue ? AnyShapeStyle(Color.overdueAmber) : AnyShapeStyle(.tertiary)
    }
}

extension Color {
    /// 过期记号的琥珀。刻意不取分类色板里的 amber —— 那是某个分类的记号，这是一层状态，
    /// 撞了色就分不清「这行属于琥珀色的分类」和「这行过期了」，所以压灰压暗一档，弱提醒不抢戏。
    /// 浅色外观深一档、深色外观浅一档，与分类色板同一条纪律。
    static let overdueAmber = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(rgb: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? OverdueAmber.dark : OverdueAmber.light)
    })
}

/// 悬停时浮出的删除。三处摆在同一个位置上：行尾那个常驻元素的左边 ——
/// 轴上它靠着分类 tag，另外两处它自己就是最右。
/// 删完那一行原地变成占位（`DeletedTodoRow`），几秒内点撤销就回来。
struct TodoDeleteButton: View {
    let delete: () -> Void

    var body: some View {
        Button(action: delete) {
            Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("删除")
    }
}

/// 原位占位：刚删掉的待办留在它原来的位置上，撤销窗口开着的那几秒里可以点回来 ——
/// 占位跟着死者的原位走，一行待办活在几处（轴、分类视图、未排期列），占位就在几处，
/// 见 ADR-0007。窗口一关它自己塌掉（`Store` 把记录搬进池子，行就不在列表里了）。
///
/// 字号与所在列同步：外面罩什么字号，正文和「撤销」就是什么字号 —— 与 `TodoText` 同一条规矩。
struct DeletedTodoRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            Text("已删除「\(todo.text)」")
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("撤销") { withAnimation { store.undeleteTodo(todo.id) } }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(.teal)
                .help("撤销删除")
        }
        .padding(.horizontal, TodoRowLayout.horizontalInset)
        .padding(.vertical, TodoRowLayout.verticalInset)
        .background(
            RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius)
                .fill(.quaternary.opacity(0.35))
        )
    }
}

/// 拖起来时手上跟着的那一小块：就是这条待办的正文。
/// 整行连着悬停底色一起拖会盖住下面的落点，只带一句字轻便得多。
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

/// 一行待办正在改写时的那点状态：改不改、改成什么。
///
/// 两样东西绑在一起，是因为「开始改写」必须一步完成：草稿先装上原文，同一下才翻成改写中 ——
/// 分两步走的话输入框会先空着闪一帧。
struct TodoEditing {
    private(set) var active = false
    var draft = ""

    /// 拿现在的正文当草稿，人于是接着改，而不是从空白重打一遍。
    mutating func begin(_ todo: TodoItem) {
        draft = todo.text
        active = true
    }

    mutating func end() {
        active = false
    }
}

/// 一行待办的正文。平时是一行字，改写时就地变成输入框 —— 改写发生在原位，不弹窗、不跳转。
///
/// 三处共用。字号不在这儿定：宽列用 body、窄列用 callout，由所在那一列外面罩上去，
/// `Text` 和 `TextField` 因此一起跟着变，两种模样的字不会差一号。
struct TodoText: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    @Binding var editing: TodoEditing
    /// 改写中按下 Tab / Shift+Tab 时做什么 —— 缩进（挂到上一个兄弟下面）与升一级。
    /// 只在兄弟看得见的地方接（分类视图左列、树里）：轴上挂到一个看不见的邻居名下，
    /// 那一行就凭空消失了，所以那两处不传，Tab 留给系统走焦点。
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?
    /// 改写中回车收下这次改写之后再做什么 —— 「再开一行同级」挂在这儿。
    /// 与 Tab 同一条边界：只在同级顺序看得见的地方接，不传就是回车只收改写。
    var onReturn: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        if editing.active {
            TextField("", text: $editing.draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    commit()
                    onReturn?()
                }
                // Esc 放弃这次改写，原文一字不动。
                .onExitCommand { editing.end() }
                // 点到别处去了也算改完 —— 一次改写没有「没保存」这个下场。
                .onChange(of: focused) { _, focused in if !focused { commit() } }
                .onAppear { focused = true }
                // Tab 缩进、Shift+Tab 升一级：先把改到一半的字收下（挪位置不丢字），
                // 再挪。光标的接力见 `TreeComposer.resumeEditingID`。
                // Shift+Tab 在 AppKit 里送来的不是带 shift 的 tab，是 backtab（0x19）——
                // 按键名匹配接不住它，所以这儿接全部按键自己认。
                .onKeyPress(phases: .down) { press in
                    let backtab = press.characters == "\u{19}"
                    guard press.key == .tab || backtab else { return .ignored }
                    let move = (backtab || press.modifiers.contains(.shift)) ? onOutdent : onIndent
                    guard let move else { return .ignored }
                    commit()
                    move()
                    return .handled
                }
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

/// 「移到分类」：列出别的分类，选一个这条待办就归到那儿去。
/// 移走只改归属 —— 计划日、创建日、完成日与完成状态都不变，这条由 `Store` 保证。
/// 它同时是腾空一个分类的那条路：非空分类删不掉，没有它就永远删不掉。
struct TodoMoveMenu: View {
    @Environment(Store.self) private var store
    let todo: TodoItem

    var body: some View {
        let others = store.categories(besides: todo.categoryID)
        if others.isEmpty {
            // 只有这一个分类时无处可移。菜单项照样在，只是灰着 —— 免得右键之后空空如也。
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

/// 右键菜单里的那几项。做成独立的 View 才拿得到环境里的 `Store` 与 `TreeComposer` ——
/// 菜单项按行的身份自己增减：顶层行有「移到分类」，子行换成「升一级」（子行的分类跟着根走，
/// 没有「移到分类」这回事）；「添加子待办」谁都有 —— 任何一行都拆得出步骤。
struct TodoRowMenuItems: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let todo: TodoItem
    @Binding var editing: TodoEditing

    var body: some View {
        Button("改写") { editing.begin(todo) }
        Button("添加子待办") {
            // 树常开，点了当场在孩子们末尾浮出一行输入，接着写。
            composer.composingUnder = todo.id
        }
        if todo.parentID != nil {
            Button("升一级") { withAnimation { _ = store.promoteTodo(todo.id) } }
        } else {
            TodoMoveMenu(todo: todo)
        }
    }
}

extension View {
    /// 行上那两个编辑入口：单击整行进就地改写，右键是菜单（改写、添加子待办、
    /// 移到分类/升一级）。三处一模一样 —— 一行待办能做什么，不看它在哪一列，见 ADR-0003。
    ///
    /// 单击接的是整行，不只是正文那几个字：行里的圈、日期、删除都是按钮，各自先接住自己的那一下，
    /// 不会落到这儿来。所以要摆在 `contentShape` 之后、`draggable` 之前，与整行抓得动那件事排好先后。
    func todoRowEditing(_ todo: TodoItem, editing: Binding<TodoEditing>) -> some View {
        contextMenu {
            TodoRowMenuItems(todo: todo, editing: editing)
        }
        .onTapGesture {
            if !editing.wrappedValue.active { editing.wrappedValue.begin(todo) }
        }
    }

    /// 一行待办的内缩与悬停底色。三处都要那块底色 —— 行上摆着打勾和删除、整行还抓得动，
    /// 手落在哪一行必须当场看得见。
    func todoRowChrome(hovering: Bool) -> some View {
        padding(.horizontal, TodoRowLayout.horizontalInset)
            .padding(.vertical, TodoRowLayout.verticalInset)
            .background(
                RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius)
                    .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.35)) : AnyShapeStyle(.clear))
            )
    }
}
