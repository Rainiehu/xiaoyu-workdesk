import SwiftUI
import WorkdeskCore
import WorkdeskUI

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
/// 字号与所在列同步：外面罩什么字号，正文和撤销钮就是什么字号 —— 与 `TodoText` 同一条规矩。
struct DeletedTodoRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    /// 撤销钮的颜色，随所在那一屏的 tint —— 死者的占位也穿这一屏的衣裳。
    let tint: Color

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            Text("已删除「\(todo.text)」")
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button { withAnimation { store.undeleteTodo(todo.id) } } label: {
                Image(systemName: "arrow.uturn.backward")
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
    /// 这次改写是从哪一下点击进来的（窗口坐标）。有它，光标就落在点到的那个字上；
    /// 没有（右键改写、Tab 挪位续编、新生的空行），光标落到末尾。
    var caretPoint: NSPoint?

    /// 拿现在的正文当草稿，人于是接着改，而不是从空白重打一遍。
    mutating func begin(_ todo: TodoItem, at point: NSPoint? = nil) {
        draft = todo.text
        caretPoint = point
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
    @Environment(TreeComposer.self) private var composer
    let todo: TodoItem
    @Binding var editing: TodoEditing
    /// 改写中按下 Tab / Shift+Tab 时做什么 —— 缩进（挂到上一个兄弟下面）与升一级。
    /// 挪成了返回 `true`；挪不动返回 `false`（没有上一个兄弟、已在顶层，
    /// 以及 `Store` 拒绝的那些：成环、目标已删、跨分类），那时这一行原地不动、
    /// 改写照旧开着 —— 键还是吃掉，不放它去走焦点，手不该在改写中间被甩走。
    /// 只在兄弟看得见的地方接（分类视图左列、树里）：轴上挂到一个看不见的邻居名下，
    /// 那一行就凭空消失了，所以那两处不传，Tab 留给系统走焦点。
    var onIndent: (() -> Bool)?
    var onOutdent: (() -> Bool)?
    /// 改写中回车收下这次改写之后再做什么 —— 「再开一行同级」挂在这儿。
    /// 与 Tab 同一条边界：只在同级顺序看得见的地方接，不传就是回车只收改写。
    var onReturn: (() -> Void)?

    @FocusState private var focused: Bool
    /// 这一场改写里光标摆过了没。摆一次就收手 —— 之后的选区变化都是人自己的
    /// （拖选、Cmd+A），不能再去动。每次输入框出现时归零。
    @State private var caretPlaced = false

    var body: some View {
        if editing.active {
            TextField("", text: $editing.draft)
                .textFieldStyle(.plain)
                .focused($focused)
                // 回车收下这次改写，写了字就接着「再开一行」；空着回车就是写完了，
                // 只收改写不开新行 —— 与「空行悄悄收走」是同一句话的两半。
                .onSubmit {
                    let wrote = !editing.draft
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    commit()
                    if wrote { onReturn?() }
                }
                // Esc 放弃这次改写，原文一字不动；生下来就空的行没有原文，悄悄收走。
                .onExitCommand {
                    editing.end()
                    if todo.text.isEmpty { store.discardEmptyTodo(todo.id) }
                }
                // 点到别处去了也算改完 —— 一次改写没有「没保存」这个下场。
                .onChange(of: focused) { _, focused in if !focused { commit() } }
                // 焦点慢一拍再落：回车生出新行时，这个输入框出现的同一拍里，
                // 上一行的输入框才刚交还第一响应者 —— 同拍去抢会被那次交还冲掉，
                // 光标就得等人再点一下。让一拍，稳稳落下。
                .onAppear {
                    caretPlaced = false
                    Task { @MainActor in
                        await Task.yield()
                        focused = true
                        await placeCaretFallback()
                    }
                }
                // 光标复位的正路：成为第一响应者那一下，AppKit 默认全选，选区变化的通知
                // 同步发出来 —— 在通知里当场换成光标落点，全选就一帧都上不了屏。
                // 认准「全选」这个签名再动手：场编辑器刚装上字时会有别的选区变化，
                // 接早了，之后真正的全选就又盖回来了。
                .onReceive(NotificationCenter.default.publisher(
                    for: NSTextView.didChangeSelectionNotification
                )) { note in
                    guard !caretPlaced,
                          let editor = note.object as? NSTextView,
                          editor.window?.firstResponder === editor,
                          editor.string == editing.draft else { return }
                    let all = NSRange(location: 0, length: (editor.string as NSString).length)
                    guard all.length > 0, editor.selectedRange() == all else { return }
                    caretPlaced = true
                    editor.setSelectedRange(NSRange(location: caretIndex(in: editor), length: 0))
                }
                // Tab 缩进、Shift+Tab 升一级：先把改到一半的字收下（挪位置不丢字），
                // 再挪。光标的接力见 `TreeComposer.resumeEditingID`。
                // Shift+Tab 在 AppKit 里送来的不是带 shift 的 tab，是 backtab（0x19）——
                // 按键名匹配接不住它，所以这儿接全部按键自己认。
                //
                // 删光了字再按一下删除，删的就是这条待办。「改成空白不算改」照旧 ——
                // 空着回车或点走，原文留着；但空行上的再一击是明确的删除表态，
                // 走软删除、开撤销窗口，与行上的删除钮同一条路。
                // 生下来就空的行例外：它没有内容可反悔，悄悄收走、不留占位。
                .onKeyPress(phases: .down) { press in
                    // 拼音正在组字（有 marked text）时，什么键都不抢：那一击删的是
                    // 组字里的字母、Tab 选的是候选 —— 都是输入法的事，不是这条待办的。
                    // 组字中草稿还空着，不让开的话，删拼音就被认成了删整条待办。
                    if let fieldEditor = NSApp.keyWindow?.firstResponder as? NSTextView,
                       fieldEditor.hasMarkedText() {
                        return .ignored
                    }
                    // 删除键与 backtab 一样按名字认不齐 —— 送进来的是 DEL（0x7F）
                    // 或 BS（0x08）字符，按键名与字符两头都认。
                    let backspace = press.key == .delete
                        || press.characters == "\u{7F}" || press.characters == "\u{8}"
                    if backspace, editing.draft.isEmpty {
                        editing.end()
                        // 收走这一行之后，光标退回上一行的末尾接着改 —— 键盘流里
                        // 删行不该把手甩在半空。只在回车开得出新行的地方接
                        // （与 onReturn 同一条边界）：轴上和右列的兄弟顺序不由人排，
                        // 「上一行」在那儿说不清是谁，退回去也就无从谈起。
                        let previous = onReturn != nil ? store.todoBefore(todo.id) : nil
                        if todo.text.isEmpty {
                            store.discardEmptyTodo(todo.id)
                        } else {
                            withAnimation { store.deleteTodo(todo) }
                        }
                        if let previous { composer.resumeEditingID = previous }
                        return .handled
                    }
                    let backtab = press.characters == "\u{19}"
                    guard press.key == .tab || backtab else { return .ignored }
                    let move = (backtab || press.modifiers.contains(.shift)) ? onOutdent : onIndent
                    guard let move else { return .ignored }
                    // 挪位置不丢字：改到一半的字先落盘。但这儿不走 `commit` ——
                    // 它会把一个字没写的新行当空行收走，要挪的那一行于是先没了，
                    // 人眼里就是「新记一行、还没打字，一按 Tab 待办凭空消失」。
                    // Tab 是给这一行换个位置，不是写完了走人。
                    // 空白照旧不写进正文，由 `editTodo` 挡着。
                    store.editTodo(todo, to: editing.draft)
                    // 挪成了，这个输入框随即被重建，光标由 `TreeComposer.resumeEditingID`
                    // 接到新位置上；挪不动就留在原地接着改 —— 挪不成的那一下
                    // 不该顺手结束一场改写，更不该留下一行空白没人管。
                    if move() { editing.end() }
                    return .handled
                }
        } else {
            Text(todo.text)
                .multilineTextAlignment(.leading)
        }
    }

    /// 光标该落在哪。点进来是要接着改，不是要重打一遍 —— 落在点到的那个字上；
    /// 点在字后面的空处、或没有点击位置（右键改写、Tab 续编），落到末尾。
    private func caretIndex(in editor: NSTextView) -> Int {
        if let point = editing.caretPoint {
            return editor.characterIndexForInsertion(at: editor.convert(point, from: nil))
        }
        return (editor.string as NSString).length
    }

    /// 光标复位的后路：万一那次全选没走选区变化的通知（或早于第一响应者换手，
    /// 通知里认不出来），这儿慢几拍把它扶正。正路已经摆过就不动。
    /// 等不到（点走了、行没了）就算了，全选也只是回到旧样子。
    private func placeCaretFallback() async {
        for _ in 0..<40 {
            await Task.yield()
            if caretPlaced { return }
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                  editor.string == editing.draft else { continue }
            caretPlaced = true
            editor.setSelectedRange(NSRange(location: caretIndex(in: editor), length: 0))
            return
        }
    }

    /// 收下这次改写。空白正文由 `Store` 挡掉，那时原文留着 —— 删除是另一条路；
    /// 生下来就空、又一个字没写的行是例外：悄悄收走，见 `discardEmptyTodo`。
    ///
    /// 「改完了」才走这儿。挪位置（Tab/Shift+Tab）不走 —— 换个地方待着不是写完了，
    /// 那条路只落字、不收行，见 `onKeyPress`。
    private func commit() {
        guard editing.active else { return }
        editing.end()
        if todo.text.isEmpty,
           editing.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.discardEmptyTodo(todo.id)
            return
        }
        store.editTodo(todo, to: editing.draft)
    }
}

