import Foundation
import Testing

@testable import Workdesk

@MainActor
@Suite("分类")
struct CategoryTests {
    @Test("新建分类只需要一个名字，按新建顺序排列")
    func addCategoryTakesOnlyAName() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("工作")
            store.addCategory("生活")
            store.addCategory("想做的事")

            #expect(store.categories.map(\.name) == ["工作", "生活", "想做的事"])
        }
    }

    @Test("名字前后的空白被抹掉，空白名字不产生分类")
    func blankNamesAreRejected() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("  工作  ")
            store.addCategory("")
            store.addCategory("   \n ")

            #expect(store.categories.map(\.name) == ["工作"])
        }
    }

    @Test("连续新建的分类获得色板中互不相同的颜色")
    func colorsAreDistinct() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            for i in 1...CategoryColor.palette.count {
                store.addCategory("分类 \(i)")
            }

            let colors = store.categories.map(\.color)
            #expect(Set(colors).count == colors.count)
        }
    }

    @Test("色板用完之后仍然可以继续新建分类")
    func paletteExhaustionStillAllowsNewCategories() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let overflow = CategoryColor.palette.count + 2
            for i in 1...overflow {
                store.addCategory("分类 \(i)")
            }

            #expect(store.categories.count == overflow)
        }
    }

    @Test("分类在同一目录的两个 Store 之间往返：名字、颜色、顺序")
    func categoriesRoundTrip() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("工作")
            store.addCategory("生活")
            store.addCategory("想做的事")

            let reopened = Store(directory: dir)
            #expect(reopened.categories == store.categories)
            #expect(reopened.categories.map(\.name) == ["工作", "生活", "想做的事"])
        }
    }

    @Test("全新目录里一个分类都没有，也不自动创建默认分类")
    func zeroCategoriesIsALegalState() throws {
        try withTemporaryDirectory { dir in
            #expect(Store(directory: dir).categories.isEmpty)
        }
    }

}

@MainActor
@Suite("待办的所属分类")
struct TodoCategoryTests {
    @Test("待办带着所属分类往返")
    func todosRoundTripWithTheirCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("买菜", in: life.id)

            let reopened = Store(directory: dir)
            #expect(reopened.todos.map(\.text) == ["写周报", "买菜"])
            #expect(reopened.todos.map(\.categoryID) == [work.id, life.id])
        }
    }

    @Test("待办必须落在一个已存在的分类里")
    func todosNeedAnExistingCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("无处安放", in: UUID())

            #expect(store.todos.map(\.text) == ["写周报"])
        }
    }

    @Test("未完成的待办数量是侧边栏徽标要的那个数")
    func unfinishedCountIgnoresFinishedTodos() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("交周报", in: work.id)
            #expect(store.unfinishedTodoCount == 2)

            store.toggleTodo(try #require(store.todos.first))
            #expect(store.unfinishedTodoCount == 1)
        }
    }

    @Test("分类与待办分别持久化在两份文件里")
    func categoriesAndTodosArePersistedSeparately() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)

            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            let content = try names.reduce(into: [String: String]()) { acc, name in
                acc[name] = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            }
            let holdingCategory = content.filter { $0.value.contains("工作") }.keys
            let holdingTodo = content.filter { $0.value.contains("写周报") }.keys

            #expect(holdingCategory.count == 1)
            #expect(holdingTodo.count == 1)
            #expect(Set(holdingCategory).isDisjoint(with: Set(holdingTodo)))
        }
    }

    @Test("旧的待办数据文件不被读取，首次运行按空状态处理")
    func legacyTodoFileIsIgnored() throws {
        try withTemporaryDirectory { dir in
            let legacy = """
            [
              {
                "id": "\(UUID().uuidString)",
                "text": "旧版本留下的待办",
                "done": false,
                "createdAt": "2025-01-01T08:00:00Z"
              }
            ]
            """
            try legacy.write(
                to: dir.appendingPathComponent("todos.json"), atomically: true, encoding: .utf8)

            let store = Store(directory: dir)
            #expect(store.todos.isEmpty)
            #expect(store.categories.isEmpty)
        }
    }
}
