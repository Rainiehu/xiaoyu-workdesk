import Foundation
import Testing

@testable import WorkdeskCore

@MainActor
@Suite("沙漏视图的分组")
struct TimelineTests {
    @Test("只有排了计划日的待办进入沙漏视图")
    func onlyPlannedTodosAppear() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("总得做但不急", in: work.id)
            let march5 = try day(2026, 3, 5)
            store.setPlannedDay(march5, for: try #require(store.todos.first))

            let timeline = store.timeline(today: try day(2026, 3, 5))

            #expect(timeline.flatMap(\.todos).map(\.text) == ["写周报"])
        }
    }

    @Test("待办按计划日分组，组间按日期升序，横跨所有分类")
    func groupsAreSortedByDayAcrossCategories() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            // 刻意乱序排期，好让升序不是「碰巧按记下的先后」蒙对的。
            try schedule("交周报", in: work, on: day(2026, 3, 9), store)
            try schedule("买菜", in: life, on: day(2026, 3, 5), store)
            try schedule("写周报", in: work, on: day(2026, 3, 5), store)

            let timeline = store.timeline(today: try day(2026, 3, 5))

            #expect(timeline.map(\.day) == [try day(2026, 3, 5), try day(2026, 3, 9)])
            #expect(timeline.map { $0.todos.map(\.text) } == [["买菜", "写周报"], ["交周报"]])
        }
    }

    @Test("没有待办的日期不产生分组，中间的空日子直接跳过")
    func emptyDaysProduceNoGroups() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            try schedule("写周报", in: work, on: day(2026, 3, 5), store)
            try schedule("交周报", in: work, on: day(2026, 3, 20), store)

            let timeline = store.timeline(today: try day(2026, 3, 5))

            #expect(timeline.count == 2)
        }
    }

    @Test("今天这一组即使一件事都没有也照样在，它是锚点")
    func todayIsAlwaysThere() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            try schedule("写周报", in: work, on: day(2026, 3, 20), store)

            let today = try day(2026, 3, 5)
            let timeline = store.timeline(today: today)

            #expect(timeline.map(\.day) == [today, try day(2026, 3, 20)])
            #expect(timeline.first?.todos.isEmpty == true)
        }
    }

    @Test("空无一物的沙漏视图里也只有今天这一组")
    func todaySurvivesAnEmptyStore() throws {
        try withTemporaryDirectory { dir in
            let today = try day(2026, 3, 5)
            let timeline = Store(directory: dir).timeline(today: today)

            #expect(timeline.map(\.day) == [today])
        }
    }

    @Test("今天取的是那一刻所在的日子，不是那一刻本身")
    func todayIsADayNotAMoment() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let today = try day(2026, 3, 5)
            try schedule("写周报", in: work, on: today, store)

            let afternoon = try #require(
                Calendar.current.date(byAdding: .hour, value: 14, to: today))
            let timeline = store.timeline(today: afternoon)

            #expect(timeline.map(\.day) == [today])
            #expect(timeline.first?.todos.map(\.text) == ["写周报"])
        }
    }

    @Test("已完成的待办归入计划日那一组，不跳到完成日那一组")
    func completedTodosStayOnTheirPlannedDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.toggleTodo(try #require(store.todos.first))
            // 完成日就是打勾的那一刻；计划日刻意往前挪几天，两者因此不是同一天。
            let completed = try #require(store.todos.first?.completedAt)
            let planned = try #require(
                Calendar.current.date(byAdding: .day, value: -3, to: completed.dayStart))
            store.setPlannedDay(planned, for: try #require(store.todos.first))

            let timeline = store.timeline(today: completed)

            #expect(timeline.map(\.day) == [planned, completed.dayStart])
            #expect(timeline.first?.todos.map(\.text) == ["写周报"])
            #expect(timeline.last?.todos.isEmpty == true)
        }
    }

    /// 过期只是行上的一个安静记号（见 ADR-0004），在派生数据这一层没有任何特殊待遇：
    /// 不顺延、不置顶，这半条 ADR-0001 仍然有效。
    @Test("计划日在过去而未完成的待办留在它那一天，不顺延也不置顶")
    func pastUnfinishedTodosStayPut() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            try schedule("上周就该写的周报", in: work, on: day(2026, 3, 2), store)
            try schedule("买菜", in: work, on: day(2026, 3, 5), store)

            let timeline = store.timeline(today: try day(2026, 3, 5))

            #expect(timeline.map(\.day) == [try day(2026, 3, 2), try day(2026, 3, 5)])
            #expect(timeline.map { $0.todos.map(\.text) } == [["上周就该写的周报"], ["买菜"]])
        }
    }

    /// 沙漏视图里每条待办旁边那个彩色 tag 的来处：颜色是所属分类的颜色，视图层只负责画。
    @Test("每条待办都能找回它的所属分类，连同颜色")
    func todosCanFindTheirCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            try schedule("写周报", in: work, on: day(2026, 3, 5), store)
            try schedule("买菜", in: life, on: day(2026, 3, 5), store)

            let todos = try #require(store.timeline(today: try day(2026, 3, 5)).first?.todos)
            let categories = todos.map { store.category($0.categoryID) }

            #expect(categories.map { $0?.name } == ["工作", "生活"])
            #expect(categories.map { $0?.color } == [work.color, life.color])
            #expect(store.category(UUID()) == nil)
        }
    }
}
