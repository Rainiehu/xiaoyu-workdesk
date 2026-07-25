import Foundation
import Testing

@testable import Workdesk

@MainActor
@Suite("分类内的待办")
struct TodoTests {
    @Test("一个分类只看到自己的待办，分类之间互不干扰")
    func eachCategoryHasItsOwnList() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("买菜", in: life.id)
            store.addTodo("交周报", in: work.id)

            #expect(store.todos(in: work.id).map(\.text) == ["写周报", "交周报"])
            #expect(store.todos(in: life.id).map(\.text) == ["买菜"])
        }
    }

    @Test("空白或纯空格的输入不产生待办")
    func blankTextMakesNoTodo() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("", in: work.id)
            store.addTodo("   \n ", in: work.id)
            store.addTodo("  写周报  ", in: work.id)

            #expect(store.todos(in: work.id).map(\.text) == ["写周报"])
        }
    }

    @Test("打勾记下完成日，取消打勾把完成日清掉")
    func tickingWritesTheCompletionDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)

            store.toggleTodo(try #require(store.todos.first))
            let done = try #require(store.todos.first)
            #expect(done.done)
            // 完成时刻原样记下 —— 截到天是显示层的事，底下留着全时刻。
            let completedAt = try #require(done.completedAt)
            #expect(abs(completedAt.timeIntervalSinceNow) < 1)

            store.toggleTodo(done)
            let undone = try #require(store.todos.first)
            #expect(!undone.done)
            #expect(undone.completedAt == nil)
        }
    }

    @Test("删除一条待办，同分类的其余待办留在原处")
    func deletingRemovesOnlyThatTodo() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("交周报", in: work.id)

            store.deleteTodo(try #require(store.todos.first))

            #expect(store.todos(in: work.id).map(\.text) == ["交周报"])
        }
    }

    @Test("重启后待办的归属、完成状态、创建日、完成日都还在")
    func todosSurviveARestart() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("买菜", in: life.id)
            store.toggleTodo(try #require(store.todos.first))

            let reopened = Store(directory: dir)
            #expect(reopened.todos(in: work.id).map(\.text) == ["写周报"])
            #expect(reopened.todos(in: life.id).map(\.text) == ["买菜"])
            #expect(reopened.todos.map(\.done) == [true, false])
            #expect(reopened.todos.map { $0.completedAt != nil } == [true, false])

            // 两个时刻都单独比：落盘用的 ISO8601 不含小数秒，读回来只精确到秒。
            for (before, after) in zip(store.todos, reopened.todos) {
                #expect(abs(after.createdAt.timeIntervalSince(before.createdAt)) < 1)
                if let b = before.completedAt, let a = after.completedAt {
                    #expect(abs(a.timeIntervalSince(b)) < 1)
                }
            }
        }
    }
}
