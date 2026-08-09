import Foundation
import Testing

@testable import WorkdeskCore

/// 「过期」的口径：未完成 ∧ 计划日在今天之前，见 ADR-0004。
/// 纯派生判断，不用建 Store —— 这里拿 `TodoItem` 直接问。
@Suite("过期的口径")
struct OverdueTests {
    private func todo(plannedOn: Date? = nil, done: Bool = false) -> TodoItem {
        var todo = TodoItem(text: "写周报", categoryID: UUID())
        todo.plannedOn = plannedOn
        if done {
            todo.done = true
            todo.completedAt = .now
        }
        return todo
    }

    @Test("计划日在昨天而未完成，就是过期")
    func plannedYesterdayUnfinishedIsOverdue() throws {
        let item = todo(plannedOn: try day(2026, 3, 4))
        #expect(item.isOverdue(today: try day(2026, 3, 5)))
    }

    @Test("计划日就是今天的不算 —— 今天还没过完")
    func plannedTodayIsNotOverdue() throws {
        let item = todo(plannedOn: try day(2026, 3, 5))
        // 「今天」带着时刻交进来也一样：比的是哪一天，不是哪一刻。
        let lateToday = try #require(
            Calendar.current.date(byAdding: .hour, value: 23, to: try day(2026, 3, 5)))
        #expect(!item.isOverdue(today: lateToday))
    }

    @Test("计划日在将来的不算")
    func plannedInTheFutureIsNotOverdue() throws {
        let item = todo(plannedOn: try day(2026, 3, 6))
        #expect(!item.isOverdue(today: try day(2026, 3, 5)))
    }

    @Test("完成了就不过期，哪怕完成得再晚 —— 打勾那一下把记号抹掉")
    func doneIsNeverOverdue() throws {
        let item = todo(plannedOn: try day(2026, 3, 2), done: true)
        #expect(!item.isOverdue(today: try day(2026, 3, 5)))
    }

    @Test("未排期的谈不上过没过")
    func unplannedIsNeverOverdue() throws {
        #expect(!todo().isOverdue(today: try day(2026, 3, 5)))
    }

    @Test("跨过零点的那一刻起，昨天的计划就是过期 —— 边界按天算，不按 24 小时算")
    func overdueBeginsAtMidnightNotAfterTwentyFourHours() throws {
        let item = todo(plannedOn: try day(2026, 3, 4))
        // 3月5日 00:30:离计划日的零点还不到 24 小时,但日子已经翻过去了。
        let justPastMidnight = try #require(
            Calendar.current.date(byAdding: .minute, value: 30, to: try day(2026, 3, 5)))
        #expect(item.isOverdue(today: justPastMidnight))
    }
}
