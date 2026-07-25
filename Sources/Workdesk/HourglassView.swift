import SwiftUI
import UniformTypeIdentifiers

/// 沙漏视图：横跨所有分类的一条连续时间轴。排了计划日的待办按计划日铺成这条轴，
/// 今天锚在中间、上方是过去、下方是未来，打开时就滚到今天。
///
/// 分组由 `Store.timeline(today:)` 给出，这里不自己聚合。
///
/// 顶上是记事输入区：这里是打开主线默认落地的地方，也是最常问「接下来要做什么」的地方，
/// 所以它必须能直接记录，不该逼使用者先切到某个分类。在这儿记下的待办自动排在今天，
/// 于是它立刻出现在眼前这条轴上，而不是凭空消失到某个分类里去。
/// 轴上的条目可以直接拖到别的日期分组里去改期：调整安排是一个手势，不必点开日期面板。
/// 拖拽只发生在这条轴的日期分组之间，也只改计划日 —— 归属哪个分类是横轴上的事，不因这一拖而变。
///
/// 计划日在过去而未完成的待办与别的待办写法一模一样：不置顶、不变色、不加徽标、不自动顺延。
/// 「过期」这个概念不存在，见 ADR-0001。要给它加提醒之前请先读那份 ADR。
struct HourglassView: View {
    @Environment(Store.self) private var store

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    /// 轴与输入区共同的内容宽度上限与内缩。写在一处，两者因此左右对齐 ——
    /// 输入框看着就是这条轴的开头，不是浮在它上面的另一块东西。
    private let contentWidth: CGFloat = 640
    private let contentInset: CGFloat = 28

    var body: some View {
        // 「今天」每次渲染问一次，整条轴都跟着这一个值：锚点、强调、日期写法因此永远一致，
        // 而跨过零点之后的下一次渲染会自己跟上，不像存进 @State 那样一直停在昨天。
        let today = Date.now

        return VStack(spacing: 0) {
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
    }

    /// 只有排了期的日子在轴上，条数不多，所以用 VStack 而不是 LazyVStack ——
    /// 打开时要滚到今天，那一组必须已经在布局里。
    private func timeline(today: Date) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.timeline(today: today)) { day in
                        DayGroup(day: day, today: today)
                            .id(day.day)
                    }
                }
                .padding(.horizontal, contentInset)
                .padding(.vertical, 24)
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                // 落在中间而不是顶上：过去与未来因此同时露在眼前，两头都摆明了可以滚。
                proxy.scrollTo(today.dayStart, anchor: .center)
            }
        }
    }

    /// 记事的那一条：输入框，旁边是记到哪个分类。
    private func input(category: Category, today: Date) -> some View {
        TodoInputField(
            tint: category.color.tint,
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
/// 于是连续记同一类事情不用反复选。样子取自沙漏视图里的分类 tag，
/// 「这条会记成什么颜色」因此一眼就对得上。
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
            .categoryChip(current.color.tint)
        }
        // 按钮式菜单加无样式按钮：自定义的那身胶囊才画得出来 ——
        // 无边框菜单会把 label 压成一行纯文字，颜色和底色都留不住。
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("记到哪个分类")
    }
}

/// 轴上的一天：一个日期头，下面是这天的待办。
/// 今天这一组用强调样式，它是锚点；别的日子一律同一副模样。
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

    private var header: some View {
        HStack(spacing: 8) {
            Text(day.day.dayLabel(relativeTo: today))
                .font(.system(size: isToday ? 15 : 13, weight: isToday ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isToday ? AnyShapeStyle(.teal) : AnyShapeStyle(.secondary))
            if isToday {
                Rectangle()
                    .fill(.teal.opacity(0.35))
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }
}

/// 拖拽时在两个日期分组之间递过去的东西：一条待办的身份，仅此而已。
/// 只带 id 不带整条待办 —— 落下时按 id 现找现改，途中它被打了勾或被删了，也不会有旧副本被写回去。
///
/// 类型是自家的，于是从别处拖来的文字、链接一律不被当成改期；反过来，
/// 从轴上拖出去的东西别的应用也接不住 —— 这个手势只在这条轴里成立。
private struct DraggedTodo: Codable, Transferable {
    var id: TodoItem.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .workdeskTodo)
    }
}

extension UTType {
    /// 只有沙漏视图自己拖出来的条目认得这个类型。与 `build.sh` 里 Info.plist 的
    /// `UTExportedTypeDeclarations` 是同一个标识符，两边要一起改。
    fileprivate static let workdeskTodo = UTType(exportedAs: "cc.huxiaoyu.workdesk.todo")
}

/// 轴上的一行待办：正文、所属分类的彩色 tag，已完成的再画个勾并附一句实际完成日。
/// 整行可以拖到别的日期分组里去改期。
private struct TimelineRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let today: Date

    var body: some View {
        HStack(spacing: 10) {
            // 只给已完成的画勾，未完成的这里留空 —— 一个空心圆圈看着就像能点，
            // 而打勾和改期都在分类视图里做，轴上只看得见事情排在哪天。
            // 位置留着，好让各行的正文对齐。
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(todo.done ? 1 : 0)
                .frame(width: 14)

            Text(todo.text)
                .multilineTextAlignment(.leading)
                .foregroundStyle(todo.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

            Spacer(minLength: 8)

            if let completedAt = todo.completedAt {
                // 条目留在计划日那一组，实际完成日只在旁边附注一句：可查，但不喧宾夺主。
                Text("完成于 \(completedAt.dayLabel(relativeTo: today))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // 分类被删了就没有 tag 可画 —— 但那时它的待办也一并没了，实际见不到。
            if let category = store.category(todo.categoryID) {
                CategoryTag(category: category)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // 整行都拖得动，包括已完成的那些 —— 做完的事也照样可以改它排在哪天。
        // 内缩一并算进拖拽范围里，免得只有正文那几个字抓得住。
        .contentShape(Rectangle())
        .draggable(DraggedTodo(id: todo.id))
    }
}

/// 待办所属分类的彩色 tag。着色取自分类 tab 选中态的那一套，两处因此永远是同一个颜色。
struct CategoryTag: View {
    let category: Category

    var body: some View {
        Text(category.name)
            .font(.caption)
            .categoryChip(category.color.tint)
    }
}

extension View {
    /// 分类的彩色胶囊。轴上每条待办旁的 tag 与记事的分类选择器共用这一副样子 ——
    /// 「这条会记成什么颜色」于是与轴上已有的 tag 一眼对得上，不会各自漂移。
    fileprivate func categoryChip(_ tint: Color) -> some View {
        foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.chipFill))
            .overlay(Capsule().stroke(tint.chipStroke, lineWidth: 1))
    }
}
