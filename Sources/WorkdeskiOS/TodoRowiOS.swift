#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
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

/// 屏缘与面板缘的边距。tab 条、两屏主列、输入栏全从这儿取 —— 一处改，四处动；
/// 面板窄，取屏缘的七折。行内缩、分组内衬仍归 `TodoRowLayout`，层级不混。
enum ScreenLayout {
    static let screenEdge: CGFloat = 20
    static let panelEdge: CGFloat = 14
}

/// 一条待办的完成状态圈。空心圈是还没做，实心勾圈是做完了，点一下就翻面。
/// 过期只换描边成琥珀 —— 安静的记号，不是警报。画哪个状态由调用方给，
/// 与 Mac 同一条理由：未排期面板里打完勾要先亮一拍。
struct TodoToggle: View {
    let done: Bool
    var overdue: Bool = false
    let tint: Color
    let toggle: () -> Void

    /// 这回打勾放的那朵烟花的号。换一个号动画从头放；也是成功震动的扳机。
    @State private var burst = 0
    @State private var bursting = false
    /// 取消完成的次数 —— 轻震的扳机：手上有个确认，但不庆祝。
    @State private var unchecked = 0
    /// 勾已经点下、账还没落 —— 这一拍里圈先画成完成态，烟花放完行才离场。
    /// 没有这一拍，分类屏上行会在打勾瞬间搬去已完成，烟花跟着行一起消失。
    @State private var pending = false

