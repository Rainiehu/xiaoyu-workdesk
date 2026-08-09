import SwiftUI
import WorkdeskCore

/// 沙漏视图：横跨所有分类的一条连续时间轴。排了计划日的待办按计划日铺成这条轴，
/// 今天锚在中间、上方是过去、下方是未来，打开时就滚到今天。
///
/// 分组由 `Store.timeline(today:)` 给出，这里不自己聚合。
///
/// 右边另有一列未排期的事（`UnscheduledColumn`），与轴分开滚 —— 轴回答「排在哪天」，
/// 那一列回答「还有什么没安排」，从那儿拖一条到轴上某一天就排上了。
///
/// 顶上是记事输入区：这里是打开主线默认落地的地方，也是最常问「接下来要做什么」的地方，
/// 所以它必须能直接记录，不该逼使用者先切到某个分类。在这儿记下的待办自动排在今天，
/// 于是它立刻出现在眼前这条轴上，而不是凭空消失到某个分类里去。
/// 两边的行都能就地打勾、就地删除 —— 这是最常问「今天要做什么」的一屏，不该为了打个勾先切到某个分类去。
/// 改写正文与移到分类不在这儿，那两件事仍旧只在分类视图里。
/// 轴上的条目可以直接拖到别的日期分组里去改期：调整安排是一个手势，不必点开日期面板。
/// 拖拽只发生在这条轴的日期分组之间，也只改计划日 —— 归属哪个分类是横轴上的事，不因这一拖而变。
///
/// 计划日在过去而未完成的待办就是「过期」：留在它那一天，不置顶、不自动顺延、不催办，
/// 唯一的痕迹是那一行的勾圈描成琥珀 —— 安静的记号，不是警报。见 ADR-0004（修订了 ADR-0001）。
struct HourglassView: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    /// 今天那一组在轴内容里的纵向中点，和轴内容的总高，都是从布局里量出来的：
    /// 「按需垫高」要拿它们算出两头各差多少才够把今天顶到中线（见 `endInsets`）。
    @State private var todayCenterY: CGFloat?
    @State private var contentHeight: CGFloat?

    /// 中线上锚着哪一天。打开时指今天；用户一滚，`scrollPosition` 就把它改指中线上的那一天。
    @State private var anchorDay: Date?

    /// 量「今天在哪」用的坐标系：挂在轴内容的 VStack 上、垫高之内，
    /// 量出来的位置因此不含垫高 —— 垫高正是要拿这个位置去算的，不能让它反过来搅了测量。
    private static let contentSpace = "hourglassTimeline"

    /// 轴与输入区共同的内容宽度上限与内缩。写在一处，两者因此左右对齐 ——
    /// 输入框看着就是这条轴的开头，不是浮在它上面的另一块东西。
    private let contentWidth: CGFloat = 640
    private let contentInset: CGFloat = 28

    var body: some View {
        // 「今天」不在这儿问时钟，从 `TodayClock` 取 —— 整条主线共用那一个值：锚点、强调、
        // 日期写法、回车记在哪一天因此永远一致，跨过零点它自己会跟上，不必等谁来叫醒。
        let today = clock.today

        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                // 输入区在 ScrollView 外面：轴滚到哪儿它都在顶上，记事随时都在手边。
                if let category = store.recordingCategory {
                    input(category: category, today: today)
                        .padding(.horizontal, contentInset)
                        .padding(.top, contentInset)
                        .frame(maxWidth: contentWidth)
                        .frame(maxWidth: .infinity)
                }
                timeline(today: today)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 未排期的事单开一列，与轴分开滚：一边是「排在哪天」，一边是「还没安排」。
            Divider()
            UnscheduledColumn()
                .frame(maxHeight: .infinity)
        }
    }

    /// 只有排了期的日子在轴上，条数不多，所以用 VStack 而不是 LazyVStack ——
    /// 打开时要滚到今天，那一组必须已经在布局里。
    private func timeline(today: Date) -> some View {
        // 「今天锚在中线」要求今天两侧各有半屏内容可滚，不够的那一侧拿空白垫 ——
        // 但只垫差的那一截（`endInsets`）：过去往往早超过半屏，顶上就一点不垫，
        // 滚到头就是最早那一天，而不是半屏说不清的空白。真垫了余白的时候（今天自己
        // 就是轴的尽头），那段空白是有含义的：滚到底，中线上正锚着今天。
        GeometryReader { geo in
            let insets = endInsets(half: geo.size.height / 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.timeline(today: today)) { day in
                        DayGroup(day: day, today: today)
                            .id(day.day)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .named(Self.contentSpace)).midY
                            } action: { midY in
                                // 每一组都在量，但只记今天的 —— 哪一组是今天由数据说，
                                // 位置变了（上面添了行、隔了夜）这里自然跟着更新。
                                if day.day.isSameDay(as: today) { todayCenterY = midY }
                            }
                    }
                }
                .scrollTargetLayout()
                .coordinateSpace(name: Self.contentSpace)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                }
                .padding(.horizontal, contentInset)
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // 锚点是声明的不是滚出来的：打开时把今天顶到中线，之后垫高一收、内容挪位，
            // 系统自己维持锚定，不用抢在布局前后掐时机再滚一把。
            // 用户一滚，绑定就跟着改指中线上的那一天 —— 锚从此归手势管，不会又被拽回今天。
            .scrollPosition(id: $anchorDay, anchor: .center)
            // 不画滚动条：这条轴的位置感由「今天」的锚点给，不靠滚动条说；
            // 真垫了余白的日子，常驻的滚动条也只会是轴中间一根说不清的粗杠。
            .scrollIndicators(.hidden)
            .onAppear {
                // 落在中间而不是顶上：过去与未来因此同时露在眼前，两头都摆明了可以滚。
                anchorDay = today.dayStart
            }
            // 过了一天就重新锚回今天，跟刚打开一样 —— 这台窗口常常一开就是几天，
            // 隔夜回来时停在昨天那一屏，看到的就是一份对不上的安排。
            // `today` 只在日子变了时才动（见 `TodayClock`），所以这句不会被时刻的走动惊动。
            .onChange(of: today) { _, now in
                withAnimation(.easeInOut(duration: 0.3)) {
                    anchorDay = now.dayStart
                }
            }
        }
    }

    /// 轴两头按需垫的空白：今天哪一侧的内容不够半屏，就在那头垫上差的那一截，
    /// 够了的一侧一点不垫 —— `scrollTo(anchor: .center)` 只在目标两边都还有内容可滚时
    /// 才居得了中，这两段垫的就是「可滚」的下限。还没量出今天在哪之前先按半屏垫着
    /// （等于从前的行为），量到了再收 —— 所以这里的空白只会少、不会多。
    private func endInsets(half: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        guard let center = todayCenterY, let height = contentHeight else {
            return (half, half)
        }
        return (max(0, half - center), max(0, half - (height - center)))
    }

    /// 记事的那一条：输入框，旁边是记到哪个分类。
    ///
    /// 加号取整体主调的青色，与 tab 栏上那个沙漏一致 —— 它属于这一屏，不属于某个分类。
    /// 「这条会记到哪儿」由右边那个分类选择器说，它才是跟着分类换颜色的那个；
    /// 加号也跟着换的话，两处说同一件事，颜色反倒没了着落。
    private func input(category: Category, today: Date) -> some View {
        TodoInputField(
            tint: .teal,
            prompt: "记一件事，回车记在今天…",
            text: $draft,
            focused: $inputFocused,
            submit: { record(today: today) }
        ) {
            RecordingCategoryPicker(current: category)
        }
    }

    /// 记下草稿里的那件事。归到哪个分类、排在哪一天都由 `Store` 定，空白输入也由它挡掉；
    /// 这里只管清空并留住焦点，好让记事可以一条接一条。
    private func record(today: Date) {
        store.recordOnTimeline(draft, today: today)
        draft = ""
        inputFocused = true
    }
}

