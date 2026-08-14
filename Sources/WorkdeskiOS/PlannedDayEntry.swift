#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 一条待办的计划日入口，iOS 版：**常驻**，不等悬停（触屏没有悬停，见 CONTEXT-iOS.md）。
/// 排期与改期是同一件事：不论排没排期、完没完成，点开同一个面板。
///
/// 那一格一次只说一样，与 Mac 同一条规矩的触屏写法：
/// - 画日期的行（分类屏主列）：日期标签自己就是入口 —— 点它就点开面板，不再另挂图标；
/// - 不画日期的行（轴上：那天写在组头上；未排期面板：没排期没日期）：入口是一枚日历图标。
struct PlannedDayEntry: View {
    @Environment(TodayClock.self) private var clock
    let todo: TodoItem
    /// 静止时画不画日期标签。轴上不画（那天写在组头上），未排期面板不画（没排期）。
    var showsDate: Bool = true

    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            if showsDate, let planned = todo.plannedOn {
                Text(planned.dayLabel(relativeTo: clock.today))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            PlannedDaySheet(todo: todo, today: clock.today) { presented = false }
                .presentationDetents([.medium])
        }
    }
}

/// 计划日面板：几个常用快捷项、一个完整日历。只问哪一天，不问几点。
/// 取消排期没有单独的按钮：点到它已排的那一天，就是取消 —— 与 Mac 同一条规矩。
private struct PlannedDaySheet: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    /// 「今天」交进来，不在这儿问时钟 —— 面板上那个「今天」与轴上锚着的必须是同一天。
    let today: Date
    let dismiss: () -> Void

    @State private var picked: Date

    init(todo: TodoItem, today: Date, dismiss: @escaping () -> Void) {
        self.todo = todo
        self.today = today
        self.dismiss = dismiss
        _picked = State(initialValue: todo.plannedOn ?? today.dayStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                shortcut("今天", daysFromToday: 0)
                shortcut("明天", daysFromToday: 1)
                shortcut("下周", daysFromToday: 7)
            }
            Divider()
            DatePicker("", selection: selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 日历上点一下就是排期，点到已排的那天就是取消。写在 setter 里而不是 `onChange` 里 ——
    /// 点已排的那天时值没变，`onChange` 不响，而那一下正是取消排期的那一下。
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
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.quaternary.opacity(0.5)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

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
#endif
