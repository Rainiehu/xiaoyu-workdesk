import Foundation
import Testing

@testable import WorkdeskCore

/// 分类视图左列的小标题：手排顺序里的一道分界，它下面到下一个小标题之前的顶层待办就是这一节。
/// 见 ADR-0009。
@MainActor
@Suite("小标题")
struct HeadingTests {
    // MARK: - 新建

    @Test("在一行上方加小标题：先有行、后有字，它就站在那一行前头")
    func addingAHeadingAboveARow() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B", "C"], in: dir)

            let id = try #require(store.addHeading(before: try store.item("B").id))

            let heading = try #require(store.todos.first { $0.id == id })
            #expect(heading.isHeading)
            #expect(heading.text.isEmpty)
            store.editTodo(heading, to: "第二节")
            #expect(try store.leftColumn() == ["A", "#第二节", "B", "C"])
        }
    }

    @Test("在分类末尾加小标题：落在最后，包括已完成的后面")
    func addingAHeadingAtTheEnd() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A", "B"], in: dir)
            store.toggleTodo(try store.item("B"))

            let id = try #require(store.addHeading(in: try store.work().id))
            store.editTodo(try #require(store.todos.first { $0.id == id }), to: "以后")

            #expect(try store.leftColumn() == ["A", "#以后"])
            // 取消打勾的 B 回到原来那一节（小标题之上），不被新标题收进去。
            store.toggleTodo(try store.item("B"))
            #expect(try store.leftColumn() == ["A", "B", "#以后"])
        }
    }

    @Test("子待办上方加不了小标题")
    func headingsOnlyLiveAtTheTopLevel() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A"], in: dir)
            let step = try #require(store.addSubTodo("一步", under: try store.item("A").id))

            #expect(store.addHeading(before: step) == nil)
            #expect(store.todos.allSatisfy { !$0.isHeading })
        }
    }

    @Test("没写字就走的空标题悄悄收走")
    func anEmptyHeadingIsDiscarded() throws {
        try withTemporaryDirectory { dir in
            let store = try arranged(["A"], in: dir)
            let id = try #require(store.addHeading(before: try store.item("A").id))

            store.discardEmptyTodo(id)

            #expect(try store.leftColumn() == ["A"])
            #expect(store.pendingUndos.isEmpty)
        }
    }

    @Test("记事栏新记的落在第一个小标题之上")
    func newTodosLandAboveTheFirstHeading() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            store.addTodo("刚想到的", in: try store.work().id)

            #expect(try store.leftColumn() == ["刚想到的", "u", "#甲", "a1", "a2", "#乙", "b1"])
        }
    }

    // MARK: - 小标题不是待办

    @Test("小标题不进右列、不上轴、不进未排期列、不算徽标的数")
    func headingsStayOutOfEverythingButTheLeftColumn() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            let work = try store.work()

            #expect(store.columns(in: work.id).finished.isEmpty)
            #expect(store.unfinishedTodoCount == 4)
            #expect(store.unscheduled.flatMap(\.todos).allSatisfy { !$0.isHeading })
            #expect(store.timeline(today: .now).flatMap(\.todos).allSatisfy { !$0.isHeading })
        }
    }

    @Test("小标题打不了勾、排不了期、换不了分类、拆不出步骤")
    func aHeadingHasNoneOfTheTodoPowers() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            let life = try #require(store.addCategory("生活"))
            let heading = try store.item("甲")

            store.toggleTodo(heading)
            store.setPlannedDay(try day(2026, 3, 2), for: heading)
            #expect(!store.reschedule(heading.id, to: try day(2026, 3, 3)))
            #expect(!store.moveTodo(heading.id, to: life.id))
            #expect(store.addSubTodo("一步", under: heading.id) == nil)

            let after = try store.item("甲")
            #expect(!after.done && after.completedAt == nil && after.plannedOn == nil)
            #expect(after.categoryID == heading.categoryID)
            #expect(store.children(of: heading.id).isEmpty)
        }
    }

    @Test("小标题挂不到谁下面，谁也挂不到它下面")
    func headingsNeverNest() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            #expect(!store.nestTodo(try store.item("甲").id, under: try store.item("a1").id))
            // 小标题下的第一条按 Tab：上一个兄弟是小标题，缩不进去。
            #expect(!store.indentTodo(try store.item("a1").id))
            #expect(!store.indentTodo(try store.item("甲").id))
            #expect(store.todos.allSatisfy { $0.parentID == nil })
        }
    }

    // MARK: - 待办在节之间走动

    @Test("待办落在小标题身上，就成了这一节的第一条")
    func droppingATodoOntoAHeadingMakesItTheFirstOfThatSection() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            #expect(store.nestTodo(try store.item("u").id, under: try store.item("乙").id))

            #expect(try store.leftColumn() == ["#甲", "a1", "a2", "#乙", "u", "b1"])
            #expect(try store.item("u").parentID == nil)
        }
    }

    @Test("子待办落在小标题身上，升到顶层成为这一节的第一条")
    func droppingAStepOntoAHeadingPromotesIt() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            let step = try #require(store.addSubTodo("一步", under: try store.item("a1").id))

            #expect(store.nestTodo(step, under: try store.item("乙").id))

            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "一步", "b1"])
        }
    }

    @Test("拖着待办越过小标题，就换到了另一节")
    func reorderingATodoAcrossAHeadingChangesItsSection() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            // 往下越过「乙」：落在它后头，进了乙这一节。
            #expect(store.reorderTodo(try store.item("a2").id, onto: try store.item("乙").id))
            #expect(try store.leftColumn() == ["u", "#甲", "a1", "#乙", "a2", "b1"])

            // 往上越过「乙」：落在它前头，回到甲这一节。
            #expect(store.reorderTodo(try store.item("b1").id, onto: try store.item("乙").id))
            #expect(try store.leftColumn() == ["u", "#甲", "a1", "b1", "#乙", "a2"])
        }
    }

    // MARK: - 拖小标题，整节跟着走

    @Test("小标题落在另一个小标题身上，整节换到它的位置")
    func reorderingAHeadingMovesItsWholeSection() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            #expect(store.reorderTodo(try store.item("甲").id, onto: try store.item("乙").id))
            #expect(try store.leftColumn() == ["u", "#乙", "b1", "#甲", "a1", "a2"])

            #expect(store.reorderTodo(try store.item("甲").id, onto: try store.item("乙").id))
            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "b1"])
        }
    }

    @Test("整节一起走，已完成的也跟着走")
    func aMovingSectionTakesItsFinishedTodosAlong() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            store.toggleTodo(try store.item("a2"))

            #expect(store.reorderTodo(try store.item("甲").id, onto: try store.item("乙").id))
            store.toggleTodo(try store.item("a2"))

            #expect(try store.leftColumn() == ["u", "#乙", "b1", "#甲", "a1", "a2"])
        }
    }

    @Test("小标题往下落进别人那一节的半中间，就排到那一节后面")
    func aSectionDroppedDownIntoAnotherSnapsPastIt() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            store.addTodo("b2", in: try store.work().id)
            #expect(store.placeTodo(try store.item("b2").id, after: try store.item("b1").id))

            #expect(store.placeTodo(try store.item("甲").id, after: try store.item("b1").id))

            #expect(try store.leftColumn() == ["u", "#乙", "b1", "b2", "#甲", "a1", "a2"])
        }
    }

    @Test("小标题往上落进别人那一节的半中间，就排到那一节前面")
    func aSectionDroppedUpIntoAnotherSnapsBeforeIt() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            #expect(store.placeTodo(try store.item("乙").id, before: try store.item("a2").id))

            #expect(try store.leftColumn() == ["u", "#乙", "b1", "#甲", "a1", "a2"])
        }
    }

    @Test("顶上不带标题的那一块永远在最上面，小标题挤不到它上头去")
    func theUntitledTopStaysOnTop() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            #expect(store.placeTodo(try store.item("乙").id, before: try store.item("u").id))

            #expect(try store.leftColumn() == ["u", "#乙", "b1", "#甲", "a1", "a2"])
        }
    }

    @Test("小标题落进自己这一节里，原地不动")
    func droppingASectionIntoItselfDoesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            #expect(!store.placeTodo(try store.item("甲").id, after: try store.item("a1").id))
            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "b1"])
        }
    }

    @Test("小标题落不进子树：子树的缝、子行身上都不接")
    func aHeadingNeverLandsInsideATree() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            let step = try #require(store.addSubTodo("一步", under: try store.item("b1").id))

            #expect(!store.placeTodo(try store.item("甲").id, before: step))
            #expect(!store.nestTodo(try store.item("甲").id, under: step))
            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "b1"])
            #expect(store.children(of: try store.item("b1").id).map(\.text) == ["一步"])
        }
    }

    @Test("小标题落在顶层待办身上不入怀，当作挪到那一行的位置，整节吸到交界")
    func aHeadingDroppedOntoATodoMovesItsSection() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            #expect(store.nestTodo(try store.item("甲").id, under: try store.item("b1").id))

            #expect(try store.leftColumn() == ["u", "#乙", "b1", "#甲", "a1", "a2"])
            #expect(store.todos.allSatisfy { $0.parentID == nil })
        }
    }

    @Test("撤销窗口里的小标题不算分界：它那一节归上一节，跟着一起走，撤销时原位回来")
    func aDeletedHeadingTravelsWithTheSectionAbove() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            store.addTodo("c1", in: try store.work().id)
            #expect(store.placeTodo(try store.item("c1").id, after: try store.item("b1").id))
            let third = try #require(store.addHeading(before: try store.item("c1").id))
            store.editTodo(try #require(store.todos.first { $0.id == third }), to: "丙")
            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "b1", "#丙", "c1"])

            store.deleteTodo(try store.item("乙"))
            #expect(store.reorderTodo(try store.item("甲").id, onto: try store.item("丙").id))

            // 乙已不是分界，b1 此刻归甲；甲整节（连同还在窗口里的乙）挪到丙后头。
            #expect(try store.leftColumn() == ["u", "#丙", "c1", "#甲", "a1", "a2", "b1"])
            store.undoLastDelete()
            #expect(try store.leftColumn() == ["u", "#丙", "c1", "#甲", "a1", "a2", "#乙", "b1"])
        }
    }

    @Test("同步合出一个打了勾的小标题，它照旧站在左列，不从两列里一起消失")
    func aHeadingMarkedDoneStaysInTheLeftColumn() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            var heading = try store.item("甲")
            heading.done = true
            heading.completedAt = .now

            store.applyRemoteTodo(heading)

            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "b1"])
            #expect(store.columns(in: try store.work().id).finished.isEmpty)
        }
    }

    // MARK: - 删除

    @Test("删小标题只删这道分界：下面的待办一条不动，并入上一节")
    func deletingAHeadingKeepsItsTodos() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            store.deleteTodo(try store.item("乙"))
            closeUndoWindows(store)

            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "b1"])
        }
    }

    @Test("删掉的小标题撤销回来，原样回到原位")
    func undoingAHeadingDeletionPutsItBack() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)

            store.deleteTodo(try store.item("甲"))
            store.undoLastDelete()

            #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "b1"])
        }
    }

    @Test("里头只剩小标题的分类也删不掉，提示分开报待办与小标题")
    func headingsKeepACategoryFromBeingDeleted() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("A", in: work.id)
            _ = try #require(store.addHeading(in: work.id))
            store.editTodo(try #require(store.todos.first { $0.isHeading }), to: "一节")

            #expect(store.deleteCategory(work.id) == .refused(todoCount: 1, headingCount: 1))

            store.deleteTodo(try #require(store.todos.first { $0.text == "A" }))
            closeUndoWindows(store)
            #expect(store.deleteCategory(work.id) == .refused(todoCount: 0, headingCount: 1))
        }
    }

    // MARK: - 落盘与同步

    @Test("小标题跨重启还在；旧数据里的待办读回来仍是待办")
    func headingsSurviveARestart() throws {
        try withTemporaryDirectory { dir in
            let store = try sectioned(dir)
            let order = try store.leftColumn()

            let reopened = Store(directory: dir)
            #expect(try reopened.leftColumn() == order)
            #expect(reopened.todos.filter(\.isHeading).count == 2)

            // 待办行不写这个键 —— 旧客户端读得懂，新客户端读旧文件也不出错。
            let raw = try String(contentsOf: dir.appendingPathComponent("todos-v2.json"), encoding: .utf8)
            #expect(raw.components(separatedBy: "\"heading\"").count - 1 == 2)
        }
    }

    @Test("小标题记号随记录上云、从云端落回来")
    func theHeadingMarkRoundTripsThroughARecord() throws {
        let heading = TodoItem(text: "一节", categoryID: UUID(), order: 3, isHeading: true)
        let todo = TodoItem(text: "一件事", categoryID: UUID())

        #expect(try #require(TodoItem(record: heading.makeRecord())).isHeading)
        #expect(try #require(TodoItem(record: todo.makeRecord())).isHeading == false)
        #expect(TodoItem(record: heading.makeRecord()) == heading)
    }

    // MARK: - 搭台子

    /// 建一个分类，按交进来的先后记下几条待办。记事是新的在上，所以倒着记。
    private func arranged(_ texts: [String], in dir: URL) throws -> Store {
        let store = Store(directory: dir)
        let work = try #require(store.addCategory("工作"))
        for text in texts.reversed() {
            store.addTodo(text, in: work.id)
        }
        #expect(try store.leftColumn() == texts)
        return store
    }

    /// 一个分好节的分类：顶上一条不带标题的 u，然后是「甲」（a1、a2）与「乙」（b1）两节。
    private func sectioned(_ dir: URL) throws -> Store {
        let store = try arranged(["u", "a1", "a2", "b1"], in: dir)
        let first = try #require(store.addHeading(before: try store.item("a1").id))
        store.editTodo(try #require(store.todos.first { $0.id == first }), to: "甲")
        let second = try #require(store.addHeading(before: try store.item("b1").id))
        store.editTodo(try #require(store.todos.first { $0.id == second }), to: "乙")
        #expect(try store.leftColumn() == ["u", "#甲", "a1", "a2", "#乙", "b1"])
        return store
    }
}

@MainActor
extension Store {
    /// 唯一那个分类（测试里先建的那个）。
    fileprivate func work() throws -> WorkdeskCore.Category {
        try #require(categories.first)
    }

    /// 左列，小标题前面带个「#」好与待办分开。
    fileprivate func leftColumn() throws -> [String] {
        columns(in: try work().id).unfinished
            .filter { !$0.isDeleted }
            .map { $0.isHeading ? "#" + $0.text : $0.text }
    }

    /// 按正文找回一条（待办或小标题）。手里的副本会变旧，所以每次都现找。
    fileprivate func item(_ text: String) throws -> TodoItem {
        try #require(todos.first { $0.text == text })
    }
}
