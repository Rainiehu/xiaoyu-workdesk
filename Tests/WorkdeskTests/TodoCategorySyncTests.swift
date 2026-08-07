import CloudKit
import Foundation
import Testing

@testable import Workdesk

/// 把账本清空：欠的保存全当送达，墓碑全当撤掉。
/// 记账的测试靠它先把场地扫干净，之后账上出现什么就全是那一步操作记下的。
@MainActor
private func settleAll(_ store: Store) {
    for entry in store.syncLog.pendingSaves { store.settleSyncSave(recordName: entry.recordName) }
    for entry in store.syncLog.tombstones { store.settleSyncDelete(recordName: entry.recordName) }
}

/// 待办与分类的记账：本地每一处增删改都得在账本上留一笔，云端才有得结。
@MainActor
@Suite("TodoCategoryLedger")
struct TodoCategoryLedgerTests {
    @Test("新建分类与记待办各记一笔待发的保存")
    func addingLogsPendingSaves() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            #expect(store.syncLog.pendingSaves == [category.changeEntry])

            store.addTodo("写周报", in: category.id)
            let todo = try #require(store.todos.first)
            #expect(store.syncLog.pendingSaves == [category.changeEntry, todo.changeEntry])
        }
    }

    @Test("打勾、改写、排期、改期、清排期，每一下都记账")
    func everyTodoEditLogsASave() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            store.addTodo("反复折腾的一条", in: category.id)
            let todo = try #require(store.todos.first)

            let edits: [(String, () -> Void)] = [
                ("打勾", { store.toggleTodo(todo) }),
                ("改写", { store.editTodo(todo, to: "改了说法") }),
                ("排期", { store.setPlannedDay(.now, for: todo) }),
                ("改期", { _ = store.reschedule(todo.id, to: .now.addingTimeInterval(86_400)) }),
                ("清排期", { store.clearPlannedDay(todo) }),
            ]
            for (name, edit) in edits {
                settleAll(store)
                edit()
                #expect(store.syncLog.pendingSaves == [todo.changeEntry], "\(name) 之后账上该有这一笔")
            }
        }
    }

    @Test("换分类记的是那条待办自己的账")
    func movingATodoLogsIt() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let from = try #require(store.addCategory("甲"))
            let to = try #require(store.addCategory("乙"))
            store.addTodo("要搬家的", in: from.id)
            let todo = try #require(store.todos.first)
            settleAll(store)

            store.moveTodo(todo, to: to.id)
            #expect(store.syncLog.pendingSaves == [todo.changeEntry])
        }
    }

    /// 拖一下重编整个分类的位置 —— 一批记录同时变脏，都得记（紧凑整数照旧，ADR-0002）。
    @Test("手拖顺序让整个分类都上账")
    func reorderingLogsTheWholeCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            store.addTodo("一", in: category.id)
            store.addTodo("二", in: category.id)
            store.addTodo("三", in: category.id)
            settleAll(store)

            let unfinished = store.columns(in: category.id).unfinished
            _ = store.reorderTodo(try #require(unfinished.last).id, onto: try #require(unfinished.first).id)
            #expect(Set(store.syncLog.pendingSaves) == Set(store.todos.map(\.changeEntry)))
        }
    }

    @Test("删待办立起墓碑并勾销欠着的保存")
    func deletingATodoLogsATombstone() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            store.addTodo("要删的", in: category.id)
            let todo = try #require(store.todos.first)

            store.deleteTodo(todo)
            #expect(!store.syncLog.pendingSaves.contains(todo.changeEntry))
            #expect(store.syncLog.isTombstoned(todo.changeEntry))
        }
    }

    @Test("改名与换色各记一笔分类的账")
    func categoryEditsLogSaves() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("原名"))
            settleAll(store)

            store.renameCategory(category.id, to: "新名")
            #expect(store.syncLog.pendingSaves == [category.changeEntry])

            settleAll(store)
            store.recolorCategory(category.id, to: .pink)
            #expect(store.syncLog.pendingSaves == [category.changeEntry])
        }
    }

    /// 位置在云端是每条分类记录自己的字段 —— 一挪，两头之间的都变了，都得记。
    @Test("挪分类把两头之间的都记上账")
    func movingACategoryLogsTheShiftedOnes() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let a = try #require(store.addCategory("甲"))
            let b = try #require(store.addCategory("乙"))
            let c = try #require(store.addCategory("丙"))
            let d = try #require(store.addCategory("丁"))
            settleAll(store)

            // 丙挪到甲的位置上：甲、乙、丙都换了位置，丁没动。
            store.moveCategory(c.id, onto: a.id)
            #expect(Set(store.syncLog.pendingSaves) == Set([a, b, c].map(\.changeEntry)))
            #expect(!store.syncLog.pendingSaves.contains(d.changeEntry))
        }
    }

    @Test("删分类立墓碑，身后的分类因位置前移一并上账")
    func deletingACategoryLogsTombstoneAndShifts() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let a = try #require(store.addCategory("甲"))
            let b = try #require(store.addCategory("乙"))
            let c = try #require(store.addCategory("丙"))
            settleAll(store)

            #expect(store.deleteCategory(b.id) == .deleted)
            #expect(store.syncLog.isTombstoned(b.changeEntry))
            #expect(Set(store.syncLog.pendingSaves) == [c.changeEntry])
            #expect(!store.syncLog.pendingSaves.contains(a.changeEntry))
        }
    }

    @Test("删不掉的分类一笔账也不记")
    func refusedDeletionLogsNothing() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("非空"))
            store.addTodo("还在里头", in: category.id)
            settleAll(store)

            #expect(store.deleteCategory(category.id) == .refused(todoCount: 1))
            #expect(store.syncLog.isEmpty)
        }
    }

    /// 偏好不同步 —— 选哪个分类记事是这台机器自己的习惯，一个字节也不上云。
    @Test("选记事分类不记账")
    func preferencesStayOffTheBooks() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            settleAll(store)

            store.chooseRecordingCategory(category.id)
            #expect(store.syncLog.isEmpty)
        }
    }

    /// 存量数据首次上云走的就是这一笔补记 —— 分类、待办、收藏，一条不丢。
    @Test("首次接上云端时存量待办与分类全数记账")
    func backfillCoversTodosAndCategories() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("存量"))
            store.addTodo("老待办一", in: category.id)
            store.addTodo("老待办二", in: category.id)
            store.addFavorite("老收藏")
            settleAll(store)
            #expect(store.syncLog.isEmpty)

            store.enqueueAllForSync()
            let expected = [category.changeEntry]
                + store.todos.map(\.changeEntry)
                + store.favorites.map(\.changeEntry)
            #expect(Set(store.syncLog.pendingSaves) == Set(expected))
        }
    }

    @Test("引擎按名字取货，待办与分类都取得着，分类还带着位置")
    func recordLookupByName() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let a = try #require(store.addCategory("甲"))
            let b = try #require(store.addCategory("乙"))
            store.addTodo("在的", in: a.id)
            let todo = try #require(store.todos.first)

            #expect(store.todo(recordName: todo.recordName)?.id == todo.id)
            #expect(store.category(recordName: b.recordName)?.position == 1)
            #expect(store.category(recordName: b.recordName)?.category.id == b.id)
            #expect(store.todo(recordName: UUID().uuidString) == nil)
            #expect(store.category(recordName: "不是 UUID") == nil)
        }
    }
}

