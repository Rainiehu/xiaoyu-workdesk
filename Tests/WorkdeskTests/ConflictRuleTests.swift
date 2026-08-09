import Foundation
import Testing

@testable import WorkdeskCore

/// 把账本清空：欠的保存全当送达，墓碑全当撤掉。
/// 冲突的测试靠它先把「已同步」这个起点摆出来 —— 之后的改动才是冲突里的那一笔。
@MainActor
private func settleAll(_ store: Store) {
    for entry in store.syncLog.pendingSaves { store.settleSyncSave(recordName: entry.recordName) }
    for entry in store.syncLog.tombstones { store.settleSyncDelete(recordName: entry.recordName) }
}

/// 字段级合并的纯函数：影子、本地、服务端三方对比，本地改过的方面重放到服务端版上。
/// 全程不碰 `Store` 也不碰 CloudKit —— 规矩本身在这儿一条条钉死。
@Suite("SyncMerge")
struct SyncMergeTests {
    /// 三方的共同起点。
    private let base: TodoItem = {
        var item = TodoItem(text: "原稿", categoryID: UUID())
        item.order = 3
        return item
    }()

    @Test("一边改写正文、一边改期，两边都保住")
    func differentAspectsBothSurvive() throws {
        var mine = base
        mine.text = "本机改过的说法"
        var theirs = base
        theirs.plannedOn = try day(2026, 8, 20)

        // 谁后写根本不重要 —— 动的不是同一个方面，两个方向合出来都是同一条。
        for localIsLater in [true, false] {
            let merged = SyncMerge.todo(shadow: base, local: mine, remote: theirs, localIsLater: localIsLater)
            #expect(merged.text == "本机改过的说法")
            #expect(merged.plannedOn == theirs.plannedOn)
        }
    }

    @Test("同一个字段两边都改，后写的算")
    func sameAspectGoesToTheLaterWriter() {
        var mine = base
        mine.text = "本机的说法"
        var theirs = base
        theirs.text = "云端的说法"

        #expect(SyncMerge.todo(shadow: base, local: mine, remote: theirs, localIsLater: true).text == "本机的说法")
        #expect(SyncMerge.todo(shadow: base, local: mine, remote: theirs, localIsLater: false).text == "云端的说法")
    }

    /// 两台机器各自合并同一场冲突，交换视角（本地与远端互换、后写标志互补），
    /// 合出来的必须是同一条 —— 不然两边就永远收敛不到一起。
    @Test("交换视角合并，两台收敛到同一条")
    func mergingConvergesFromBothSides() throws {
        var mine = base
        mine.text = "本机的说法"
        mine.done = true
        mine.completedAt = .now
        var theirs = base
        theirs.text = "云端的说法"
        theirs.plannedOn = try day(2026, 9, 1)

        let seenFromA = SyncMerge.todo(shadow: base, local: mine, remote: theirs, localIsLater: false)
        let seenFromB = SyncMerge.todo(shadow: base, local: theirs, remote: mine, localIsLater: true)
        #expect(seenFromA == seenFromB)
        // 顺带钉死内容：正文云端后写胜，打勾与改期各自保住。
        #expect(seenFromA.text == "云端的说法")
        #expect(seenFromA.done)
        #expect(seenFromA.plannedOn == theirs.plannedOn)
    }

    /// 没影子就分不出谁改过 —— 凡不一致都交给后写胜，整体退化成 #35 的整条后写胜。
    @Test("没有影子时退化成整条后写胜")
    func withoutAShadowTheLaterWriterTakesAll() {
        var mine = base
        mine.text = "本机的说法"
        var theirs = base
        theirs.plannedOn = .now

        #expect(SyncMerge.todo(shadow: nil, local: mine, remote: theirs, localIsLater: true) == mine)
        #expect(SyncMerge.todo(shadow: nil, local: mine, remote: theirs, localIsLater: false) == theirs)
    }

