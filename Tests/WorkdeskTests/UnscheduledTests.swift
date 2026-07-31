import Foundation
import Testing

@testable import Workdesk

/// 沙漏视图右边那一列：还没排期的未完成待办，按分类分组。
@MainActor
@Suite("未排期的那一列")
struct UnscheduledTests {
    @Test("只有未完成且没排期的待办进这一列")
    func onlyUnfinishedAndUnscheduledTodosShowUp() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("总得做但不急", in: work.id)
            try schedule("周一的事", in: work, on: day(2026, 3, 2), store)
            store.addTodo("做完了的", in: work.id)
            store.toggleTodo(try #require(store.todos.first { $0.text == "做完了的" }))

            #expect(store.unscheduled.map(\.todos).flatMap { $0 }.map(\.text) == ["总得做但不急"])
        }
    }

    @Test("按分类分组，分组的顺序就是 tab 栏的顺序")
    func groupsFollowTheTabOrder() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("买菜", in: life.id)
            store.addTodo("写周报", in: work.id)

            #expect(store.unscheduled.map(\.category.name) == ["工作", "生活"])

            // tab 拖了顺序，这一列跟着走 —— 两处的先后是同一个。
            store.moveCategory(life.id, onto: work.id)
            #expect(store.unscheduled.map(\.category.name) == ["生活", "工作"])
        }
    }

    @Test("一条未排期待办都没有的分类不成组")
    func emptyCategoriesMakeNoGroup() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            try schedule("周一的事", in: work, on: day(2026, 3, 2), store)
            store.addTodo("买菜", in: life.id)

            #expect(store.unscheduled.map(\.category.name) == ["生活"])
        }
    }

    @Test("组内的先后与分类视图左列一致")
    func eachGroupFollowsTheHandMadeOrder() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            for text in ["A", "B", "C"] {
                store.addTodo(text, in: work.id)
            }
            store.reorderTodo(
                try #require(store.todos.first { $0.text == "C" }).id,
                onto: try #require(store.todos.first { $0.text == "A" }).id
            )

            let left = store.columns(in: work.id).unfinished.map(\.text)
            #expect(try #require(store.unscheduled.first).todos.map(\.text) == left)
        }
    }

    @Test("排上计划日就离开这一列，清掉计划日又回来")
    func schedulingTakesATodoOutOfTheColumn() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("总得做但不急", in: work.id)

            store.setPlannedDay(try day(2026, 3, 2), for: try #require(store.todos.first))
            #expect(store.unscheduled.isEmpty)

            store.clearPlannedDay(try #require(store.todos.first))
            #expect(store.unscheduled.map(\.todos).flatMap { $0 }.map(\.text) == ["总得做但不急"])
        }
    }
}
