import Foundation
import Testing

@testable import WorkdeskCore

@MainActor
@Suite("沙漏视图的拖拽改期")
struct TimelineDragTests {
    @Test("拖到另一个日期分组，计划日就是那一组的日子")
    func droppingOnAnotherDayChangesThePlannedDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let march5 = try day(2026, 3, 5)
            try schedule("写周报", in: work, on: march5, store)
            let todo = try #require(store.todos.first)

            let march9 = try day(2026, 3, 9)
            store.reschedule(todo.id, to: march9)

            #expect(store.todos.first?.plannedOn == march9)
        }
    }

    @Test("改期后条目就在目标分组里，原来那组不再有它")
    func theTodoMovesBetweenGroups() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let march5 = try day(2026, 3, 5)
            let march9 = try day(2026, 3, 9)
            try schedule("写周报", in: work, on: march5, store)
            try schedule("买菜", in: work, on: march5, store)
            try schedule("交周报", in: work, on: march9, store)
            let 写周报 = try #require(store.todos.first)

            store.reschedule(写周报.id, to: march9)

            let timeline = store.timeline(today: march5)
            #expect(timeline.map(\.day) == [march5, march9])
            #expect(timeline.map { $0.todos.map(\.text) } == [["买菜"], ["写周报", "交周报"]])
        }
    }

    /// 旧版本用创建日兼作计划日，拖拽是最容易让它复活的地方 —— 这条守着别的日子别被顺手改掉。
    @Test("改期只动计划日：归属分类、创建日、完成日与完成状态都不受影响")
    func reschedulingTouchesNothingButThePlannedDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            try schedule("写周报", in: work, on: try day(2026, 3, 5), store)
            store.toggleTodo(try #require(store.todos.first))
            let before = try #require(store.todos.first)
            let completed = try #require(before.completedAt)

            store.reschedule(before.id, to: try day(2026, 3, 9))

            let after = try #require(store.todos.first)
            #expect(after.categoryID == work.id)
            #expect(after.createdAt == before.createdAt)
            #expect(after.completedAt == completed)
            #expect(after.done)
            #expect(after.text == before.text)
        }
    }

    @Test("拖到一条不存在的待办上什么也不发生")
    func reschedulingAMissingTodoChangesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let march5 = try day(2026, 3, 5)
            try schedule("写周报", in: work, on: march5, store)

            #expect(store.reschedule(UUID(), to: try day(2026, 3, 9)) == false)
            #expect(store.todos.first?.plannedOn == march5)
        }
    }

    @Test("落下算数时说得出来，好让视图层知道这一放接住了没有")
    func aLandedDropReportsItself() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            try schedule("写周报", in: work, on: try day(2026, 3, 5), store)
            let todo = try #require(store.todos.first)

            #expect(store.reschedule(todo.id, to: try day(2026, 3, 9)))
        }
    }

    @Test("放回原来那一组，计划日还是那一天")
    func droppingBackOnTheSameDayKeepsThePlannedDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let march5 = try day(2026, 3, 5)
            try schedule("写周报", in: work, on: march5, store)
            let todo = try #require(store.todos.first)

            store.reschedule(todo.id, to: march5)

            #expect(store.todos.first?.plannedOn == march5)
        }
    }

    /// 落点交进来的是分组自己的那个日子，而分组的日子天然是当天零点 ——
    /// 于是拖出来的计划日只到天，`Store` 一路上没有替谁截断过。
    @Test("落到哪一组，计划日就是那一组的日子，天然只到天")
    func theDroppedDayIsTheGroupsOwnDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let march5 = try day(2026, 3, 5)
            try schedule("写周报", in: work, on: march5, store)
            try schedule("交周报", in: work, on: try day(2026, 3, 9), store)
            let 写周报 = try #require(store.todos.first)
            // 「今天」刻意给一个下午的时刻：分组的日子该是那个日子本身，不带时刻。
            let afternoon = try #require(Calendar.current.date(byAdding: .hour, value: 14, to: march5))
            let target = try #require(store.timeline(today: afternoon).last)

            store.reschedule(写周报.id, to: target.day)

            let planned = try #require(store.todos.first?.plannedOn)
            #expect(planned == target.day)
            #expect(planned == planned.dayStart)
        }
    }

    @Test("拖出来的计划日重启后还在")
    func aDraggedPlannedDaySurvivesARestart() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            try schedule("写周报", in: work, on: try day(2026, 3, 5), store)
            let march9 = try day(2026, 3, 9)

            store.reschedule(try #require(store.todos.first).id, to: march9)

            #expect(Store(directory: dir).todos.first?.plannedOn == march9)
        }
    }
}