/// 记到哪个分类。列出全部分类，选中的那个由 `Store` 记着 —— 它跨重启保留，
/// 于是连续记同一类事情不用反复选。
///
/// 与轴上每行的 tag 一样是光板的：只有名字和一个小箭头，没有胶囊也不着色 ——
/// 这一条本就是记事栏里最不该抢眼的一格，箭头说明它点得开，够了。
private struct RecordingCategoryPicker: View {
    @Environment(Store.self) private var store
    let current: Category

    var body: some View {
        Menu {
            ForEach(store.categories) { category in
                Button {
                    store.chooseRecordingCategory(category.id)
                } label: {
                    // 当前那个前面带勾：菜单收起来时只看得见名字，展开才说得清哪个是选中的。
                    if category.id == current.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.name)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            // 没有底色也得有块点得着的地方：这点内缩就是它的按钮范围。
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        // 按钮式菜单加无样式按钮：自己排的那副 label 才留得住 ——
        // 无边框菜单会把它压成一行纯文字，字号、间距都留不住。
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("记到哪个分类")
    }
}

/// 轴上的一天：一个日期头，下面是这天的待办。
/// 今天这一组用强调样式，它是锚点；别的日子一律同一副模样 ——
/// 过去试过铺一块沉降的灰底，上手看着闹，去掉了：过去认不认得出，交给位置和琥珀圈就够。
///
/// 每一组同时是一个落点：条目拖到这儿松手，它的计划日就是这一天。
private struct DayGroup: View {
    @Environment(Store.self) private var store
    let day: TimelineDay
    let today: Date

    /// 有条目正悬在这一组上方。落点指示只认它 —— 松手落在哪一组，此刻亮的就是哪一组。
    @State private var targeted = false

    private var isToday: Bool { day.day.isSameDay(as: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(day.todos) { todo in
                TimelineRow(todo: todo, today: today)
            }
            // 空着也照样成组的只有今天，所以这句话只属于今天 —— 别的日子没有待办就根本不成组。
            if isToday && day.todos.isEmpty {
                Text("今天还没有安排")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 内缩每一组都留着，只有底色跟着今天变 —— 强调今天不该顺带把那一组的条目挪位置。
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isToday ? AnyShapeStyle(.teal.opacity(0.08)) : AnyShapeStyle(.clear))
        )
        // 落点指示画在外圈：整组连同日期头一起框起来，「松手会落在这一天」于是说得明明白白，
        // 而底色留给今天那个锚点 —— 两件事各说各的，不会看混。
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.teal.opacity(targeted ? 0.7 : 0), lineWidth: 2)
        )
        // 整块矩形都接得住，包括内缩留出的空白和只有一句话的今天 —— 落点不该只有文字那么窄。
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: DraggedTodo.self) { dropped, _ in
            // 一次拖一条 —— 轴上没有多选，落下的就只会是刚才抓起的那一行。
            guard let dropped = dropped.first else { return false }
            return store.reschedule(dropped.id, to: day.day)
        } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    /// 日期头。今天的写得大些、重些、是青的 —— 强调它靠字本身，不再拉一道横线：
    /// 那一组已经有整块底色框着了，横线是同一句话说第三遍。
    private var header: some View {
        Text(day.day.dayLabel(relativeTo: today))
            .font(.system(size: isToday ? 15 : 13, weight: isToday ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isToday ? AnyShapeStyle(.teal) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }
}

/// 轴上的一行待办：打勾的圈、正文、所属分类的 tag（这儿是光板的：没有胶囊、不着色）。
/// 圈点得动、悬停时右边浮出排期入口与删除、单击整行就地改写、右键还有「改写」与「移到分类」，
/// 整行可以拖到别的日期分组里去改期，也可以拖到 tab 栏上换分类。
///
/// 这些本事三处的行都一样，不看它在哪一列，见 ADR-0003：沙漏视图是打开主线默认落地的那一屏，
/// 也是最常盯着的一屏 —— 在这儿看见一句话写错了却得先切到某个分类去改，这一趟没有道理。
/// 打完勾条目留在原处不动（它属于它的计划日，不是完成日），只是变淡、圈亮 ——
/// 实际完成于哪天，轴上不说，去分类视图右列查。
private struct TimelineRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let today: Date
    @State private var hovering = false

    /// 正在就地改写这一行。改写时删除让开，其余各格原地不动。
    @State private var editing = TodoEditing()

    /// 分类被删了就没有 tag 可画 —— 但那时它的待办也一并没了，实际见不到。
    private var category: Category? { store.category(todo.categoryID) }

    /// 这一行上的彩色：打勾之后的圈，以及拖起来时手上跟着的那一小块。
    ///
    /// 轴上不用分类色，用整体主调的青色 —— 与 tab 栏上的沙漏、「今天」那一组同一个。
    /// 理由与这儿的 tag 不着色是同一条：一屏几十行，每行一个彩色勾圈就成了噪点，
    /// 而这一屏该抢眼的是「今天」。分类色留给未排期列的组头和分类视图，那两处颜色有出处。
    private let tint: Color = .teal

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, overdue: todo.isOverdue(today: today), tint: tint) {
                store.toggleTodo(todo)
            }