/// 云端改动的落地：本地没动过的整条照收，待办必须归属存在的分类 ——
/// 分类还没到的先候着，一条不丢。两边同时改同一条的合并另有一套测试（ConflictRuleTests）。
@MainActor
@Suite("RemoteTodoCategoryLanding")
struct RemoteTodoCategoryLandingTests {
    /// 抓取不保证次序，落地的次序由 `CloudSync.landingOrder` 摆正：
    /// 分类先于待办、分类之间按位置从小到大 —— 于是逐条「插到第几位」插完就是那一排，
    /// 待办落地时它的分类也已经在了。
    @Test("一批抓来的记录不论次序，摆正后铺出同一排 tab")
    func fetchedBatchLandsInPositionOrder() throws {
        let a = Workdesk.Category(name: "甲", color: .teal)
        let b = Workdesk.Category(name: "乙", color: .orange)
        let c = Workdesk.Category(name: "丙", color: .indigo)
        var todo = TodoItem(text: "夹在中间的待办", categoryID: b.id)
        todo.order = 0
        let arrivals = [[0, 1, 2], [2, 1, 0], [1, 2, 0], [2, 0, 1], [0, 2, 1], [1, 0, 2]]
        for order in arrivals {
            try withTemporaryDirectory { dir in
                let store = Store(directory: dir)
                var batch = order.map { i in [a, b, c][i].makeRecord(position: i) }
                batch.insert(todo.makeRecord(), at: 1)

                for record in CloudSync.landingOrder(batch) {
                    switch record.recordType {
                    case SyncSchema.categoryType:
                        let category = Workdesk.Category(record: record)
                        store.applyRemoteCategory(
                            try #require(category), position: Workdesk.Category.position(in: record)
                        )
                    case SyncSchema.todoType:
                        store.applyRemoteTodo(try #require(TodoItem(record: record)))
                    default:
                        break
                    }
                }
                #expect(store.categories.map(\.id) == [a.id, b.id, c.id], "到达次序 \(order)")
                // 待办哪怕排在批头也落得下去 —— 它的分类被摆到了前头。
                #expect(store.todos.map(\.id) == [todo.id])
                #expect(store.orphanTodos.isEmpty)
            }
        }
    }

    @Test("本地没动过的分类，云端来了新版本就整条换掉：名字、颜色、位置一起")
    func remoteCategoryReplacesWholesale() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("原名"))
            _ = try #require(store.addCategory("陪衬"))
            // 账清了 —— 本地没有欠着的改动，云端的版本就是唯一说了算的版本。
            settleAll(store)