    var body: some View {
        Button(action: fire) {
            Image(systemName: done || pending ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(circleStyle)
                // 圈本身 18pt，手指要的可点范围比这大 —— 内缩摊进按钮里。
                .padding(6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .overlay {
            if bursting {
                CompletionBurst(tint: tint)
                    .id(burst)
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: burst)
        .sensoryFeedback(.impact(weight: .light), trigger: unchecked)
    }

    /// 打勾放烟花、来一记成功震；取消完成只轻震一下 —— 手上有确认，但不庆祝。
    private func fire() {
        guard !pending else { return }
        guard !done else {
            unchecked += 1
            toggle()
            return
        }
        pending = true
        burst += 1
        bursting = true
        Task {
            // 让烟花放到七成再落账（落账后行可能就搬走了）；尾巴再收一拍。
            try? await Task.sleep(for: .milliseconds(550))
            toggle()
            pending = false
            try? await Task.sleep(for: .milliseconds(450))
            bursting = false
        }
    }

    private var circleStyle: AnyShapeStyle {
        if done || pending { return AnyShapeStyle(tint) }
        return overdue ? AnyShapeStyle(Color.overdueAmber) : AnyShapeStyle(.tertiary)
    }
}

/// 打勾那一拍从勾圈里绽开的一圈小彩点：飞出去、缩小、隐去，半秒收场。
/// 颜色只用这一行的 tint 一族深浅 —— 在哪个分类打勾就绽哪家的颜色，
/// 与落点高亮同一条规矩。
private struct CompletionBurst: View {
    let tint: Color
    @State private var fired = false

    private let count = 16

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = (Double(i) + 0.5) / Double(count) * 2 * .pi
                let radius: CGFloat = i.isMultiple(of: 2) ? 46 : 32
                let size: CGFloat = i.isMultiple(of: 3) ? 7 : 5
                Circle()
                    .fill(dotColor(i))
                    .frame(width: size, height: size)
                    .offset(
                        x: cos(angle) * (fired ? radius : 9),
                        y: sin(angle) * (fired ? radius : 9)
                    )
                    .scaleEffect(fired ? 0.3 : 1)
                    .opacity(fired ? 0 : 1)
            }
        }
        .task {
            // 隔一拍再点火：与插入同一拍的动画会被并进插入渲染，直接落在终态上 ——
            // 那样一粒也看不见。
            await Task.yield()
            withAnimation(.easeOut(duration: 0.85)) { fired = true }
        }
    }

    private func dotColor(_ i: Int) -> Color {
        switch i % 4 {
        case 0: tint
        case 1: tint.opacity(0.75)
        case 2: tint.opacity(0.5)
        default: tint.opacity(0.3)
        }
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

/// app 内正拖着的那条待办。系统的 NSItemProvider 只是占位 —— 这些拖拽出不了
/// 这个 app（类型是自家的），id 犯不着序列化一个来回，放在这儿落点同步取用。
enum TodoDrag {
    static var current: TodoItem.ID?
}

/// 触感的那几记，共用一套常驻的发生器，打之前有预热 —— 现用现建的发生器
/// 引擎是冷的，第一记常被吞掉（松手的成功震偶尔失踪，根子就是它）。
enum Buzz {
    static let light = UIImpactFeedbackGenerator(style: .light)
    static let medium = UIImpactFeedbackGenerator(style: .medium)
    static let notify = UINotificationFeedbackGenerator()
    /// 切换 tab 那一嗒 —— 系统「选择变了」的触感，与拨选择器同一种。
    static let select = UISelectionFeedbackGenerator()

    static func warm() {
        light.prepare()
        notify.prepare()
    }
}

/// 一个落点的三件事：进来、走开、接住。提案一律 `.move` —— 拖一条待办是移动，
/// 不是增加，系统才不会在拖拽预览上挂一枚「复制」的绿加号。
///
/// 「拖到哪列表就当场变成哪样」靠 `entered`：悬进来的瞬间落点直接落账
/// （换位、改期），列表本身就是预览 —— 不再另画预渲染的空位。
private struct TodoDropDelegate: DropDelegate {
    var entered: (TodoItem.ID) -> Void = { _ in }
    var exited: () -> Void = {}
    let perform: (TodoItem.ID) -> Bool

    func validateDrop(info: DropInfo) -> Bool { TodoDrag.current != nil }
    func dropEntered(info: DropInfo) {
        if let id = TodoDrag.current { entered(id) }
    }
    func dropExited(info: DropInfo) { exited() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        exited()
        guard let id = TodoDrag.current else { return false }
        TodoDrag.current = nil
        return perform(id)
    }
}

extension View {
    /// 抓起一条待办。不走 `.draggable` 是为了让落点能把提案改成 `.move` ——
    /// 语义对了，系统也不会挂「复制」的绿加号。预览是一粒看不见的点：
    /// 列表实时换位就是预览，手上不用再浮一小块内容。
    /// 拎起那一刻直接打一记中震 —— 「抓住了」不用看也知道。
    func todoDragSource(_ todo: TodoItem) -> some View {
        // 拎起那一记震动欠着不打：系统拖拽框架里没有「抬起了」的可靠信号 ——
        // 取件闭包会被预取复用、首次 enter 晚七成秒、并行长按会踩坏拖拽识别，
        // 三条路都实测过不通。等自绘拖拽那一轮，抬起归自己管了再补。
        onDrag {
            TodoDrag.current = todo.id
            Buzz.warm()
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.workdeskTodo.identifier, visibility: .ownProcess
            ) { completion in
                completion(try? JSONEncoder().encode(DraggedTodo(id: todo.id)), nil)
                return nil
            }
            return provider
        } preview: {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    /// 接住一条待办。悬进来那一刻发生什么由 `entered` 定、落下收尾由 `perform` 定 ——
    /// 与 `DraggedTodo` 的约定一致：抓起的那一头不知道也不必知道。
    func todoDropTarget(
        entered: @escaping (TodoItem.ID) -> Void = { _ in },
        exited: @escaping () -> Void = {},
        perform: @escaping (TodoItem.ID) -> Bool
    ) -> some View {
        onDrop(
            of: [.workdeskTodo],
            delegate: TodoDropDelegate(entered: entered, exited: exited, perform: perform)
        )
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

/// 行上长按菜单的总开关。先关着：长按干干净净全归拖拽的抬起 ——
/// 菜单（只剩「移到分类」）等磨玻璃自绘那一轮回来，开关一拨即回，代码不删。
enum RowContextMenu {
    static let enabled = false
}

extension View {
    /// 行上的编辑入口：单击整行进就地改写；长按菜单只剩「移到分类」——
    /// 改写有单击、删除有左滑，各有各的路，菜单里不再重复一份。
    /// （菜单的磨玻璃自定义面板等自绘拖拽那一轮一起做 —— 系统菜单的皮改不动。）
    /// 三处一模一样 —— 一行待办能做什么，不看它在哪一列，见 ADR-0003。
    @ViewBuilder
    func todoRowActions(_ todo: TodoItem, editing: Binding<TodoEditing>) -> some View {
        if RowContextMenu.enabled {
            contextMenu {
                TodoMoveMenu(todo: todo)
            }
            .onTapGesture {
                if !editing.wrappedValue.active { editing.wrappedValue.begin(todo) }
            }
        } else {
            onTapGesture {
                if !editing.wrappedValue.active { editing.wrappedValue.begin(todo) }
            }
        }
    }
}

/// 原位占位：刚删掉的待办留在它原来的位置上，撤销窗口开着的那几秒里点撤销就回来 ——
/// 占位跟着死者的原位走，一行待办活在几处（轴、分类屏、未排期面板、已完成面板），
/// 占位就在几处，见 ADR-0007。窗口一关它自己塌掉（`Store` 把记录搬进池子）。
/// 字号与所在列同步：外面罩什么字号就是什么字号，与 `TodoText` 同一条规矩。
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
        }
        .todoRowChrome()
        .background(
            RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius)
                .fill(.quaternary.opacity(0.35))
        )
    }
}

/// 左滑亮出删除钮。往左一划，行让开一截、身后露出一枚红圆钮，停在那儿 ——
/// 点这枚钮才真正删（软删＋原位占位，几秒内可撤销，见 ADR-0007）；
/// 点行上别处或往回一划就合上，什么也不发生。
/// 划出去就删太容易失手 —— 删除要的是「亮出来、看清了、点下去」三拍。
struct SwipeToDelete: ViewModifier {
    let delete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var revealed = false

    /// 行让开这一截，正好摆下那枚钮。
    private let reveal: CGFloat = 64

    func body(content: Content) -> some View {
        content
            // 钮亮着时，行上随便点哪儿都是「合上」—— 不落进行内的编辑。
            .overlay {
                if revealed {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { settle(open: false) }
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < -4 { deleteButton }
            }
            .gesture(drag)
    }

    private var deleteButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { offset = -600 }
            delete()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.red))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, (reveal - 30) / 2)
        // 钮随行让开的宽度显影 —— 划到一半就是半张脸。
        .opacity(min(1, -offset / reveal))
        .accessibilityLabel("删除")
    }

    private var drag: some Gesture {
        // 位移在全局坐标系里量 —— 行自己跟着手指动，本地坐标系会自己追自己。
        DragGesture(minimumDistance: 25, coordinateSpace: .global)
            .onChanged { value in
                // 方向门只把第一下：横移胜过纵移才接手；接了手就一路跟随。
                guard offset != 0 || abs(value.translation.width) > abs(value.translation.height)
                else { return }
                let base: CGFloat = revealed ? -reveal : 0
                offset = min(0, max(base + value.translation.width, -reveal * 1.3))
            }
            .onEnded { _ in
                settle(open: offset < -reveal * 0.6)
            }
    }

    private func settle(open: Bool) {
        withAnimation(.spring(duration: 0.25)) {
            offset = open ? -reveal : 0
            revealed = open
        }
    }
}

extension View {
    func swipeToDelete(_ delete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(delete: delete))
    }
}
#endif
