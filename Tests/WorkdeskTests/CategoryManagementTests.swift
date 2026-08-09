import Foundation
import Testing

@testable import WorkdeskCore

@MainActor
@Suite("分类的改名、换色与排序")
struct CategoryEditingTests {
    @Test("改名之后名字立即生效，并且跨重启还在")
    func renamePersists() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addCategory("生活")

            store.renameCategory(work.id, to: "上班")

            #expect(store.categories.map(\.name) == ["上班", "生活"])
            #expect(Store(directory: dir).categories.map(\.name) == ["上班", "生活"])
        }
    }

    @Test("改名只抹掉前后空白，空白名字不改")
    func renameTrimsAndRejectsBlank() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))

            store.renameCategory(work.id, to: "  上班  ")
            #expect(store.categories.map(\.name) == ["上班"])

            store.renameCategory(work.id, to: "   \n ")
            #expect(store.categories.map(\.name) == ["上班"])
        }
    }

    @Test("换颜色之后新颜色跨重启还在，别的分类不受影响")
    func recolorPersists() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))

            store.recolorCategory(work.id, to: .orange)

            #expect(store.category(work.id)?.color == .orange)
            #expect(store.category(life.id)?.color == life.color)
            #expect(Store(directory: dir).categories == store.categories)
        }
    }

    @Test("换成一个已经被别的分类占着的颜色也允许")
    func recolorAllowsDuplicateColors() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))

            store.recolorCategory(work.id, to: life.color)

            #expect(store.category(work.id)?.color == life.color)
        }
    }

    @Test("把一个分类拖到靠前的那个身上，它就排到那个位置，顺序跨重启还在")
    func reorderPersists() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addCategory("生活")
            let ideas = try #require(store.addCategory("想做的事"))

            store.moveCategory(ideas.id, onto: work.id)

            #expect(store.categories.map(\.name) == ["想做的事", "工作", "生活"])
            #expect(Store(directory: dir).categories.map(\.name) == ["想做的事", "工作", "生活"])
        }
    }

    @Test("往后拖也是落到那个位置上，别的分类依次让开")
    func reorderBackwards() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addCategory("生活")
            let ideas = try #require(store.addCategory("想做的事"))

            store.moveCategory(work.id, onto: ideas.id)

            #expect(store.categories.map(\.name) == ["生活", "想做的事", "工作"])
        }
    }

    @Test("拖到它自己身上、或者两头有一个不存在，都什么也不发生")
    func reorderIgnoresNonsense() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addCategory("生活")
            let before = store.categories

            store.moveCategory(work.id, onto: work.id)
            store.moveCategory(work.id, onto: UUID())
            store.moveCategory(UUID(), onto: work.id)

            #expect(store.categories == before)
        }
    }

    @Test("改名、换色、排序都认不出不存在的分类")
    func editingIgnoresUnknownCategories() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let before = store.categories

            store.renameCategory(UUID(), to: "上班")
            store.recolorCategory(UUID(), to: .orange)
            store.moveCategory(UUID(), onto: work.id)

            #expect(store.categories == before)
        }
    }

    @Test("「移到分类」列的是除它自己之外的分类")
    func moveTargetsExcludeTheTodosOwnCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addCategory("生活")
            store.addCategory("想做的事")

            #expect(store.categories(besides: work.id).map(\.name) == ["生活", "想做的事"])
        }
    }
}

