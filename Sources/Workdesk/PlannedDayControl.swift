import SwiftUI
import WorkdeskCore

/// 一条待办的计划日入口。排期与改期是同一件事：不论排没排期、完没完成，悬停时都浮出
/// 同一个日历图标，点开同一个面板 —— 入口不随行的状态换模样，看见图标就知道这一下是干什么的。
/// 四处的行（分类视图两列、轴上、未排期列）都是这一个入口。
/// 已排期的行另有一个日期标签，但这一格一次只说一样：静止时是安静的标签，
/// 悬停时它让位给图标 —— 图标点开的面板说的就是这一天，两个并排就是重复。
///
/// 计划日在过去还是将来，日期标签的写法一模一样：不变色、不加徽标 ——
/// 过期的记号只有一处，在那一行的勾圈上（描成琥珀），不在这儿再说一遍。见 ADR-0004。
struct PlannedDayControl: View {
    @Environment(TodayClock.self) private var clock
    let todo: TodoItem
    /// 整行是不是正被悬停 —— 入口只在悬停时露面，静止时行上只有日期这个安静的标签。
    let rowHovering: Bool
    /// 静止时的日期标签画不画。轴上不画（那天写在组头上，行上再挂一遍是重复的灰字），
    /// 分类视图右列不画（那格常驻的是完成日，由所在那列自己画）—— 两处只要悬浮的图标。
    var showsDate: Bool = true

    @State private var presented = false

    var body: some View {
        if showsDate, !entryVisible, let planned = todo.plannedOn {
            Text(planned.dayLabel(relativeTo: clock.today))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if entryVisible {
            entry
        }
    }

    /// 面板开着时把图标留住：鼠标移去面板上就不算悬停这一行了，入口不能跟着消失
    /// （日期标签也跟着继续让位，不挤回来）。
    private var entryVisible: Bool { rowHovering || presented }

    private var entry: some View {
        Button { presented = true } label: {
            Image(systemName: "calendar")
                .font(.system(size: 12))
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

/// 计划日面板：几个常用快捷项、一个完整日历。
/// 只问哪一天，不问几点 —— 选出来的日子天然落在当天零点。
///
/// 取消排期没有单独的按钮：点到它已排的那一天，就是取消 —— 日历上点、快捷键点，同一条规矩。
/// 面板因此不随行的状态换模样，排没排期、完没完成，长的都是这一副。
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
        }
        .padding(14)
        .frame(width: 260)
    }

    /// 日历上点一下就是排期，点到已排的那天就是取消。写在 setter 里而不是 `onChange` 里 ——
    /// `onChange` 只在值变了才响，点已排的那天（日历上正落脚在这儿）就会什么也不发生，
    /// 而那一下正是取消排期的那一下。
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

    /// 排到这一天；已排这一天就是取消 —— 那条规矩在 `Store.togglePlannedDay`，两端同一份。
    private func schedule(_ day: Date) {
        store.togglePlannedDay(todo, to: day)
        dismiss()
    }
}
