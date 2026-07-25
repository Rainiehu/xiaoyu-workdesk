import Foundation
import Testing

@testable import Workdesk

@MainActor
@Suite("分类视图的两列")
struct CategoryColumnsTests {
    @Test("左列里已排期的待办按计划日从早到晚")
    func scheduledTodosGoEarliestFirst() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            // 刻意乱序排期，好让升序不是「碰巧按记下的先后」蒙对的。
            try schedule("交周报", in: work, on: day(2026, 3, 9), store)
            try schedule("写周报", in: work, on: day(2026, 3, 5), store)
            try schedule("开会", in: work, on: day(2026, 3, 7), store)

            let columns = store.columns(in: work.id)

            #expect(columns.unfinished.map(\.text) == ["写周报", "开会", "交周报"])
        }
    }

    @Test("左列里未排期的待办接在已排期的后面，按创建日从新到旧")
    func unscheduledTodosFollowNewestFirst() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("先想到的", in: work.id)
            try schedule("交周报", in: work, on: day(2026, 3, 9), store)
            store.addTodo("后想到的", in: work.id)
            try schedule("写周报", in: work, on: day(2026, 3, 5), store)

            let columns = store.columns(in: work.id)

            #expect(columns.unfinished.map(\.text) == ["写周报", "交周报", "后想到的", "先想到的"])
        }
    }

    @Test("右列按完成日从新到旧，最近的成果在最上面")
    func finishedTodosGoNewestFirst() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("先做完的", in: work.id)
            store.addTodo("后做完的", in: work.id)
            // 打勾的先后就是完成日的先后，刻意与记下的先后相反。
            store.toggleTodo(try todo("先做完的", store))
            store.toggleTodo(try todo("后做完的", store))

            let columns = store.columns(in: work.id)

            #expect(columns.finished.map(\.text) == ["后做完的", "先做完的"])
        }
    }

    @Test("打勾后待办离开左列，落进右列")
    func tickingMovesATodoToTheRightColumn() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            try schedule("交周报", in: work, on: day(2026, 3, 9), store)

            store.toggleTodo(try todo("交周报", store))

            let columns = store.columns(in: work.id)
            #expect(columns.unfinished.map(\.text) == ["写周报"])
            #expect(columns.finished.map(\.text) == ["交周报"])
        }
    }

    @Test("取消打勾后待办回到左列，未排期的按创建日落回原位")
    func untickingPutsAnUnscheduledTodoBackInPlace() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("最早想到的", in: work.id)
            store.addTodo("中间想到的", in: work.id)
            store.addTodo("最晚想到的", in: work.id)

            store.toggleTodo(try todo("中间想到的", store))
            store.toggleTodo(try todo("中间想到的", store))

            let columns = store.columns(in: work.id)
            // 回到左列时按创建日落回中间，不因为打过勾就跑到一头去。
            #expect(columns.unfinished.map(\.text) == ["最晚想到的", "中间想到的", "最早想到的"])
            #expect(columns.finished.isEmpty)
        }
    }

    @Test("取消打勾后已排期的待办回到左列上半段，按计划日落回原位")
    func untickingPutsAScheduledTodoBackInPlace() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            try schedule("周一的事", in: work, on: day(2026, 3, 2), store)
            try schedule("周三的事", in: work, on: day(2026, 3, 4), store)
            try schedule("周五的事", in: work, on: day(2026, 3, 6), store)
            store.addTodo("总得做但不急", in: work.id)

            store.toggleTodo(try todo("周三的事", store))
            store.toggleTodo(try todo("周三的事", store))

            let columns = store.columns(in: work.id)
            #expect(columns.unfinished.map(\.text) == ["周一的事", "周三的事", "周五的事", "总得做但不急"])
            #expect(columns.finished.isEmpty)
        }
    }

    /// 计划日只到天，同一天排了几条是常事 —— 这时候按记下的先后排，
    /// 顺序因此是定死的，不指望 `sorted` 碰巧稳定。
    @Test("同一个计划日里的几条按记下的先后排")
    func todosOnTheSameDayKeepTheOrderTheyWereWrittenIn() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let monday = try day(2026, 3, 2)
            for text in ["第一件", "第二件", "第三件", "第四件", "第五件"] {
                try schedule(text, in: work, on: monday, store)
            }

            let columns = store.columns(in: work.id)

            #expect(columns.unfinished.map(\.text) == ["第一件", "第二件", "第三件", "第四件", "第五件"])
        }
    }

    @Test("两列里都只有这个分类自己的待办")
    func bothColumnsAreScopedToTheirCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("买菜", in: life.id)
            store.addTodo("倒垃圾", in: life.id)
            store.toggleTodo(try todo("倒垃圾", store))

            let columns = store.columns(in: work.id)
            #expect(columns.unfinished.map(\.text) == ["写周报"])
            #expect(columns.finished.isEmpty)

            let lifeColumns = store.columns(in: life.id)
            #expect(lifeColumns.unfinished.map(\.text) == ["买菜"])
            #expect(lifeColumns.finished.map(\.text) == ["倒垃圾"])
        }
    }

    /// 按正文找回一条待办。手里的副本会随着打勾、改期变旧，所以每次都现找。
    private func todo(_ text: String, _ store: Store) throws -> TodoItem {
        try #require(store.todos.first { $0.text == text })
    }
}
