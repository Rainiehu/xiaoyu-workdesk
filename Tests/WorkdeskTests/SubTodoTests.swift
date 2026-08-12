import Foundation
import Testing

@testable import WorkdeskCore

/// 子待办：父待办的内部结构（拆出来的步骤）。不排期、不上轴、不进未排期列，
/// 层级任意深；勾与父解耦；删父连子；升降级、换爹、入怀都是「挂到新位置」这一件事。
@MainActor
@Suite("子待办的树")
struct SubTodoTests {
    @Test("子待办生在兄弟末尾，跟着父的分类，没有计划日")
    func subTodosAppendInWritingOrder() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)

            store.addSubTodo("买配件", under: parent.id)
            store.addSubTodo("装系统", under: parent.id)
            store.addSubTodo("迁数据", under: parent.id)

            // 步骤按书写顺序 1、2、3 追加在尾 —— 与顶层「新记的落最上面」刻意不同。
            let steps = store.children(of: parent.id)
            #expect(steps.map(\.text) == ["买配件", "装系统", "迁数据"])
            #expect(steps.allSatisfy { $0.categoryID == work.id })
            #expect(steps.allSatisfy { $0.plannedOn == nil })
            // 再拆一层也一样。
            store.addSubTodo("挑内存", under: steps[0].id)
            #expect(store.children(of: steps[0].id).map(\.text) == ["挑内存"])
        }
    }

    @Test("死人不添孩子：父在删除态时 addSubTodo 什么也不发生")
    func noChildrenForTheDeleted() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.deleteTodo(parent)

            store.addSubTodo("买配件", under: parent.id)

            #expect(store.children(of: parent.id).isEmpty)
        }
    }

    @Test("进度只数直接子女的活人：孙辈不算、删除态不算、没孩子是 nil")
    func progressCountsDirectLivingChildren() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)
            store.addSubTodo("装系统", under: parent.id)
            let steps = store.children(of: parent.id)
            store.addSubTodo("挑内存", under: steps[0].id)
            store.toggleTodo(steps[0])

            #expect(store.childProgress(of: parent.id)! == (done: 1, total: 2))
            // 孙辈是下一层的进度，不掺在父的数里。
            #expect(store.childProgress(of: steps[0].id)! == (done: 0, total: 1))
            #expect(store.childProgress(of: steps[1].id) == nil)

            store.deleteTodo(steps[1])
            #expect(store.childProgress(of: parent.id)! == (done: 1, total: 1))
        }
    }

    @Test("勾是解耦的：子全勾完父不动，勾父子也不动")
    func checkmarksStayUncoupled() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)

            store.toggleTodo(try #require(store.children(of: parent.id).first))
            #expect(try #require(store.todos.first { $0.id == parent.id }).done == false)

            store.toggleTodo(try #require(store.todos.first { $0.id == parent.id }))
            let step = try #require(store.children(of: parent.id).first)
            #expect(step.done == true && step.completedAt != nil)
        }
    }

    @Test("子待办不上轴、不进未排期列、不进两列，徽标也不数它")
    func subTodosStayOffTheAxes() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let today = try day(2026, 8, 13)
            try schedule("装机", in: work, on: today, store)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)

            #expect(store.timeline(today: today).flatMap(\.todos).map(\.text) == ["装机"])
            #expect(store.unscheduled.isEmpty)
            let columns = store.columns(in: work.id)
            #expect(columns.unfinished.map(\.text) == ["装机"])
            #expect(columns.finished.isEmpty)
            #expect(store.unfinishedTodoCount == 1)
            // 但「非空分类删不掉」数的是每一条活着的记录 —— 步骤也是记录。
            store.deleteTodo(parent)
            store.undeleteTodo(parent.id)
            #expect(store.deleteCategory(work.id) == .refused(todoCount: 2))
        }
    }

    @Test("入怀落末子：整棵子树跟着走，排期顺手撤掉")
    func nestingJoinsAtTheEndAndLeavesTheAxis() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let today = try day(2026, 8, 13)
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("已有的一步", under: parent.id)
            try schedule("买配件", in: work, on: today, store)
            let joining = try #require(store.todos.first { $0.text == "买配件" })
            store.addSubTodo("挑内存", under: joining.id)

            #expect(store.nestTodo(joining.id, under: parent.id))

            #expect(store.children(of: parent.id).map(\.text) == ["已有的一步", "买配件"])
            let landed = try #require(store.todos.first { $0.id == joining.id })
            // 挂进怀里就离开轴：步骤不单独排期，轴上今天那组就此空了。
            #expect(landed.plannedOn == nil)
            #expect(store.timeline(today: today).flatMap(\.todos).isEmpty)
            // 名下的孙辈原样跟着。
            #expect(store.children(of: joining.id).map(\.text) == ["挑内存"])
        }
    }

    @Test("挂到自己肚子里不行：自己、子孙、删除态目标都不接")
    func nestingRefusesCyclesAndTheDeleted() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)
            let step = try #require(store.children(of: parent.id).first)

            #expect(!store.nestTodo(parent.id, under: parent.id))
            #expect(!store.nestTodo(parent.id, under: step.id))

            store.addTodo("另一件事", in: work.id)
            let other = try #require(store.todos.first { $0.text == "另一件事" })
            store.deleteTodo(other)
            #expect(!store.nestTodo(parent.id, under: other.id))
        }
    }

    @Test("入怀跨分类：整棵树换到新分类去")
    func nestingAcrossCategoriesCarriesTheTree() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let home = try #require(store.addCategory("家务"))
            store.addTodo("装机", in: work.id)
            let tree = try #require(store.todos.first)
            store.addSubTodo("买配件", under: tree.id)
            store.addTodo("大扫除", in: home.id)
            let host = try #require(store.todos.first { $0.text == "大扫除" })

            #expect(store.nestTodo(tree.id, under: host.id))

            #expect(store.todos.filter { $0.categoryID == home.id }.count == 3)
            #expect(store.todos.filter { $0.categoryID == work.id }.isEmpty)
        }
    }

    @Test("落缝当兄弟：顶层的缝就是升级的落点，位置落在目标前头")
    func gapDropsPlaceAsSiblings() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("乙", in: work.id)
            store.addTodo("甲", in: work.id)
            let jia = try #require(store.todos.first { $0.text == "甲" })
            let yi = try #require(store.todos.first { $0.text == "乙" })
            store.addSubTodo("步骤", under: jia.id)
            let step = try #require(store.children(of: jia.id).first)

            // 把子拖进顶层「甲乙」之间的缝：升级，落在乙前头。
            #expect(store.placeTodo(step.id, before: yi.id))
            #expect(store.columns(in: work.id).unfinished.map(\.text) == ["甲", "步骤", "乙"])
            #expect(try #require(store.todos.first { $0.id == step.id }).parentID == nil)

            // 再拖回子树的缝：降级，落在末尾那道缝只有「谁的后面」说得清。
            store.addSubTodo("先有的一步", under: jia.id)
            let anchor = try #require(store.children(of: jia.id).first)
            #expect(store.placeTodo(step.id, after: anchor.id))
            #expect(store.children(of: jia.id).map(\.text) == ["先有的一步", "步骤"])
        }
    }

    @Test("Tab 缩进挂到上一个兄弟名下，头一个兄弟缩不进去")
    func tabIndentsUnderThePreviousSibling() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("一", under: parent.id)
            store.addSubTodo("二", under: parent.id)
            let steps = store.children(of: parent.id)

            #expect(!store.indentTodo(steps[0].id))
            #expect(store.indentTodo(steps[1].id))
            #expect(store.children(of: parent.id).map(\.text) == ["一"])
            #expect(store.children(of: steps[0].id).map(\.text) == ["二"])
        }
    }

    @Test("Shift+Tab 升一级，站到父的旁边、紧跟在父后面")
    func shiftTabPromotesNextToTheParent() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("丙", in: work.id)
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first { $0.text == "装机" })
            store.addSubTodo("步骤", under: parent.id)
            let step = try #require(store.children(of: parent.id).first)

            #expect(store.promoteTodo(step.id))
            #expect(store.columns(in: work.id).unfinished.map(\.text) == ["装机", "步骤", "丙"])
            // 顶层没有再往上。
            #expect(!store.promoteTodo(parent.id))
        }
    }

    @Test("换分类只认根：整棵树一起走，子行上无此事")
    func movingCategoriesIsForRootsOnly() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let home = try #require(store.addCategory("家务"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)
            let step = try #require(store.children(of: parent.id).first)
            store.addSubTodo("挑内存", under: step.id)

            #expect(!store.moveTodo(step.id, to: home.id))
            #expect(store.moveTodo(parent.id, to: home.id))
            #expect(store.todos.allSatisfy { $0.categoryID == home.id })
            #expect(store.children(of: parent.id).map(\.text) == ["买配件"])
        }
    }

    @Test("换位置只在一窝兄弟里：跨窝的拖不动")
    func reorderingStaysWithinASiblingGroup() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("一", under: parent.id)
            store.addSubTodo("二", under: parent.id)
            let steps = store.children(of: parent.id)

            #expect(store.reorderTodo(steps[1].id, onto: steps[0].id))
            #expect(store.children(of: parent.id).map(\.text) == ["二", "一"])
            // 子与顶层不是一窝 —— 这一拖不该被解释成换位置。
            #expect(!store.reorderTodo(steps[0].id, onto: parent.id))
        }
    }

    @Test("删父连子：整棵树同一扇窗口，一起去一起回")
    func deletingAParentFellsAndRevivesTheWholeTree() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)
            let step = try #require(store.children(of: parent.id).first)
            store.addSubTodo("挑内存", under: step.id)

            store.deleteTodo(try #require(store.todos.first { $0.id == parent.id }))

            #expect(store.todos.allSatisfy { $0.isDeleted })
            #expect(store.pendingUndos.count == 1)

            store.undoLastDelete()
            #expect(store.todos.allSatisfy { !$0.isDeleted })
            #expect(store.children(of: parent.id).map(\.text) == ["买配件"])
            #expect(store.children(of: step.id).map(\.text) == ["挑内存"])
        }
    }

    @Test("先单独删掉的一步不搭父的车：各有各的窗口，各救各的")
    func separatelyDeletedStepsKeepTheirOwnWindows() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("先删的一步", under: parent.id)
            store.addSubTodo("留着的一步", under: parent.id)
            let doomed = try #require(store.children(of: parent.id).first)

            store.deleteTodo(doomed)
            store.deleteTodo(try #require(store.todos.first { $0.id == parent.id }))
            #expect(store.pendingUndos.count == 2)

            // 撤销父的删除：树回来了，先删的那步还躺着 —— 它有自己的时刻和窗口。
            store.undeleteTodo(parent.id)
            #expect(try #require(store.todos.first { $0.id == doomed.id }).isDeleted)
            #expect(store.children(of: parent.id).filter { !$0.isDeleted }.map(\.text) == ["留着的一步"])

            store.undeleteTodo(doomed.id)
            #expect(store.todos.allSatisfy { !$0.isDeleted })
        }
    }

    @Test("窗口关上整棵树沉进池子，重启回来还在")
    func expiryLowersTheWholeTreeIntoThePool() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)

            store.deleteTodo(try #require(store.todos.first { $0.id == parent.id }))
            closeUndoWindows(store)

            #expect(store.todos.isEmpty)
            #expect(Set(store.deletedTodos.map(\.text)) == ["装机", "买配件"])
            let reopened = Store(directory: dir)
            #expect(reopened.deletedTodos.count == 2)
        }
    }

    @Test("救活一步就得救活它的祖先链 —— 但不连带陪葬的兄弟")
    func revivingAStepRevivesItsAncestorsOnly() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("要救的一步", under: parent.id)
            store.addSubTodo("陪葬的一步", under: parent.id)
            let saved = try #require(store.children(of: parent.id).first)

            store.deleteTodo(try #require(store.todos.first { $0.id == parent.id }))
            store.undeleteTodo(saved.id)

            // 这一步和它的父都活了；陪葬的兄弟没人叫它，不回来。
            #expect(try #require(store.todos.first { $0.id == saved.id }).isDeleted == false)
            #expect(try #require(store.todos.first { $0.id == parent.id }).isDeleted == false)
            let other = try #require(store.todos.first { $0.text == "陪葬的一步" })
            #expect(other.isDeleted)
            // 窗口到点，剩下躺着的照样沉进池子，一个不漏。
            closeUndoWindows(store)
            #expect(store.deletedTodos.map(\.text) == ["陪葬的一步"])
        }
    }

    @Test("树的形状跨重启完好：父子关系与兄弟顺序都落在盘上")
    func theTreeSurvivesARestart() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)
            store.addSubTodo("装系统", under: parent.id)

            let reopened = Store(directory: dir)
            #expect(reopened.children(of: parent.id).map(\.text) == ["买配件", "装系统"])
        }
    }
}

