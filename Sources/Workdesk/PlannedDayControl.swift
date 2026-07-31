import SwiftUI

/// 一条待办的计划日入口。已排期的，行里显示的那个日期标签本身就是入口；
/// 未排期的，静止时完全干净，只在悬停时浮出一个日历图标。两种模样点开的是同一个面板 ——
/// 排期与改期不是两件事。
///
/// 计划日在过去还是将来，写法一模一样：不置顶、不变色、不加徽标。
/// 「过期」这个概念在这里不存在，见 ADR-0001。
struct PlannedDayControl: View {
    @Environment(TodayClock.self) private var clock
    let todo: TodoItem
    /// 整行是不是正被悬停 —— 未排期的入口只在悬停时露面。
    let rowHovering: Bool

    @State private var presented = false

    var body: some View {
        if let planned = todo.plannedOn {
            entry { Text(planned.dayLabel(relativeTo: clock.today)).font(.caption) }
        } else if rowHovering || presented {
            // 面板开着时把图标留住：鼠标移去面板上就不算悬停这一行了，入口不能跟着消失。
            entry { Image(systemName: "calendar").font(.system(size: 12)) }
        }
    }

    private func entry(@ViewBuilder _ label: () -> some View) -> some View {
        Button { presented = true } label: {
            label()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(presented ? 0.7 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(todo.plannedOn == nil ? "安排计划日" : "改计划日")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            PlannedDayPanel(todo: todo, today: clock.today) { presented = false }
        }
    }
}

/// 计划日面板：几个常用快捷项、一个完整日历，以及清除计划日。
/// 只问哪一天，不问几点 —— 选出来的日子天然落在当天零点。
private struct PlannedDayPanel: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    /// 「今天」交进来，不在这儿问时钟 —— 面板上那个「今天」与轴上锚着的那一天必须是同一天。
    let today: Date
    let dismiss: () -> Void

    /// 日历上落脚的那天。未排期时先落在今天 —— 落脚不等于排期，
    /// 真要写进待办得等用户点一下。
    @State private var picked: Date

    init(todo: TodoItem, today: Date, dismiss: @escaping () -> Void) {
        self.todo = todo
        self.today = today
        self.dismiss = dismiss
        _picked = State(initialValue: todo.plannedOn ?? today.dayStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                shortcut("今天", daysFromToday: 0)
                shortcut("明天", daysFromToday: 1)
                shortcut("下周", daysFromToday: 7)
            }
            Divider()
            DatePicker("", selection: selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            if todo.plannedOn != nil {
                Divider()
                Button {
                    store.clearPlannedDay(todo)
                    dismiss()
                } label: {
                    Label("清除计划日", systemImage: "xmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    /// 日历上点一下就是排期。写在 setter 里而不是 `onChange` 里 —— `onChange` 只在值变了才响，
    /// 未排期的待办点「今天」（日历上正落脚在这儿）就会什么也不发生。
    private var selection: Binding<Date> {
        Binding {
            picked
        } set: { day in
            picked = day
            schedule(day)
        }
    }

    private func shortcut(_ title: String, daysFromToday: Int) -> some View {
        Button {
            schedule(day(daysFromToday))
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.quaternary.opacity(0.5)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 从今天数起的第几天，落在那天零点。
    private func day(_ offset: Int) -> Date {
        let start = today.dayStart
        return Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private func schedule(_ day: Date) {
        store.setPlannedDay(day, for: todo)
        dismiss()
    }
}
