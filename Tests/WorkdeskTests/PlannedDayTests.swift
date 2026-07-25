import Foundation
import Testing

@testable import Workdesk

@MainActor
@Suite("计划日")
struct PlannedDayTests {
    /// 一个确定的日子，好让断言不随「今天是几号」漂移。
    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day)))
    }

    @Test("新记下的待办是未排期的，排上计划日后它就有了")
    func schedulingAnUnscheduledTodo() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            let todo = try #require(store.todos.first)
            #expect(todo.plannedOn == nil)

            let march5 = try day(2026, 3, 5)
            store.setPlannedDay(march5, for: todo)

            #expect(store.todos.first?.plannedOn == march5)
        }
    }

    @Test("改到另一天，再清除就回到未排期")
    func rescheduleThenClear() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.setPlannedDay(try day(2026, 3, 5), for: try #require(store.todos.first))

            let march9 = try day(2026, 3, 9)
            store.setPlannedDay(march9, for: try #require(store.todos.first))
            #expect(store.todos.first?.plannedOn == march9)

            store.clearPlannedDay(try #require(store.todos.first))
            #expect(store.todos.first?.plannedOn == nil)
        }
    }

    /// 旧版本用创建日兼作计划日（「挪到今天」直接改写创建时间），这条守着它别复活。
    @Test("打勾不改动计划日，改期不改动创建日与完成日")
    func theThreeDaysNeverOverwriteEachOther() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            let created = try #require(store.todos.first?.createdAt)
            let march5 = try day(2026, 3, 5)
            store.setPlannedDay(march5, for: try #require(store.todos.first))

            store.toggleTodo(try #require(store.todos.first))
            let ticked = try #require(store.todos.first)
            #expect(ticked.plannedOn == march5)
            #expect(ticked.createdAt == created)
            let completed = try #require(ticked.completedAt)

            store.setPlannedDay(try day(2026, 3, 9), for: ticked)
            let moved = try #require(store.todos.first)
            #expect(moved.createdAt == created)
            #expect(moved.completedAt == completed)
            #expect(moved.done)
        }
    }

    @Test("计划日重启后还在，未排期的重启后仍是未排期")
    func plannedDaysSurviveARestart() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("学点什么", in: work.id)
            let march5 = try day(2026, 3, 5)
            store.setPlannedDay(march5, for: try #require(store.todos.first))

            let reopened = Store(directory: dir)
            #expect(reopened.todos.map(\.plannedOn) == [march5, nil])
        }
    }
}