    /// 打勾动的是 done 和 completedAt 两个字段 —— 合并不许把它们拆散，
    /// 不然会合出「打了勾却没有完成时刻」这种谁也没写过的状态。
    @Test("打勾与完成时刻同进同退")
    func completionMovesAsOnePiece() {
        var mine = base
        mine.done = true
        mine.completedAt = .now
        var theirs = base
        theirs.done = true
        theirs.completedAt = mine.completedAt?.addingTimeInterval(60)

        let merged = SyncMerge.todo(shadow: base, local: mine, remote: theirs, localIsLater: true)
        #expect(merged.done == mine.done)
        #expect(merged.completedAt == mine.completedAt)
    }

    /// 换分类必带新位置 —— 归属与位置是一个方面：本机把它挪去别的分类、
    /// 云端只在原分类里拖了位置，后写的那边说了算，不会合出「新分类 + 旧分类里的位置」。
    @Test("归属与位置同进同退")
    func placementMovesAsOnePiece() {
        var mine = base
        mine.categoryID = UUID()
        mine.order = 0
        var theirs = base
        theirs.order = 9

        let merged = SyncMerge.todo(shadow: base, local: mine, remote: theirs, localIsLater: false)
        #expect(merged.categoryID == theirs.categoryID)
        #expect(merged.order == 9)
    }

    @Test("一边改名、一边换色，分类两边都保住；位置相争后写胜")
    func categoryAspectsMergeIndependently() {
        let base = PlacedCategory(category: WorkdeskCore.Category(name: "原名", color: .teal), position: 1)
        var mine = base
        mine.category.name = "本机改的名"
        mine.position = 0
        var theirs = base
        theirs.category.color = .pink
        theirs.position = 3

        let merged = SyncMerge.category(shadow: base, local: mine, remote: theirs, localIsLater: false)
        #expect(merged.category.name == "本机改的名")
        #expect(merged.category.color == .pink)
        #expect(merged.position == 3)
    }
}

