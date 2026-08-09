import CloudKit
import Foundation
import Testing

@testable import WorkdeskCore

/// 软删除与撤销窗口（ADR-0007）：删除是打记号，不是抹掉 —— 占位跟着死者的原位走，
/// 每次删除各开一扇窗口、各自撤；窗口一关记录沉进池子，永远留着。
@MainActor
@Suite("软删除与撤销窗口")
struct SoftDeleteUndoTests {
    @Test("删掉的待办占位在原位，不算在「要做」的名下，窗口一关沉进池子并落盘")
    func deletedTodoHoldsItsPlaceThenSinks() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("买摄像头", in: work.id)
            store.addTodo("写周报", in: work.id)
            let doomed = try #require(store.todos.first { $0.text == "买摄像头" })

            store.deleteTodo(doomed)

            // 占位还站在原位：列表照旧两行，只是这一条打了记号；徽标已经不数它。
            #expect(store.todos(in: work.id).map(\.text) == ["买摄像头", "写周报"])
            #expect(store.todos(in: work.id).map(\.isDeleted) == [true, false])
            #expect(store.unfinishedTodoCount == 1)
            #expect(store.pendingUndos.count == 1)

            closeUndoWindows(store)
            #expect(store.todos.map(\.text) == ["写周报"])
            #expect(store.deletedTodos.map(\.text) == ["买摄像头"])
            // 池子落了盘 —— 重启回来还在，永远留着。
            let reopened = Store(directory: dir)
            #expect(reopened.todos.map(\.text) == ["写周报"])
            #expect(reopened.deletedTodos.map(\.text) == ["买摄像头"])
        }
    }

    @Test("窗口内撤销：记号摘掉，待办带着位置、排期、完成状态原样回来")
    func undoRestoresTheTodoIntact() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let monday = try day(2026, 8, 3)
            store.addTodo("三", in: work.id)
            store.addTodo("二", in: work.id)
            store.addTodo("一", in: work.id)
            let middle = try #require(store.todos.first { $0.text == "二" })
            store.setPlannedDay(monday, for: middle)

            store.deleteTodo(try #require(store.todos.first { $0.text == "二" }))
            store.undeleteTodo(middle.id)

            let back = try #require(store.todos.first { $0.id == middle.id })
            #expect(!back.isDeleted)
            #expect(back.plannedOn == monday)
            // 位置没动过 —— 左列的顺序还是「一二三」。
            #expect(store.columns(in: work.id).unfinished.map(\.text) == ["一", "二", "三"])
            #expect(store.pendingUndos.isEmpty)
            // 撤销把这条重新记上账 —— 云端得知道它又活了。
            #expect(store.syncLog.pendingSaves.contains(middle.changeEntry))
        }
    }

    @Test("连删几条各开各的窗口：救得准中间那条，其余照常沉底")
    func eachDeletionHasItsOwnWindow() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("三", in: work.id)
            store.addTodo("二", in: work.id)
            store.addTodo("一", in: work.id)
            for text in ["一", "二", "三"] {
                store.deleteTodo(try #require(store.todos.first { $0.text == text }))
            }
            #expect(store.pendingUndos.count == 3)

            // 只救中间那条 —— 各占各的，不必从最新往回撤。
            let middle = try #require(store.todos.first { $0.text == "二" })
            store.undeleteTodo(middle.id)

            #expect(store.pendingUndos.count == 2)
            closeUndoWindows(store)
            #expect(store.todos.map(\.text) == ["二"])
            #expect(Set(store.deletedTodos.map(\.text)) == ["一", "三"])
        }
    }

    @Test("⌘Z 按删除时间从新到旧收，一路点得回去")
    func undoLastWalksBackwards() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("先删的", in: work.id)
            store.addTodo("后删的", in: work.id)
            store.deleteTodo(try #require(store.todos.first { $0.text == "先删的" }))
            store.deleteTodo(try #require(store.todos.first { $0.text == "后删的" }))

            store.undoLastDelete()
            #expect(try #require(store.todos.first { $0.text == "后删的" }).isDeleted == false)
            #expect(try #require(store.todos.first { $0.text == "先删的" }).isDeleted == true)

            store.undoLastDelete()
            #expect(store.todos.map(\.isDeleted) == [false, false])
            // 都撤完了，再按一下什么也不发生。
            store.undoLastDelete()
            #expect(store.pendingUndos.isEmpty)
        }
    }

    @Test("删掉的分类占位在 tab 原位，撤销回原位；窗口关了从池子里也回得来")
    func deletedCategoryHoldsItsSlot() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let a = try #require(store.addCategory("甲"))
            let b = try #require(store.addCategory("乙"))
            let c = try #require(store.addCategory("丙"))

            #expect(store.deleteCategory(b.id) == .deleted)
            // 占位不合拢：数组里它还在原位，活人名单里没有它。
            #expect(store.categories.map(\.name) == ["甲", "乙", "丙"])
            #expect(store.livingCategories.map(\.name) == ["甲", "丙"])

            store.undeleteCategory(b.id)
            #expect(store.livingCategories.map(\.name) == ["甲", "乙", "丙"])

            // 再删一次，这回让窗口关掉 —— 池子带着死时的位置，回来还插在原处。
            #expect(store.deleteCategory(b.id) == .deleted)
            closeUndoWindows(store)
            #expect(store.categories.map(\.name) == ["甲", "丙"])
            #expect(store.deletedCategories.map(\.position) == [1])
            store.undeleteCategory(b.id)
            #expect(store.categories.map(\.name) == ["甲", "乙", "丙"])
            _ = (a, c)
        }
    }

    @Test("不变式：撤销一条待办，删除态的分类跟着复活")
    func undoingATodoRevivesItsCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("唯一一条", in: work.id)
            let todo = try #require(store.todos.first)

            // 删掉唯一的待办（它进了删除态，分类就算空了），跟着删分类。
            store.deleteTodo(todo)
            #expect(store.deleteCategory(work.id) == .deleted)

            // 直接救那条待办 —— 活着的待办的分类必须活着，分类跟着回来。
            store.undeleteTodo(todo.id)
            #expect(store.livingCategories.map(\.id) == [work.id])
            #expect(try #require(store.todos.first).isDeleted == false)
            #expect(store.pendingUndos.isEmpty)
        }
    }

    @Test("上次退出时窗口还开着的删除态记录，下次启动清扫进池子")
    func interruptedWindowsSweepIntoPoolsOnRelaunch() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("没等到窗口关", in: work.id)
            store.deleteTodo(try #require(store.todos.first))

            // 窗口还开着就「退出」了 —— 新开的 Store 只认落盘的记号。
            let reopened = Store(directory: dir)
            #expect(reopened.todos.isEmpty)
            #expect(reopened.deletedTodos.map(\.text) == ["没等到窗口关"])
            #expect(reopened.pendingUndos.isEmpty)
        }
    }

    @Test("远端来的删除态待办静静进池子，不弹窗口；活版本再来又回活人堆")
    func remoteDeletedStateLandsQuietly() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            var theirs = TodoItem(text: "另一台删的", categoryID: work.id)
            theirs.order = 0
            theirs.deletedAt = .now

            store.applyRemoteTodo(theirs)
            #expect(store.todos.isEmpty)
            #expect(store.deletedTodos.map(\.id) == [theirs.id])
            #expect(store.pendingUndos.isEmpty)

            // 另一台撤销了：活版本落地，从池子里回到活人堆。
            theirs.deletedAt = nil
            store.applyRemoteTodo(theirs)
            #expect(store.todos.map(\.id) == [theirs.id])
            #expect(store.deletedTodos.isEmpty)
        }
    }

    @Test("旧客户端的记录删除转成本地删除态：内容进池子，能留多少留多少")
    func legacyHardDeletionBecomesDeletedState() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("旧版本删的", in: work.id)
            let todo = try #require(store.todos.first)

            store.applyRemoteTodoDeletion(recordName: todo.recordName)
            #expect(store.todos.isEmpty)
            let sunk = try #require(store.deletedTodos.first)
            #expect(sunk.text == "旧版本删的")
            #expect(sunk.isDeleted)
        }
    }

    @Test("删掉的收藏占位在流里原位，撤销原样回来")
    func deletedFavoriteHoldsItsPlace() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("先收的")
            store.addFavorite("要删的")
            store.addFavorite("后收的")
            let doomed = try #require(store.favorites.first { $0.title == "要删的" })

            store.deleteFavorite(doomed)
            #expect(store.favorites.map(\.title) == ["先收的", "要删的", "后收的"])
            #expect(store.favorites.map(\.isDeleted) == [false, true, false])

            store.undeleteFavorite(doomed.id)
            #expect(store.favorites.map(\.isDeleted) == [false, false, false])

            store.deleteFavorite(doomed)
            closeUndoWindows(store)
            #expect(store.favorites.map(\.title) == ["先收的", "后收的"])
            #expect(store.deletedFavorites.map(\.title) == ["要删的"])
        }
    }

    @Test("引擎给删除态记录发货：三种记录都取得着，deletedAt 打包解包不丢")
    func deletedRecordsShipWithTheirMark() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("删除态也要上云", in: work.id)
            let todo = try #require(store.todos.first)
            store.deleteTodo(todo)
            closeUndoWindows(store)

            let shipped = try #require(store.todo(recordName: todo.recordName))
            #expect(shipped.isDeleted)
            let record = shipped.makeRecord()
            let back = try #require(TodoItem(record: record))
            #expect(back.deletedAt == shipped.deletedAt)
        }
    }
}
