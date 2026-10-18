import SwiftUI
import WorkdeskCore

/// 一个分类里的待办，左右分列：左边待完成，右边已完成，同屏可见、互不干扰。
/// 左列突出、右列整体淡化 —— 注意力自然落在还没做的事情上，做完的事退成可查的背景。
///
/// 两列的顺序都由 `Store.columns(in:)` 定，这里一行排序也不做。左列的顺序是使用者自己拖出来的
/// （拖一行放到另一行上），已排期与未排期混在一列里，靠日期标签的有无自然区分，见 ADR-0002。
///
/// 时间在这个视图里刻意弱化：日期只是行尾一个低对比度的次要标签，不构成组织结构 ——
/// 在分类里关心的是「有哪些事」，不是「排在哪天」。
struct CategoryTodoList: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let category: Category

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    /// 右列的宽度。定死一个值而不是按比例分 —— 左列于是随窗口一起长，
    /// 「哪边是主角」不随窗口宽度动摇。引用同一个常量而不是各写一遍 264：
    /// 两处的右列看着是同一块东西，就该真是同一个数。
    private let finishedColumnWidth = UnscheduledColumn.width

    /// 左列的内容宽度上限。窗口再宽，一行字也不跟着摊开。
    private let unfinishedColumnMaxWidth: CGFloat = 620

    /// 右列顶上要让出的那一段，就是输入框那一条的高度 —— 从它那儿取，两列的第一行因此齐平。
    private let inputHeight = TodoInputField<EmptyView>.height

    /// 两列共同的上留白。
    private let topInset: CGFloat = 28

    /// 左列行下那片「加小标题」空白的高度，由下面两个量算出：铺满可视区里行没占的那段，
    /// 行多到滚起来时也至少留这么一截，滚到底总还点得着。
    @State private var unfinishedViewportHeight: CGFloat = 0
    @State private var unfinishedRowsHeight: CGFloat = 0
    private let newSectionAreaMinHeight: CGFloat = 80

    var body: some View {
        let columns = store.columns(in: category.id)

        HStack(alignment: .top, spacing: 0) {
            unfinishedColumn(columns.unfinished, blank: columns.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // 一件事都没有的时候不分列：那时没有「已完成」可谈，整个界面就是一段引导。
            if !columns.isEmpty {
                Divider()
                finishedColumn(columns.finished)
                    .frame(width: finishedColumnWidth)
            }
        }
    }

    /// 左列：记事的入口留在顶上，下面是还没完成的事。
    private func unfinishedColumn(_ todos: [TodoItem], blank: Bool) -> some View {
        VStack(spacing: 0) {
            // 输入框在 ScrollView 外面：待办再多也留在顶上，记事随时都在手边。
            input
                .padding(.horizontal, 28)
                .padding(.top, topInset)
                .frame(maxWidth: unfinishedColumnMaxWidth)

            if blank {
                empty
            } else {
                list(todos, addsSectionsBelow: true)
                    .frame(maxWidth: unfinishedColumnMaxWidth, alignment: .leading)
                    .overlay { if todos.isEmpty { hint("都做完了") } }
            }
        }
    }

    /// 左列最后一行下面那片空白：右键「加小标题」，在末尾开一节新的。
    /// 只铺在行的下面 —— 菜单若挂在整个列表上，行与行之间的缝、小标题上方那段留白也会接住右键，
    /// 点在中间却在末尾生出一个小标题，人眼里就是「什么也没发生」。
    /// 想把已有的几条分出一节，走行上的「在上方加小标题」。
    private var newSectionArea: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: max(newSectionAreaMinHeight, unfinishedViewportHeight - unfinishedRowsHeight))
            .contentShape(Rectangle())
            .contextMenu {
                Button("加小标题") {
                    if let newID = store.addHeading(in: category.id) {
                        composer.resumeEditingID = newID
                    }
                }
            }
    }

    /// 右列：已经完成的事，按完成日从新到旧。整列淡化、字号小一号，
    /// 但仍然读得清楚 —— 完成的事情是可查的记录，不是被划掉的废稿。
    private func finishedColumn(_ todos: [TodoItem]) -> some View {
        list(todos)
            .font(.callout)
            // 顶上让出输入框那一条，右列的第一行于是与左列的第一行齐平。
            .padding(.top, topInset + inputHeight)
            .opacity(0.62)
            .overlay { if todos.isEmpty { hint("打勾的事落到这边") } }
    }

    /// - Parameter addsSectionsBelow: 行下面铺一片接「加小标题」的空白。只有左列给 ——
    ///   小标题只站在左列的手排顺序里，见 ADR-0009。
    private func list(_ todos: [TodoItem], addsSectionsBelow: Bool = false) -> some View {
        ScrollView {
            // 行与下面那片空白摞成一列；间距归零，空白紧贴着最后一行的下留白起头。
            VStack(spacing: 0) {
                LazyVStack(spacing: 2) {
                    ForEach(todos) { todo in
                        // 删除态的行是原位占位：撤销窗口开着的那几秒它还站在这儿，见 ADR-0007。
                        if todo.isDeleted {
                            DeletedTodoRow(todo: todo, tint: category.color.tint)
                        } else if todo.isHeading {
                            // 小标题只会出现在左列：右列的那份 `Store` 就没给。
                            HeadingRow(heading: todo, tint: category.color.tint)
                        } else {
                            TodoRow(todo: todo, tint: category.color.tint)
                            // 子树常开，就摊在行底下。右列也一样 —— 完成的事带着它的步骤
                            // 一起退到背景里。
                            SubTodoTree(parentID: todo.id, tint: category.color.tint)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if addsSectionsBelow { unfinishedRowsHeight = height }
                }

                if addsSectionsBelow { newSectionArea }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if addsSectionsBelow { unfinishedViewportHeight = height }
        }
    }

    private var input: some View {
        TodoInputField(
            tint: category.color.tint,
            prompt: "记一件事，回车记下…",
            text: $draft,
            focused: $inputFocused,
            submit: record
        ) {
            // 分类视图里记到哪个分类是不问自明的 —— 眼下这个分类就是了。
            EmptyView()
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 34))
                .foregroundStyle(category.color.tint.opacity(0.5))
            Text("「\(category.name)」还是空的")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// 一列空着时的一句话。轻到几乎不占分量 —— 它说明这列是干什么的，不催人做事。
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    /// 记下草稿里的那件事。空白输入交给 `Store` 挡掉，这里只管清空并留住焦点，好让记事可以一条接一条。
    private func record() {
        store.addTodo(draft, in: category.id)
        draft = ""
        inputFocused = true
    }
}

/// 一行待办：左边的圆圈打勾/取消，悬停时右边浮出排期入口与删除，单击整行就地改写，
/// 右键是同样这两件事的菜单入口。已完成的不带删除线 —— 完成的事情读起来该仍然清晰体面。
/// 淡化交给所在那一列，行本身不管。
///
/// 整行抓得动，落在哪儿就是哪件事：落在左列另一行上是换位置，落在 tab 栏某个分类上是改归属。
/// 这些本事轴上和未排期列的行也都有，见 ADR-0003；只有「换位置」是这一列独有的，
/// 因为位置只在一个分类里可比。
private struct TodoRow: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock
    @Environment(TreeComposer.self) private var composer
    let todo: TodoItem
    let tint: Color
    @State private var hovering = false

    /// 正在就地改写这一行。改写时整行变成一个输入框，别的按钮让开 ——
    /// 手正放在字上，旁边不该还浮着一个删除。
    @State private var editing = TodoEditing()

    /// 左列的行才排得动 —— 右列的顺序是完成日，不由人排，见 ADR-0002。
    /// 落缝（换位置）与 Tab 缩进（挂到上一个兄弟名下）都只在排得动的列里成立。
    private var reorderable: Bool { !todo.done }

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, overdue: todo.isOverdue(today: clock.today), tint: tint) {
                store.toggleTodo(todo)
            }

            // 左列接树编辑的三下键；右列不由人排，三下都不接，回车只收改写。
            if reorderable {
                TodoText(todo: todo, editing: $editing, tree: store, composer: composer)
            } else {
                TodoText(todo: todo, editing: $editing)
            }

            Spacer(minLength: 8)

            // 完成了的行上，常驻的日期是完成日，而且只是个标签 —— 它说明右列为什么这么排。
            // 排期入口照样有，只是不再画计划日标签：一行上一个日期就够了，而这一格的职责是解释排序。
            // 有完成日就等于完成了，这条由 `Store` 保证，所以这儿只问一次。
            if let completedAt = todo.completedAt {
                Text(completedAt.dayLabel(relativeTo: clock.today))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PlannedDayControl(todo: todo, rowHovering: hovering, showsDate: false)
            } else {
                PlannedDayControl(todo: todo, rowHovering: hovering)
            }

            // 改写时不浮出删除：手正放在字上，旁边不该还摆着一个删得掉整条的按钮。
            if hovering && !editing.active {
                TodoDeleteButton { withAnimation { store.deleteTodo(todo) } }
            }
        }
        .todoRowChrome(hovering: hovering)
        .onHover { hovering = $0 }
        // 整行都抓得动，内缩一并算进拖拽范围里，免得只有正文那几个字抓得住。
        // 已完成的也抓得动 —— 它排不了序，但照样可以拖到 tab 栏上换分类。
        .contentShape(Rectangle())
        .todoRowEditing(todo, editing: $editing, addsHeadingAbove: reorderable)
        .draggable(DraggedTodo(id: todo.id)) { TodoDragPreview(text: todo.text, tint: tint) }
        // 落间换位、落身入怀：缝亮线、身亮圈。右列不接缝 —— 那儿的顺序不由人排，
        // 行上只剩「入怀」一件事。
        .todoTreeDropTarget(todo, allowsGaps: reorderable, tint: tint)
        // 光标的接力（Tab/Shift+Tab 挪完、删行退回）收在 `resumesTreeEditing` 一处。
        .resumesTreeEditing(todo, editing: $editing)
    }

}