            TodoText(todo: todo, editing: $editing)
                .foregroundStyle(todo.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

            Spacer(minLength: 8)

            // 排期入口只有图标，不带常驻日期标签：这一行就躺在它计划日的分组底下，
            // 那天写在组头上，行上再挂一遍就是一列重复的灰字。
            PlannedDayControl(todo: todo, rowHovering: hovering, showsDate: false)

            // 删除浮在 tag 左边，不追加在它右边：tag 于是永远钉在行尾，
            // 一排行的右边缘因此是齐的，悬停也不会让它跳位置。
            // 改写时不浮出删除：手正放在字上，旁边不该还摆着一个删得掉整条的按钮。
            if hovering && !editing.active {
                TodoDeleteButton { withAnimation { store.deleteTodo(todo) } }
            }

            if let category {
                CategoryTag(category: category, chip: false)
            }
        }
        .todoRowChrome(hovering: hovering)
        .onHover { hovering = $0 }
        // 整行都拖得动，包括已完成的那些 —— 做完的事也照样可以改它排在哪天。
        // 内缩一并算进拖拽范围里，免得只有正文那几个字抓得住。
        .contentShape(Rectangle())
        .todoRowEditing(todo, editing: $editing)
        .draggable(DraggedTodo(id: todo.id)) {
            TodoDragPreview(text: todo.text, tint: tint)
        }
    }
}

/// 待办所属分类的 tag。两副样子：
///
/// - 带胶囊的（`chip` 为真）用在未排期列的组头上 —— 那儿它是一整组的标题，一屏只有几个，
///   着色取自分类 tab 选中态的那一套，两处因此永远是同一个颜色。
/// - 光板的用在轴上每一行：只有名字，没有底、没有边、也不着色。轴上一屏几十行，
///   每行挂一个彩色胶囊就成了噪点，而那儿该抢眼的是「今天」那一组，不是每行属于谁。
struct CategoryTag: View {
    let category: Category
    var chip: Bool = true

    var body: some View {
        if chip {
            Text(category.name)
                .font(.caption)
                .categoryChip(category.color.tint)
        } else {
            Text(category.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// 分类的彩色胶囊。眼下只有未排期列的组头用它 —— 那儿的颜色是一整组的标题。
    /// 着色取自分类 tab 选中态的那一套（`chipFill` / `chipStroke`），两处因此永远是同一个颜色。
    fileprivate func categoryChip(_ tint: Color) -> some View {
        foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.chipFill))
            .overlay(Capsule().stroke(tint.chipStroke, lineWidth: 1))
    }
}