/// 子待办与同步：挂靠是一个方面；孩子等父落地；子胜父复活；环自愈。
@MainActor
@Suite("子待办的同步")
struct SubTodoSyncTests {
    @Test("CloudKit 记录来回一趟，父子关系原样")
    func recordsCarryTheParentLink() throws {
        let categoryID = UUID()
        let parentID = UUID()
        let sub = TodoItem(text: "买配件", categoryID: categoryID, parentID: parentID)
        let restored = try #require(TodoItem(record: sub.makeRecord()))
        #expect(restored.parentID == parentID)
        let top = TodoItem(text: "装机", categoryID: categoryID)
        #expect(try #require(TodoItem(record: top.makeRecord())).parentID == nil)
    }

    @Test("一边改字、一边换爹：字段级合并两边都保住")
    func mergeKeepsEditsAndReparentsApart()  {
        let categoryID = UUID()
        let newParent = UUID()
        let shadow = TodoItem(text: "买配件", categoryID: categoryID, order: 3)
        var local = shadow
        local.text = "买齐配件"
        var remote = shadow
        remote.parentID = newParent
        remote.order = 0

        let merged = SyncMerge.todo(shadow: shadow, local: local, remote: remote, localIsLater: false)
        #expect(merged.text == "买齐配件")
        #expect(merged.parentID == newParent)
        #expect(merged.order == 0)
    }