// 「移到分类」菜单（`TodoMoveMenu`）在共享层，两端逐字同款、只此一份。

extension TodoText {
    /// 树编辑三下键（Tab 缩进、Shift+Tab 升一级、回车再开一行）都接上的那副，
    /// 挪完、生完把光标接力交给 `TreeComposer`。分类视图左列与子树两处同一份 ——
    /// 行的共性收在这儿，不各抄一遍。轴上不用这副：兄弟看不见的地方，
    /// Tab 留给系统走焦点，见 `onIndent` 的注释。
    init(todo: TodoItem, editing: Binding<TodoEditing>, tree store: Store, composer: TreeComposer) {
        self.init(
            todo: todo, editing: editing,
            onIndent: {
                let moved = store.indentTodo(todo.id)
                if moved { composer.resumeEditingID = todo.id }
                return moved
            },
            onOutdent: {
                let moved = store.promoteTodo(todo.id)
                if moved { composer.resumeEditingID = todo.id }
                return moved
            },
            onReturn: {
                if let newID = store.addTodo("", after: todo.id) {
                    composer.resumeEditingID = newID
                }
            }
        )
    }
}

/// 接上光标的接力：`TreeComposer.resumeEditingID` 说好要续上改写的那一行，
/// 出现时（Tab/Shift+Tab 挪完刚上屏，`onAppear`）或变化时（删行退光标，
/// 行早就在屏上，`onAppear` 不会再响）就地开编。
///
/// 发接力的只有树编辑那几下（分类视图左列、树里），但**四处的行都接**：
/// Shift+Tab 升一级会把行送去别的屏（树 → 未排期列、树 → 轴），
/// 光标得跟着行走，不看它落在哪一屏。少接一处，一条还没写字就升上去的行
/// 就会被撂在那儿 —— 不在改写态，也没人收走它。
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
            // 当场在孩子们末尾生一行空的，光标就位 —— 先有行、后有字。
            if let newID = store.addSubTodo("", under: todo.id) {
                composer.resumeEditingID = newID
            }
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
            // 顺手记下这一下点在窗口的哪儿：光标要落在点到的那个字上，不是全选。
            if !editing.wrappedValue.active {
                editing.wrappedValue.begin(todo, at: NSApp.currentEvent?.locationInWindow)
            }
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
