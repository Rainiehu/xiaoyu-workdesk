import SwiftUI

/// 沙漏视图：横跨所有分类的一条连续时间轴。排了计划日的待办按计划日铺成这条轴，
/// 今天锚在中间、上方是过去、下方是未来，打开时就滚到今天。
///
/// 分组由 `Store.timeline(today:)` 给出，这里不自己聚合。
/// 这一版只读 —— 不在这儿新建待办，也不拖拽改期。
///
/// 计划日在过去而未完成的待办与别的待办写法一模一样：不置顶、不变色、不加徽标、不自动顺延。
/// 「过期」这个概念不存在，见 ADR-0001。要给它加提醒之前请先读那份 ADR。
struct HourglassView: View {
    @Environment(Store.self) private var store

    var body: some View {
        // 「今天」每次渲染问一次，整条轴都跟着这一个值：锚点、强调、日期写法因此永远一致，
        // 而跨过零点之后的下一次渲染会自己跟上，不像存进 @State 那样一直停在昨天。
        let today = Date.now

        // 只有排了期的日子在轴上，条数不多，所以用 VStack 而不是 LazyVStack ——
        // 打开时要滚到今天，那一组必须已经在布局里。
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.timeline(today: today)) { day in
                        DayGroup(day: day, today: today)
                            .id(day.day)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                // 落在中间而不是顶上：过去与未来因此同时露在眼前，两头都摆明了可以滚。
                proxy.scrollTo(today.dayStart, anchor: .center)
            }
        }
    }
}

/// 轴上的一天：一个日期头，下面是这天的待办。
/// 今天这一组用强调样式，它是锚点；别的日子一律同一副模样。
private struct DayGroup: View {
    let day: TimelineDay
    let today: Date

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

/// 轴上的一行待办：正文、所属分类的彩色 tag，已完成的再画个勾并附一句实际完成日。
private struct TimelineRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let today: Date

    var body: some View {
        HStack(spacing: 10) {
            // 只给已完成的画勾，未完成的这里留空 —— 一个空心圆圈看着就像能点，
            // 而这张视图只读，打勾和改期都在分类视图里做。位置留着，好让各行的正文对齐。
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
    }
}

/// 待办所属分类的彩色 tag。着色取自分类 tab 选中态的那一套，两处因此永远是同一个颜色。
struct CategoryTag: View {
    let category: Category

    var body: some View {
        Text(category.name)
            .font(.caption)
            .foregroundStyle(category.color.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(category.color.tint.chipFill))
            .overlay(Capsule().stroke(category.color.tint.chipStroke, lineWidth: 1))
    }
}