    @Test("孩子先到就候着，父落地跟着落 —— 一层层接")
    func childrenWaitForTheirParents() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let parent = TodoItem(text: "装机", categoryID: work.id)
            let child = TodoItem(text: "买配件", categoryID: work.id, parentID: parent.id)
            let grandchild = TodoItem(text: "挑内存", categoryID: work.id, parentID: child.id)

            store.applyRemoteTodo(grandchild)
            store.applyRemoteTodo(child)
            #expect(store.todos.isEmpty)

            store.applyRemoteTodo(parent)
            #expect(store.todos.count == 3)
            #expect(store.children(of: parent.id).map(\.text) == ["买配件"])
            #expect(store.children(of: child.id).map(\.text) == ["挑内存"])
        }
    }

    @Test("这台删父、那台改子：子胜，祖先链复活")
    func aRemoteEditToAChildRevivesItsDeletedParent() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.addSubTodo("买配件", under: parent.id)
            let step = try #require(store.children(of: parent.id).first)

            store.deleteTodo(try #require(store.todos.first { $0.id == parent.id }))
            closeUndoWindows(store)
            // 账已结清：这台的删除已送达云端，那台后来改了子的字。
            store.settleSyncSave(recordName: parent.recordName)
            store.settleSyncSave(recordName: step.recordName)
            var edited = step
            edited.text = "买齐配件"
            store.applyRemoteTodo(edited, modifiedAt: .now)

            #expect(try #require(store.todos.first { $0.id == parent.id }).isDeleted == false)
            #expect(store.children(of: parent.id).map(\.text) == ["买齐配件"])
        }
    }

    @Test("这台往树里加子、那台删父：父的删除落不下来，复活记账推回云端")
    func aLocalNewChildBeatsARemoteParentDeletion() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.settleSyncSave(recordName: parent.recordName)
            store.addSubTodo("新想到的一步", under: parent.id)

            var remoteDeleted = parent
            remoteDeleted.deletedAt = .now
            store.applyRemoteTodo(remoteDeleted, modifiedAt: .now)

            let landed = try #require(store.todos.first { $0.id == parent.id })
            #expect(!landed.isDeleted)
            #expect(store.syncLog.pendingSaves.contains(parent.changeEntry))
        }
    }

    @Test("两台各把对方挂进怀里合出一个环：断在刚落地的这条，升它到顶层")
    func mergedCyclesHealByPromotion() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.addTodo("乙", in: work.id)
            store.addTodo("甲", in: work.id)
            let jia = try #require(store.todos.first { $0.text == "甲" })
            let yi = try #require(store.todos.first { $0.text == "乙" })
            // 这台把乙挂进甲；那台把甲挂进乙，它的版本随同步而来。
            store.nestTodo(yi.id, under: jia.id)
            store.settleSyncSave(recordName: jia.recordName)
            store.settleSyncSave(recordName: yi.recordName)
            var remoteJia = jia
            remoteJia.parentID = yi.id
            store.applyRemoteTodo(remoteJia, modifiedAt: .now)

            let landedJia = try #require(store.todos.first { $0.id == jia.id })
            let landedYi = try #require(store.todos.first { $0.id == yi.id })
            #expect(landedJia.parentID == nil)
            #expect(landedYi.parentID == jia.id)
            // 修补是本地的表态，得让云端也知道。
            #expect(store.syncLog.pendingSaves.contains(jia.changeEntry))
        }
    }

    @Test("子随根走：远端来的子带着陈旧的分类，落地时正过来")
    func staleChildCategoriesFollowTheRoot() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let home = try #require(store.addCategory("家务"))
            store.addTodo("装机", in: work.id)
            let parent = try #require(store.todos.first)
            store.moveTodo(parent.id, to: home.id)
            store.settleSyncSave(recordName: parent.recordName)

            // 那台还没看到换分类，往树里加了一步，记录带着旧分类到来。
            let stale = TodoItem(text: "买配件", categoryID: work.id, parentID: parent.id)
            store.applyRemoteTodo(stale)

            let landed = try #require(store.todos.first { $0.id == stale.id })
            #expect(landed.categoryID == home.id)
        }
    }
}