/// 一个小标题：分类色胶囊，与未排期列的组头同一副 —— 胶囊在 app 里本就意味着「一组的开头」。
/// 它下面、到下一个小标题之前的顶层待办就是这一节；节没有容器，只是手排顺序里的一道分界，
/// 见 ADR-0009。
///
/// 胶囊不额外内缩，左缘与下面每一行悬停时那块底色对齐，一节读起来是一块 —— 与组头同一条理由。
/// 行上能做的只有三样：单击改名、悬停浮出删除、整行拖走（整节跟着走）。没有勾圈、排期入口、
/// 「移到分类」与「添加子待办」——那几格不是禁用，是小标题无此事。
private struct HeadingRow: View {
    @Environment(Store.self) private var store
    @Environment(TreeComposer.self) private var composer
    let heading: TodoItem
    let tint: Color
    @State private var hovering = false
    @State private var editing = TodoEditing()

    /// 胶囊上方多留的那一段：节与节之间靠它喘口气，比行距宽，又不至于把一节切成两块。
    private let sectionGap: CGFloat = 12

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            // 改名接的是待办那一套键：回车收下改名并在这一节顶上开一行新待办，
            // 空着按删除就是删掉这个小标题（Tab 在这儿挪不动，什么也不发生）。
            TodoText(todo: heading, editing: $editing, tree: store, composer: composer)
                .font(.caption.weight(.semibold))
                // 改名时胶囊随字伸缩，不铺满整行 —— 留一点底宽，空着时也看得出是个胶囊。
                .fixedSize(horizontal: editing.active, vertical: false)
                .frame(minWidth: editing.active ? 48 : nil, alignment: .leading)
                .categoryChip(tint)

            Spacer(minLength: 8)

            if hovering && !editing.active {
                TodoDeleteButton { withAnimation { store.deleteTodo(heading) } }
                    .padding(.trailing, TodoRowLayout.horizontalInset)
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .contextMenu {
            Button("改写") { editing.begin(heading) }
        }
        .onTapGesture {
            if !editing.active {
                editing.begin(heading, at: NSApp.currentEvent?.locationInWindow)
            }
        }
        .draggable(DraggedTodo(id: heading.id)) {
            Text(heading.text).font(.caption.weight(.semibold)).categoryChip(tint)
        }
        // 落点与待办行同一副：缝换位、身上 —— 待办落上来成了这一节的第一条，
        // 小标题落上来整节换到这儿（`Store.nestTodo` 分得清）。
        .todoTreeDropTarget(heading, allowsGaps: true, tint: tint)
        .resumesTreeEditing(heading, editing: $editing)
        // 间隔放在落点外面：落点指示框住的是胶囊这一行，不连着上头那段空白。
        .padding(.top, sectionGap)
    }
}
