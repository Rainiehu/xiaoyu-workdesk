import CloudKit
import Foundation
import Testing

@testable import WorkdeskCore

/// 归档：分类连同名下的一切从主线上撤下，只在档案里看得见；取回原样回来。
/// 待办一条不动 —— 撤下的只是「在哪儿露面」，见 ADR-0010。
@MainActor
@Suite("归档分类")
struct ArchiveTests {
    @Test("归档后不在主线上，进了档案；取回回到原来的位置")
    func archiveAndRetrieveKeepThePosition() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("工作")
            let trip = try #require(store.addCategory("旅行"))
            store.addCategory("读书")

            store.archiveCategory(trip.id)
            #expect(store.mainlineCategories.map(\.name) == ["工作", "读书"])
            #expect(store.archivedCategories.map(\.name) == ["旅行"])

            store.retrieveCategory(trip.id)
            #expect(store.mainlineCategories.map(\.name) == ["工作", "旅行", "读书"])
            #expect(store.archivedCategories.isEmpty)
        }
    }

    @Test("归档跨重启还在")
    func archivePersists() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let trip = try #require(store.addCategory("旅行"))
            store.archiveCategory(trip.id)

            let reopened = Store(directory: dir)
            #expect(reopened.archivedCategories.map(\.id) == [trip.id])
            #expect(reopened.mainlineCategories.isEmpty)
        }
    }

    @Test("档案按归档时间从新到旧")
    func archiveListsNewestFirst() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let a = try #require(store.addCategory("甲"))
            let b = try #require(store.addCategory("乙"))
            store.archiveCategory(a.id)
            store.archiveCategory(b.id)
            #expect(store.archivedCategories.map(\.name) == ["乙", "甲"])
        }
    }

    @Test("同一刻归档的按 tab 栏上的先后排，每次都是同一个顺序")
    func simultaneousArchivesKeepTabOrder() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let moment = Date(timeIntervalSince1970: 1_790_000_000)
            for (i, name) in ["甲", "乙", "丙"].enumerated() {
                let category = WorkdeskCore.Category(name: name, color: .teal, archivedAt: moment)
                store.applyRemoteCategory(category, position: i)
            }
            for _ in 0..<20 {
                #expect(store.archivedCategories.map(\.name) == ["甲", "乙", "丙"])
            }
        }
    }

    @Test("里头有没做完的也收得进去，待办一条不动")
    func archiveTakesUnfinishedTodosAlongUntouched() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let trip = try #require(store.addCategory("旅行"))
            try schedule("订机票", in: trip, on: try day(2026, 10, 30), store)
            store.addTodo("换日元", in: trip.id)
            let before = store.todos

            store.archiveCategory(trip.id)

            #expect(store.archivedCategories.map(\.id) == [trip.id])
            #expect(store.todos == before)
        }
    }

    @Test("归档分类的待办不上轴：做完的、没做完的都不上")
    func archivedTodosLeaveTheTimeline() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let trip = try #require(store.addCategory("旅行"))
            let today = try day(2026, 10, 23)
            try schedule("写周报", in: work, on: today, store)
            try schedule("订机票", in: trip, on: today, store)
            try schedule("换日元", in: trip, on: try day(2026, 10, 20), store)
            store.toggleTodo(try #require(store.todos.last))

            store.archiveCategory(trip.id)

            let onAxis = store.timeline(today: today).flatMap(\.todos).map(\.text)
            #expect(onAxis == ["写周报"])

            store.retrieveCategory(trip.id)
            let back = store.timeline(today: today).flatMap(\.todos).map(\.text)
            #expect(Set(back) == ["写周报", "订机票", "换日元"])
        }
    }

    @Test("归档分类不进未排期列，也不算徽标的数")
    func archivedTodosLeaveUnscheduledAndBadge() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let trip = try #require(store.addCategory("旅行"))
            store.addTodo("整理桌面", in: work.id)
            store.addTodo("整理照片", in: trip.id)
            #expect(store.unfinishedTodoCount == 2)

            store.archiveCategory(trip.id)

            #expect(store.unscheduled.map(\.category.id) == [work.id])
            #expect(store.unfinishedTodoCount == 1)
        }
    }

    @Test("归档的分类照样认得：分类视图打得开，往里记的事也留在档案里")
    func archivedCategoryStillOpensAndRecords() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let trip = try #require(store.addCategory("旅行"))
            store.archiveCategory(trip.id)

            #expect(store.category(trip.id)?.isArchived == true)
            store.addTodo("补一张发票", in: trip.id)
            #expect(store.columns(in: trip.id).unfinished.map(\.text) == ["补一张发票"])
            // 在档案里做的事留在档案里，不会让它自己回到 tab 栏上。
            #expect(store.archivedCategories.map(\.id) == [trip.id])
            #expect(store.unscheduled.isEmpty)
        }
    }

    @Test("记事的分类被归档就落回主线上的第一个，取回之后又认回它")
    func recordingCategoryFallsBackWhileArchived() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let trip = try #require(store.addCategory("旅行"))
            store.chooseRecordingCategory(trip.id)

            store.archiveCategory(trip.id)
            #expect(store.recordingCategory?.id == work.id)

            store.retrieveCategory(trip.id)
            #expect(store.recordingCategory?.id == trip.id)
        }
    }

    @Test("选不了归档的分类来记事；主线上一个都不剩就无处记")
    func cannotRecordIntoTheArchiveFromTheTimeline() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let trip = try #require(store.addCategory("旅行"))
            store.archiveCategory(trip.id)

            store.chooseRecordingCategory(trip.id)
            #expect(store.recordingCategory == nil)
            store.recordOnTimeline("凭空一条", today: try day(2026, 10, 23))
            #expect(store.todos.isEmpty)
        }
    }

    @Test("「移到分类」的名单不列归档的")
    func moveMenuSkipsArchived() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let trip = try #require(store.addCategory("旅行"))
            let life = try #require(store.addCategory("生活"))
            store.archiveCategory(trip.id)

            #expect(store.categories(besides: work.id).map(\.id) == [life.id])
            // 档案里的待办照样移得出来 —— 名单里是主线上的那些。
            #expect(store.categories(besides: trip.id).map(\.id) == [work.id, life.id])
        }
    }

    @Test("删除的规矩不变：非空的归档分类删不掉，空的删得掉")
    func deletionRulesHoldInTheArchive() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let trip = try #require(store.addCategory("旅行"))
            let empty = try #require(store.addCategory("空的"))
            store.addTodo("整理照片", in: trip.id)
            store.archiveCategory(trip.id)
            store.archiveCategory(empty.id)

            #expect(store.deleteCategory(trip.id) == .refused(todoCount: 1))
            #expect(store.deleteCategory(empty.id) == .deleted)
            // 撤销窗口开着时占位还站在名单里它那一行；窗口一关就只剩活人。
            #expect(store.archivedCategories.map(\.id) == [empty.id, trip.id])
            #expect(store.archivedCategories.first?.isDeleted == true)
            closeUndoWindows(store)
            #expect(store.archivedCategories.map(\.id) == [trip.id])

            store.retrieveCategory(trip.id)
            #expect(store.archivedCategories.isEmpty)
        }
    }

    @Test("删除态的、已归档的、不存在的，归档都什么也不发生")
    func archiveIgnoresWhatItCannotTake() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let gone = try #require(store.addCategory("删了的"))
            let trip = try #require(store.addCategory("旅行"))
            store.deleteCategory(gone.id)
            store.archiveCategory(gone.id)
            #expect(store.categories.first { $0.id == gone.id }?.isArchived == false)

            store.archiveCategory(trip.id)
            let first = try #require(store.category(trip.id)?.archivedAt)
            store.archiveCategory(trip.id)
            #expect(store.category(trip.id)?.archivedAt == first)

            store.archiveCategory(UUID())
            store.retrieveCategory(UUID())
            #expect(store.archivedCategories.map(\.id) == [trip.id])
        }
    }

    @Test("归档、取回各记一笔分类的账")
    func archiveAndRetrieveAreLogged() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let trip = try #require(store.addCategory("旅行"))
            for entry in store.syncLog.pendingSaves { store.settleSyncSave(recordName: entry.recordName) }

            store.archiveCategory(trip.id)
            #expect(store.syncLog.pendingSaves.contains(trip.changeEntry))

            store.settleSyncSave(recordName: trip.recordName)
            store.retrieveCategory(trip.id)
            #expect(store.syncLog.pendingSaves.contains(trip.changeEntry))
        }
    }

    @Test("归档记号随云端记录往返")
    func archiveMarkRoundTripsThroughTheRecord() throws {
        var trip = WorkdeskCore.Category(name: "旅行", color: .teal)
        trip.archivedAt = Date(timeIntervalSince1970: 1_790_000_000)
        // 先落到常量里再 #require：宏会把「模块名.类型名(...)」拆成对模块的函数调用。
        let decoded = WorkdeskCore.Category(record: trip.makeRecord(position: 0))
        let back = try #require(decoded)
        #expect(back == trip)

        trip.archivedAt = nil
        let decodedAgain = WorkdeskCore.Category(record: trip.makeRecord(position: 0))
        let retrieved = try #require(decodedAgain)
        #expect(retrieved.archivedAt == nil)
    }

    @Test("一台归档、一台改名，两边都保住；两台都动归档记号，后写的算")
    func archiveMergesAsItsOwnAspect() {
        let base = PlacedCategory(category: WorkdeskCore.Category(name: "旅行", color: .teal), position: 0)
        var mine = base
        mine.category.archivedAt = Date(timeIntervalSince1970: 1_790_000_000)
        var theirs = base
        theirs.category.name = "日本旅行"

        let merged = SyncMerge.category(shadow: base, local: mine, remote: theirs, localIsLater: false)
        #expect(merged.category.name == "日本旅行")
        #expect(merged.category.archivedAt == mine.category.archivedAt)

        // 对面先归档又取回 —— 那是对面对同一个方面的改动，与本机的归档相争，后写胜。
        var retrievedThere = base
        retrievedThere.category.archivedAt = nil
        var archivedHere = base
        archivedHere.category.archivedAt = Date(timeIntervalSince1970: 1_790_000_000)
        var shadow = base
        shadow.category.archivedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let later = SyncMerge.category(shadow: shadow, local: archivedHere, remote: retrievedThere, localIsLater: true)
        #expect(later.category.archivedAt == archivedHere.category.archivedAt)
        let earlier = SyncMerge.category(shadow: shadow, local: archivedHere, remote: retrievedThere, localIsLater: false)
        #expect(earlier.category.archivedAt == nil)
    }
}
