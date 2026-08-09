import Foundation
import Testing

@testable import WorkdeskCore

/// 左列的顺序归使用者自己拖，见 ADR-0002。
@MainActor
@Suite("左列的顺序")
struct TodoOrderTests {
    @Test("把一条放到下面某一条身上，中间的依次让开")
    func droppingOntoALowerRowPushesTheOthersUp() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B", "C", "D"], in: dir)

            // A 放到 C 身上：A 落在 C 原来的位置，B、C 依次上移。
            try store.drag("A", onto: "C")

            #expect(try store.leftColumn() == ["B", "C", "A", "D"])
        }
    }

    @Test("把一条放到上面某一条身上，被压住的依次让开")
    func droppingOntoAHigherRowPushesTheOthersDown() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B", "C", "D"], in: dir)

            try store.drag("D", onto: "B")

            #expect(try store.leftColumn() == ["A", "D", "B", "C"])
        }
    }

    @Test("换位置只动顺序：归属、三个日子与完成状态都不变")
    func reorderingChangesNothingElse() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B", "C"], in: dir)
            store.setPlannedDay(try day(2026, 3, 2), for: try store.todo("C"))
            let before = try store.todo("C")

            try store.drag("C", onto: "A")

            let after = try store.todo("C")
            #expect(after.categoryID == before.categoryID)
            #expect(after.plannedOn == before.plannedOn)
            #expect(after.createdAt == before.createdAt)
            #expect(after.completedAt == before.completedAt)
            #expect(after.done == before.done)
        }
    }

    @Test("自己排的顺序跨重启还在")
    func theOrderSurvivesARestart() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B", "C"], in: dir)
            try store.drag("A", onto: "B")
            let arrangedOrder = try store.leftColumn()

            #expect(try Store(directory: dir).leftColumn() == arrangedOrder)
        }
    }

    @Test("跨分类的两条之间拖不动，两边的顺序都不变")
    func draggingAcrossCategoriesDoesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("交周报", in: work.id)
            store.addTodo("买菜", in: life.id)

            #expect(!store.reorderTodo(try store.todo("买菜").id, onto: try store.todo("写周报").id))

            #expect(store.columns(in: work.id).unfinished.map(\.text) == ["交周报", "写周报"])
            #expect(store.columns(in: life.id).unfinished.map(\.text) == ["买菜"])
        }
    }

    @Test("放到它自己身上什么也不发生")
    func droppingOntoItselfDoesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B", "C"], in: dir)
            let before = try store.leftColumn()

            let moved = try store.todo("B")
            #expect(!store.reorderTodo(moved.id, onto: moved.id))

            #expect(try store.leftColumn() == before)
        }
    }

    @Test("拖到别的分类去，落在新分类的最上面")
    func aTodoDraggedToAnotherCategoryLandsOnTop() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("买菜", in: life.id)
            store.addTodo("倒垃圾", in: life.id)
            store.addTodo("写周报", in: work.id)

            #expect(store.moveTodo(try store.todo("写周报").id, to: life.id))

            #expect(store.columns(in: life.id).unfinished.map(\.text) == ["写周报", "倒垃圾", "买菜"])
            #expect(store.columns(in: work.id).unfinished.isEmpty)
        }
    }

    @Test("拖回它已经在的那个分类什么也不发生，位置也不动")
    func movingToItsOwnCategoryDoesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B", "C"], in: dir)
            let before = try store.leftColumn()
            let work = try #require(store.categories.first)

            #expect(!store.moveTodo(try store.todo("C").id, to: work.id))

            #expect(try store.leftColumn() == before)
        }
    }

    /// 升级上来的数据里没有位置这个字段。载入时照老规矩补一遍：已排期的在上，
    /// 按计划日从早到晚；未排期的在下，按创建日从新到旧 —— 第一眼看到的顺序与升级前一模一样。
    @Test("旧数据没有位置，载入时照老规矩补上")
    func oldDataGetsItsOrderSeeded() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("先想到的", in: work.id)
            store.addTodo("后想到的", in: work.id)
            try schedule("周五的事", in: work, on: day(2026, 3, 6), store)
            try schedule("周一的事", in: work, on: day(2026, 3, 2), store)

            try makeItLookOld(in: dir)

            let reopened = Store(directory: dir)
            #expect(try reopened.leftColumn() == ["周一的事", "周五的事", "后想到的", "先想到的"])
            // 补完就落了盘，下次启动不必再补一遍。
            #expect(reopened.todos.allSatisfy { $0.order != nil })
            #expect(try Store(directory: dir).leftColumn() == ["周一的事", "周五的事", "后想到的", "先想到的"])
        }
    }

    /// 建一个分类，按交进来的先后记下几条待办，返回排好的 `Store`。
    /// 记事是新的在上，所以左列一开始就是倒过来的那一串 —— 各条测试自己去拖。
    private func arranged(_ texts: [String], in dir: URL) throws -> Store {
        let store = Store(directory: dir)
        let work = try #require(store.addCategory("工作"))
        for text in texts.reversed() {
            store.addTodo(text, in: work.id)
        }
        #expect(try store.leftColumn() == texts)
        return store
    }

    /// 把落盘的待办改成升级之前的样子：抹掉位置那个字段，
    /// 顺带把创建时刻按记下的先后隔开一分钟 —— 落盘的 ISO8601 不含小数秒，
    /// 同一秒里记下的几条读回来创建时刻一模一样，那时「按创建日从新到旧」根本无从谈起。
    private func makeItLookOld(in dir: URL) throws {
        let url = dir.appendingPathComponent("todos-v2.json")
        let raw = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let formatter = ISO8601DateFormatter()
        let base = Date(timeIntervalSince1970: 1_772_000_000)
        let old = try #require(raw as? [[String: Any]]).enumerated().map { i, todo in
            var todo = todo
            todo["order"] = nil
            todo["createdAt"] = formatter.string(from: base.addingTimeInterval(Double(i) * 60))
            return todo
        }
        try JSONSerialization.data(withJSONObject: old).write(to: url)
    }
}

@MainActor
extension Store {
    /// 唯一那个分类的左列。多分类的测试自己去 `columns(in:)` 拿。
    fileprivate func leftColumn() throws -> [String] {
        columns(in: try #require(categories.first).id).unfinished.map(\.text)
    }

    /// 按正文找回一条待办。手里的副本会随着打勾、改期、换位置变旧，所以每次都现找。
    fileprivate func todo(_ text: String) throws -> TodoItem {
        try #require(todos.first { $0.text == text })
    }

    /// 拖着一条放到另一条身上，并断言这一放落到了实处。
    fileprivate func drag(_ text: String, onto targetText: String) throws {
        #expect(reorderTodo(try todo(text).id, onto: try todo(targetText).id))
    }
}