/// 三条裁决在 `Store` 里的落地：字段级合并、删除胜、分类复活。
/// 每个场景都从「两边已对齐」的起点出发 —— 账清了、影子对上了，之后的改动才是冲突。
@MainActor
@Suite("ConflictRules")
struct ConflictRuleTests {
    /// 摆出一条已与云端对齐的待办：记下、销账、影子对齐 —— 保存送达后的样子。
    private func synced(_ store: Store, text: String) throws -> TodoItem {
        let category = try #require(
            store.categories.first ?? store.addCategory("工作")
        )
        store.addTodo(text, in: category.id)
        let todo = try #require(store.todos.last)
        settleAll(store)
        store.alignShadow(todo: todo)
        return todo
    }

    // MARK: - 裁决一：字段级合并

    @Test("一边改写正文、一边改期同一条，合并后两个改动都在")
    func editAndRescheduleBothSurvive() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let todo = try #require(try synced(store, text: "原稿"))

            // 本机改写正文；另一台改了期，它那份先到了云端（写得还更晚）。
            store.editTodo(todo, to: "改过的说法")
            var theirs = todo
            theirs.plannedOn = try day(2026, 8, 20)
            store.applyRemoteTodo(theirs, modifiedAt: .distantFuture)

            let merged = try #require(store.todos.first)
            #expect(merged.text == "改过的说法")
            #expect(merged.plannedOn == theirs.plannedOn)
            // 本机的改动云端还没见过 —— 那笔账还挂着，合并结果会推上去。
            #expect(store.syncLog.pendingSaves.contains(todo.changeEntry))
        }
    }

    @Test("同一个字段两边都改，收敛为后写的那个")
    func sameFieldConvergesToTheLaterWrite() throws {
        // 云端写得晚，云端的算。
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let todo = try #require(try synced(store, text: "原稿"))
            store.editTodo(todo, to: "本机的说法")
            var theirs = todo
            theirs.text = "云端的说法"
            store.applyRemoteTodo(theirs, modifiedAt: .distantFuture)
            #expect(store.todos.first?.text == "云端的说法")
        }
        // 本机写得晚，本机的算 —— 挂着的账把它推回云端。
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let todo = try #require(try synced(store, text: "原稿"))
            store.editTodo(todo, to: "本机的说法")
            var theirs = todo
            theirs.text = "云端的说法"
            store.applyRemoteTodo(theirs, modifiedAt: .distantPast)
            #expect(store.todos.first?.text == "本机的说法")
            #expect(store.syncLog.pendingSaves.contains(todo.changeEntry))
        }
    }

    // MARK: - 裁决二：删待办对上改待办，删除胜

    @Test("一边删待办、一边改同一条，最终两边都没有这条")
    func deletionBeatsEditOnBothSides() throws {
        try withTemporaryDirectory { dirA in
            try withTemporaryDirectory { dirB in
                let a = Store(directory: dirA)
                let b = Store(directory: dirB)
                let todo = try #require(try synced(a, text: "两台都有的"))
                let category = try #require(a.categories.first)
                b.applyRemoteCategory(category, position: 0)
                b.applyRemoteTodo(todo)

                // A 删了它；B 同时在改它，账上欠着一笔保存。
                a.deleteTodo(todo)
                b.editTodo(todo, to: "还没送出去的改动")

                // B 的新版本到了 A：墓碑拦下，不复活。
                var theirs = todo
                theirs.text = "还没送出去的改动"
                a.applyRemoteTodo(theirs, modifiedAt: .distantFuture)
                #expect(a.todos.isEmpty)

                // A 的删除到了 B：本地欠着保存也照删 —— 删除是郑重的表态。
                b.applyRemoteTodoDeletion(recordName: todo.recordName)
                #expect(b.todos.isEmpty)
            }
        }
    }

    /// 票面钉死的时序：本地还欠着一笔保存时收到删除 —— 待办删掉之外，
    /// 那笔保存必须一并勾销，不然它会把这条待办在云端重新立起来。
    @Test("欠着保存时收到云端删除：待办删掉，欠账勾销，影子撤掉")
    func remoteDeletionSpendsThePendingSave() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let todo = try #require(try synced(store, text: "原稿"))
            store.editTodo(todo, to: "还没送出去的改动")
            #expect(store.syncLog.pendingSaves.contains(todo.changeEntry))

            store.applyRemoteTodoDeletion(recordName: todo.recordName)
            #expect(store.todos.isEmpty)
            #expect(store.syncLog.isEmpty)
            #expect(store.syncShadows.todo(named: todo.recordName) == nil)
        }
    }

    // MARK: - 裁决三：删分类对上往里记待办，待办胜、分类复活

    @Test("删掉的分类等来了云端的待办：带原名原色原位置复活，待办落在里面")
    func buriedCategoryRevivesForAnIncomingTodo() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            _ = try #require(store.addCategory("排前面的"))
            let category = try #require(store.addCategory("项目"))
            store.recolorCategory(category.id, to: .pink)
            settleAll(store)

            #expect(store.deleteCategory(category.id) == .deleted)
            // 删除已送达云端 —— 墓碑都撤了，殉葬品还得在。
            store.settleSyncDelete(recordName: category.recordName)

            // 另一台设备在删除送达前往里记了一条 —— 待办胜。
            var theirs = TodoItem(text: "另一台记下的", categoryID: category.id)
            theirs.order = 0
            store.applyRemoteTodo(theirs)

            let revived = try #require(store.categories.first { $0.id == category.id })
            #expect(revived.name == "项目")
            #expect(revived.color == .pink)
            #expect(store.categories.firstIndex(of: revived) == 1)
            #expect(store.todos.map(\.id) == [theirs.id])
            // 复活得说出去：云端已经没有（或快没有）这条分类了，本地是复活的一方。
            #expect(store.syncLog.pendingSaves.contains(category.changeEntry))
        }
    }

    @Test("删除还没送出去就等来了待办：墓碑撤掉，那笔删除不再发")
    func revivalLiftsAPendingTombstone() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("项目"))
            settleAll(store)
            #expect(store.deleteCategory(category.id) == .deleted)
            #expect(store.syncLog.isTombstoned(category.changeEntry))

            var theirs = TodoItem(text: "另一台记下的", categoryID: category.id)
            theirs.order = 0
            store.applyRemoteTodo(theirs)

            #expect(!store.syncLog.isTombstoned(category.changeEntry))
            #expect(store.syncLog.pendingSaves.contains(category.changeEntry))
            #expect(store.categories.map(\.id) == [category.id])
            #expect(store.todos.map(\.id) == [theirs.id])
        }
    }

    /// 冲突可能隔着一次重启才撞上 —— 殉葬品随数据落盘，回来还认得出。
    @Test("殉葬品跨重启还在，复活照样成立")
    func keepsakesSurviveRelaunch() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("项目"))
            settleAll(store)
            #expect(store.deleteCategory(category.id) == .deleted)

            let reopened = Store(directory: dir)
            var theirs = TodoItem(text: "另一台记下的", categoryID: category.id)
            theirs.order = 0
            reopened.applyRemoteTodo(theirs)

            #expect(reopened.categories.map(\.name) == ["项目"])
            #expect(reopened.todos.map(\.id) == [theirs.id])
        }
    }

    /// 反方向：云端删了分类、本地里头还有待办 —— 分类留下，并把复活推回云端。
    /// #35 只做到「拒收不动」；这儿把「说出去」补上，两边才不会就此各说各话。
    @Test("云端删非空分类：分类留下，并重新记账推回云端")
    func remoteDeletionOfANonEmptyCategoryIsPushedBack() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("非空"))
            store.addTodo("还在里头", in: category.id)
            settleAll(store)

            store.applyRemoteCategoryDeletion(recordName: category.recordName)
            #expect(store.categories.map(\.id) == [category.id])
            #expect(store.syncLog.pendingSaves.contains(category.changeEntry))
        }
    }

    /// 云端删空分类照删 —— 但殉葬品留下：归属它的待办可能从第三台设备晚一步到来。
    @Test("云端删掉的空分类也留殉葬品，晚到的待办仍能让它复活")
    func aRemotelyDeletedCategoryCanStillRevive() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("空的"))
            settleAll(store)

            store.applyRemoteCategoryDeletion(recordName: category.recordName)
            #expect(store.categories.isEmpty)

            var theirs = TodoItem(text: "晚到的", categoryID: category.id)
            theirs.order = 0
            store.applyRemoteTodo(theirs)
            #expect(store.categories.map(\.name) == ["空的"])
            #expect(store.todos.map(\.id) == [theirs.id])
        }
    }

    // MARK: - 影子的对齐时机

    /// 云端版本落地就是一次对齐：紧接着的本地改动，下一场冲突里分得清是本地改的。
    @Test("云端版本落地后影子跟上，下一场冲突照样合得对")
    func shadowsFollowRemoteLandings() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let todo = try #require(try synced(store, text: "原稿"))

            // 云端来了新版本（本地没动过，整条照收）—— 影子应当跟着它走。
            var theirs = todo
            theirs.text = "云端第一轮改的"
            store.applyRemoteTodo(theirs, modifiedAt: .now)

            // 本地在新版本上改期；云端又来一轮改写 —— 三方对比该认得出各自的改动。
            store.setPlannedDay(try day(2026, 8, 21), for: theirs)
            var another = theirs
            another.text = "云端第二轮改的"
            store.applyRemoteTodo(another, modifiedAt: .distantFuture)

            let merged = try #require(store.todos.first)
            #expect(merged.text == "云端第二轮改的")
            #expect(merged.plannedOn == (try day(2026, 8, 21)))
        }
    }
}
