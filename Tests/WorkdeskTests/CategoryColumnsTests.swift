import Foundation
import Testing

@testable import Workdesk

@MainActor
@Suite("分类视图的两列")
struct CategoryColumnsTests {
    @Test("新记下的待办落在左列最上面")
    func newTodosLandOnTop() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("先想到的", in: work.id)
            store.addTodo("后想到的", in: work.id)
            store.addTodo("刚想到的", in: work.id)

            let columns = store.columns(in: work.id)

            #expect(columns.unfinished.map(\.text) == ["刚想到的", "后想到的", "先想到的"])
        }
    }

    /// 左列的顺序归使用者自己拖，日期在这一列里不组织任何东西，见 ADR-0002。
    @Test("排期与改期都不动左列的顺序")
    func schedulingLeavesTheOrderAlone() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("先想到的", in: work.id)
            store.addTodo("后想到的", in: work.id)
            let before = store.columns(in: work.id).unfinished.map(\.text)

            // 给排在底下的那条排一个最早的日子：换了老规矩它会窜到最上面去。
            store.setPlannedDay(try day(2026, 3, 2), for: try todo("先想到的", store))
            store.setPlannedDay(try day(2026, 3, 9), for: try todo("后想到的", store))

            #expect(store.columns(in: work.id).unfinished.map(\.text) == before)
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

    @Test("取消打勾后待办回到左列原来的位置")
    func untickingPutsATodoBackInPlace() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("最早想到的", in: work.id)
            store.addTodo("中间想到的", in: work.id)
            store.addTodo("最晚想到的", in: work.id)

            store.toggleTodo(try todo("中间想到的", store))
            store.toggleTodo(try todo("中间想到的", store))

            let columns = store.columns(in: work.id)
            // 落回原来那个位置，不因为打过勾就跑到一头去。
            #expect(columns.unfinished.map(\.text) == ["最晚想到的", "中间想到的", "最早想到的"])
            #expect(columns.finished.isEmpty)
        }
    }

    /// 打勾的那条离开左列时不重排，回来时也就回得到原处 —— 中间那条被抽走又插回来，
    /// 它两边的先后一次都没变过。
    @Test("拖过序的一列里，打勾再取消也回得到原处")
    func untickingRespectsAHandMadeOrder() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            for text in ["第一件", "第二件", "第三件"] {
                store.addTodo(text, in: work.id)
            }
            // 拖成自己排的样子：把最早那条提到最上面。
            store.reorderTodo(try todo("第一件", store).id, onto: try todo("第三件", store).id)
            let arranged = store.columns(in: work.id).unfinished.map(\.text)

            store.toggleTodo(try todo("第二件", store))
            store.toggleTodo(try todo("第二件", store))

            #expect(store.columns(in: work.id).unfinished.map(\.text) == arranged)
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