            var renamed = category
            renamed.name = "云端改的名"
            renamed.color = .pink
            store.applyRemoteCategory(renamed, position: 1)

            #expect(store.categories.map(\.name) == ["陪衬", "云端改的名"])
            #expect(store.categories.last?.color == .pink)
            #expect(store.categories.count == 2)
        }
    }

    /// 两台各自建过同名分类：UUID 不串，就是两个分类 —— 并集里并存，不做自动合并。
    @Test("同名分类并存为两个 tab")
    func sameNameCategoriesCoexist() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let mine = try #require(store.addCategory("工作"))
            let theirs = Workdesk.Category(name: "工作", color: .blue)
            store.applyRemoteCategory(theirs, position: 1)

            #expect(store.categories.count == 2)
            #expect(Set(store.categories.map(\.id)) == [mine.id, theirs.id])
        }
    }

    @Test("云端来的改动不是欠账，一笔也不记")
    func remoteChangesStayOffTheBooks() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = Workdesk.Category(name: "云端建的", color: .teal)
            store.applyRemoteCategory(category, position: 0)
            var todo = TodoItem(text: "云端记的", categoryID: category.id)
            todo.order = 0
            store.applyRemoteTodo(todo)
            #expect(store.syncLog.isEmpty)
        }
    }

    @Test("墓碑拦下迟到的云端分类保存")
    func tombstoneBlocksLateCategorySave() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("要删的"))
            #expect(store.deleteCategory(category.id) == .deleted)

            store.applyRemoteCategory(category, position: 0)
            #expect(store.categories.isEmpty)
        }
    }

    /// 非空分类删不掉，云端来的删除也一样 —— 先守住「每条待办都有归属」，裁决是 #36 的事。
    @Test("云端删非空分类被拒，删空分类落地")
    func remoteCategoryDeletionRespectsNonEmptyRule() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let full = try #require(store.addCategory("非空"))
            let empty = try #require(store.addCategory("空的"))
            store.addTodo("占着", in: full.id)

            store.applyRemoteCategoryDeletion(recordName: full.recordName)
            #expect(store.categories.map(\.id).contains(full.id))

            store.applyRemoteCategoryDeletion(recordName: empty.recordName)
            #expect(!store.categories.map(\.id).contains(empty.id))
        }
    }

    @Test("云端来的待办按创建时刻插进数组，轴上同一天的先后两台一致")
    func remoteTodoLandsInChronologicalPlace() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            store.addTodo("本机先记的", in: category.id)
            store.addTodo("本机后记的", in: category.id)

            var early = TodoItem(text: "云端更早记的", categoryID: category.id)
            early.createdAt = .distantPast
            store.applyRemoteTodo(early)

            #expect(store.todos.map(\.text) == ["云端更早记的", "本机先记的", "本机后记的"])
        }
    }

    @Test("本地没动过的待办，云端来了新版本就整条换掉")
    func remoteTodoReplacesWholesale() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            store.addTodo("原来的说法", in: category.id)
            let mine = try #require(store.todos.first)
            // 账清了 —— 本地没有欠着的改动，云端的版本就是唯一说了算的版本。
            settleAll(store)

            var theirs = mine
            theirs.text = "云端改的说法"
            theirs.done = true
            theirs.completedAt = .now
            store.applyRemoteTodo(theirs)

            #expect(store.todos == [theirs])
        }
    }

    @Test("墓碑拦下迟到的云端待办保存")
    func tombstoneBlocksLateTodoSave() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            store.addTodo("要删的", in: category.id)
            let todo = try #require(store.todos.first)
            store.deleteTodo(todo)

            store.applyRemoteTodo(todo)
            #expect(store.todos.isEmpty)
        }
    }

    @Test("云端的删除落回本机，先后删同一条不是错")
    func remoteTodoDeletionLandsLocally() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = try #require(store.addCategory("工作"))
            store.addTodo("云端要删的", in: category.id)
            let todo = try #require(store.todos.first)

            store.applyRemoteTodoDeletion(recordName: todo.recordName)
            #expect(store.todos.isEmpty)
            store.applyRemoteTodoDeletion(recordName: todo.recordName)
            #expect(store.todos.isEmpty)
        }
    }

    // MARK: - 孤儿待办：分类还没到

    @Test("待办先到就候着不露面，分类到了再落地")
    func orphanWaitsForItsCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = Workdesk.Category(name: "还在路上", color: .teal)
            var todo = TodoItem(text: "先到的", categoryID: category.id)
            todo.order = 0

            store.applyRemoteTodo(todo)
            #expect(store.todos.isEmpty)
            #expect(store.orphanTodos == [todo])

            store.applyRemoteCategory(category, position: 0)
            #expect(store.todos == [todo])
            #expect(store.orphanTodos.isEmpty)
        }
    }

    /// 分类可能等到下次启动才来 —— 候着的不能跟着重启丢了。
    @Test("候着的待办随数据落盘，重启回来还在等")
    func orphansSurviveRelaunch() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let category = Workdesk.Category(name: "还在路上", color: .teal)
            var todo = TodoItem(text: "先到的", categoryID: category.id)
            todo.order = 0
            store.applyRemoteTodo(todo)

            // 认身份不认整条 —— 时刻经 JSON 落盘会掉小数位，那是存储精度，不是数据变了。
            let reopened = Store(directory: dir)
            #expect(reopened.orphanTodos.map(\.id) == [todo.id])
            reopened.applyRemoteCategory(category, position: 0)
            #expect(reopened.todos.map(\.id) == [todo.id])
            #expect(reopened.orphanTodos.isEmpty)
        }
    }

    @Test("云端把本地的待办挪进还没到的分类：旧版留着可用，分类到了换成新版")
    func moveIntoUnknownCategoryKeepsLocalUntilItArrives() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let here = try #require(store.addCategory("本地有的"))
            store.addTodo("被挪走的", in: here.id)
            let mine = try #require(store.todos.first)
            // 账清了 —— 这条测试说的是时序（分类晚到），不是冲突（本地并没有在改它）。
            settleAll(store)

            let elsewhere = Workdesk.Category(name: "还在路上", color: .blue)
            var theirs = mine
            theirs.categoryID = elsewhere.id
            store.applyRemoteTodo(theirs)
            // 分类还没到，本地这份先照旧 —— 界面上不许出现无归属的待办，也不该凭空少一条。
            #expect(store.todos == [mine])

            store.applyRemoteCategory(elsewhere, position: 1)
            #expect(store.todos == [theirs])
        }
    }

    @Test("云端删掉还在候着的待办，它就不再等了")
    func remoteDeletionAlsoClearsOrphans() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            var todo = TodoItem(text: "等不到了", categoryID: UUID())
            todo.order = 0
            store.applyRemoteTodo(todo)
            #expect(store.orphanTodos == [todo])

            store.applyRemoteTodoDeletion(recordName: todo.recordName)
            #expect(store.orphanTodos.isEmpty)
        }
    }
}