@MainActor
@Suite("删除分类")
struct CategoryDeletionTests {
    @Test("空分类直接删掉")
    func emptyCategoryIsDeleted() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))

            #expect(store.deleteCategory(work.id) == .deleted)

            #expect(store.categories == [life])
            #expect(Store(directory: dir).categories == [life])
        }
    }

    @Test("还装着待办的分类拒绝删除，分类与待办都不受影响")
    func nonEmptyCategoryIsRefused() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            let categoriesBefore = store.categories
            let todosBefore = store.todos

            #expect(store.deleteCategory(work.id) == .refused(todoCount: 1))

            #expect(store.categories == categoriesBefore)
            #expect(store.todos == todosBefore)
            // 落盘的那份也一样没动过。时刻落盘时截到秒，所以这儿比身份不比整条。
            let reopened = Store(directory: dir)
            #expect(reopened.categories == categoriesBefore)
            #expect(reopened.todos.map(\.id) == todosBefore.map(\.id))
            #expect(reopened.todos.map(\.categoryID) == todosBefore.map(\.categoryID))
        }
    }

    @Test("只剩已完成的待办也照样拒绝删除")
    func finishedTodosAlsoRefuseDeletion() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            store.toggleTodo(try #require(store.todos.first))

            #expect(store.deleteCategory(work.id) == .refused(todoCount: 1))
            #expect(store.categories.count == 1)
            #expect(store.todos.count == 1)
        }
    }

    @Test("拒绝时带回里头有多少条待办 —— 提示要说的就是这个数")
    func refusalCarriesTheTodoCount() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)
            store.addTodo("交周报", in: work.id)
            store.addTodo("买菜", in: life.id)

            #expect(store.deleteCategory(work.id) == .refused(todoCount: 2))
        }
    }

    @Test("把待办全部移走之后，这个分类就可以删了")
    func emptiedCategoryBecomesDeletable() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)

            #expect(store.deleteCategory(work.id) == .refused(todoCount: 1))

            store.moveTodo(try #require(store.todos.first), to: life.id)

            #expect(store.deleteCategory(work.id) == .deleted)
            #expect(store.categories == [life])
            #expect(store.todos.map(\.categoryID) == [life.id])
        }
    }

    @Test("把待办删光之后，这个分类也可以删了")
    func categoryEmptiedByDeletingTodosIsDeletable() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)

            store.deleteTodo(try #require(store.todos.first))

            #expect(store.deleteCategory(work.id) == .deleted)
            #expect(store.categories.isEmpty)
        }
    }

    @Test("删掉最后一个分类是允许的，删完就回到一个分类都没有的状态")
    func deletingTheLastCategoryIsAllowed() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))

            #expect(store.deleteCategory(work.id) == .deleted)

            #expect(store.categories.isEmpty)
            #expect(store.recordingCategory == nil)
            #expect(Store(directory: dir).categories.isEmpty)
        }
    }

    @Test("删掉正选着记事的那个分类，记事的分类落回还在的那个")
    func deletingTheRecordingCategoryFallsBack() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.chooseRecordingCategory(life.id)

            #expect(store.deleteCategory(life.id) == .deleted)
            #expect(store.recordingCategory == work)
        }
    }

    @Test("删一个不存在的分类什么也不发生")
    func deletingAnUnknownCategoryDoesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("工作")
            let before = store.categories

            #expect(store.deleteCategory(UUID()) == .noSuchCategory)
            #expect(store.categories == before)
        }
    }
}

@MainActor
@Suite("待办改分类")
struct MoveTodoTests {
    @Test("改分类只改归属：计划日、创建日、完成日与完成状态都不变")
    func movingChangesOnlyTheCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            try schedule("写周报", in: work, on: try day(2026, 3, 4), store)
            store.toggleTodo(try #require(store.todos.first))
            let before = try #require(store.todos.first)

            store.moveTodo(before, to: life.id)

            let after = try #require(store.todos.first)
            #expect(after.categoryID == life.id)
            #expect(after.id == before.id)
            #expect(after.text == before.text)
            #expect(after.plannedOn == before.plannedOn)
            #expect(after.createdAt == before.createdAt)
            #expect(after.completedAt == before.completedAt)
            #expect(after.done == before.done)
        }
    }

    @Test("改分类之后待办出现在新分类的两列里，不再出现在旧分类里")
    func movedTodoShowsUpInTheNewCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)

            store.moveTodo(try #require(store.todos.first), to: life.id)

            #expect(store.columns(in: work.id).isEmpty)
            #expect(store.columns(in: life.id).unfinished.map(\.text) == ["写周报"])
        }
    }

    @Test("新的归属跨重启还在")
    func movePersists() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))
            store.addTodo("写周报", in: work.id)

            store.moveTodo(try #require(store.todos.first), to: life.id)

            #expect(Store(directory: dir).todos.map(\.categoryID) == [life.id])
        }
    }

    @Test("移到一个不存在的分类什么也不发生，待办留在原处")
    func movingToAnUnknownCategoryDoesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            let before = store.todos

            store.moveTodo(try #require(store.todos.first), to: UUID())

            #expect(store.todos == before)
        }
    }

    @Test("移到它已经在的那个分类什么也不变")
    func movingToItsOwnCategoryIsANoop() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("写周报", in: work.id)
            let before = store.todos

            store.moveTodo(try #require(store.todos.first), to: work.id)

            #expect(store.todos == before)
        }
    }
}