/// 待办与分类的 CKRecord 打包解包。全程不碰真实的 CloudKit 服务 ——
/// `CKRecord` 只是个数据结构，往返在本地就测得了。
@Suite("TodoCategoryRecords")
struct TodoCategoryRecordTests {
    @Test("待办打包成记录再解回来，一个字段也不少")
    func todoRecordRoundTrip() throws {
        var item = TodoItem(text: "全须全尾的一条", categoryID: UUID())
        item.done = true
        item.completedAt = .now
        item.plannedOn = try day(2026, 8, 7)
        item.order = 3

        let record = item.makeRecord()
        #expect(record.recordID.recordName == item.id.uuidString)
        #expect(record.recordID.zoneID == SyncSchema.zoneID)
        #expect(TodoItem(record: record) == item)
    }

    @Test("可空的字段空着也打得回来")
    func todoRecordRoundTripWithNils() throws {
        var item = TodoItem(text: "没排期没完成", categoryID: UUID())
        item.order = 0
        let back = try #require(TodoItem(record: item.makeRecord()))
        #expect(back == item)
        #expect(back.plannedOn == nil)
        #expect(back.completedAt == nil)
    }

    /// 改一条云端已有的记录要打在带系统字段的底子上 —— 底子上的旧值得被冲干净，
    /// 取消排期、取消打勾靠的就是这一冲。
    @Test("打在旧底子上：身份不变，旧值冲净")
    func packingOntoABaseClearsStaleFields() throws {
        var item = TodoItem(text: "排过期的", categoryID: UUID())
        item.plannedOn = .now
        item.order = 0
        let base = item.makeRecord()

        item.plannedOn = nil
        item.text = "又清了排期的"
        let repacked = item.makeRecord(onto: base)
        #expect(repacked === base)
        #expect(TodoItem(record: repacked) == item)
        #expect(repacked["plannedOn"] == nil)
    }

    /// 不是这个 app 写上去的东西，装作没看见比硬凑一条强。
    @Test("残缺或陌生的记录解不出待办")
    func malformedTodoRecordsAreRejected() {
        func record(type: String = SyncSchema.todoType, name: String = UUID().uuidString) -> CKRecord {
            CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: SyncSchema.zoneID))
        }
        #expect(TodoItem(record: record(type: "Stranger")) == nil)

        let noText = record()
        noText["categoryID"] = UUID().uuidString
        #expect(TodoItem(record: noText) == nil)

        let noCategory = record()
        noCategory["text"] = "没归属"
        #expect(TodoItem(record: noCategory) == nil)

        let oddCategory = record()
        oddCategory["text"] = "归属不是 UUID"
        oddCategory["categoryID"] = "不是 UUID"
        #expect(TodoItem(record: oddCategory) == nil)

        let oddName = record(name: "不是 UUID")
        oddName["text"] = "名字不是 UUID"
        oddName["categoryID"] = UUID().uuidString
        #expect(TodoItem(record: oddName) == nil)
    }

    @Test("分类打包成记录再解回来，位置也在")
    func categoryRecordRoundTrip() throws {
        let category = Workdesk.Category(name: "工作", color: .indigo)
        let record = category.makeRecord(position: 4)
        #expect(record.recordID.recordName == category.id.uuidString)
        #expect(Workdesk.Category(record: record) == category)
        #expect(Workdesk.Category.position(in: record) == 4)
    }

    /// 更新的版本也许添了新颜色 —— 丢整个分类会连坐一串待办，颜色不对只是颜色不对。
    @Test("认不出的色名落到石墨色，分类本身不丢")
    func unknownColorFallsBackToSlate() throws {
        let record = Workdesk.Category(name: "来自未来", color: .teal).makeRecord(position: 0)
        record["color"] = "hologram"
        // 先接住再 #require —— 类型名带模块前缀时，宏展开会在这个调用上绊倒。
        let decoded = Workdesk.Category(record: record)
        let back = try #require(decoded)
        #expect(back.color == .slate)
        #expect(back.name == "来自未来")
    }

    @Test("缺了位置的分类排到最后，缺了称呼的解不出")
    func categoryRecordEdges() {
        let record = Workdesk.Category(name: "没位置", color: .teal).makeRecord(position: 0)
        record["position"] = nil
        #expect(Workdesk.Category.position(in: record) == .max)

        let noName = CKRecord(
            recordType: SyncSchema.categoryType,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: SyncSchema.zoneID)
        )
        #expect(Workdesk.Category(record: noName) == nil)
    }

    /// 系统字段归档再解回来，身份还在 —— 引擎重启后照样打得回旧底子上。
    @Test("系统字段归档解档，记录的身份不丢")
    func systemFieldsRoundTrip() throws {
        var item = TodoItem(text: "有底子的", categoryID: UUID())
        item.order = 0
        let record = item.makeRecord()
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)

        let base = try #require(CloudSync.decodeSystemFields(archiver.encodedData))
        #expect(base.recordID == record.recordID)
        #expect(base.recordType == record.recordType)
        // 系统字段里不带业务字段 —— 那些每次都由 `makeRecord(onto:)` 重新赋。
        #expect(base["text"] == nil)
        #expect(TodoItem(record: item.makeRecord(onto: base)) == item)
    }
}
