import CloudKit
import Foundation
import Testing

@testable import Workdesk

/// 收藏与同步的合缝处：本地增删记账、云端改动落地、账本落盘。
/// 全程不碰真实的 CloudKit 服务 —— `CKRecord` 只是个数据结构，打包解包在本地就测得了。
@MainActor
@Suite("FavoriteSync")
struct FavoriteSyncTests {
    // MARK: - 本地增删记账

    @Test("新增收藏记下一笔待发的保存")
    func addingLogsAPendingSave() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("https://example.com/a")
            let item = try #require(store.favorites.first)
            #expect(store.syncLog.pendingSaves == [item.changeEntry])
            #expect(store.syncLog.tombstones.isEmpty)
        }
    }

    @Test("删除收藏立起墓碑并勾销欠着的保存")
    func deletingLogsATombstone() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("一段文字")
            let item = try #require(store.favorites.first)
            store.deleteFavorite(item)
            #expect(store.syncLog.pendingSaves.isEmpty)
            #expect(store.syncLog.isTombstoned(item.changeEntry))
        }
    }

    /// 断网期间的增删靠这份落盘的账撑过重启 —— 引擎哪天接上了，照账补发。
    @Test("账本随数据落盘，重启回来账还在")
    func logSurvivesRelaunch() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("要发出去的")
            let entry = try #require(store.favorites.first).changeEntry

            let reopened = Store(directory: dir)
            #expect(reopened.syncLog.pendingSaves == [entry])
        }
    }

    @Test("账本添了新账会喊一声，引擎听得见")
    func logChangesArePoked() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            var pokes = 0
            store.syncLogDidChange = { pokes += 1 }
            store.addFavorite("第一条")
            store.deleteFavorite(try #require(store.favorites.first))
            #expect(pokes == 2)
        }
    }

    // MARK: - 云端改动落地

    /// 两台设备各收各的，最后看到的是同一条按时间铺开的流 —— 不是按谁先联网铺开的。
    @Test("云端来的收藏按收藏时刻插进流里")
    func remoteFavoriteLandsInChronologicalPlace() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("本机先收的")
            store.addFavorite("本机后收的")

            var early = FavoriteItem(title: "云端更早收的")
            early.createdAt = .distantPast
            store.applyRemoteFavorite(early)

            #expect(store.favorites.map(\.title) == ["云端更早收的", "本机先收的", "本机后收的"])
            // 云端来的不是欠账 —— 账本上只该有本机那两笔。
            #expect(store.syncLog.pendingSaves.count == 2)
        }
    }

    /// 同一条被抓取两次是常事（首轮对账、两台设备转发）—— 落地是幂等的。
    @Test("云端同一条收藏来两遍还是一条")
    func remoteFavoriteIsIdempotent() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let item = FavoriteItem(title: "来两遍")
            store.applyRemoteFavorite(item)
            store.applyRemoteFavorite(item)
            #expect(store.favorites.count == 1)
        }
    }

    /// 本地删了、删除还没送达云端时，一次迟到的抓取可能把它又带回来 ——
    /// 删除是郑重的表态，躺在墓碑里的不复活。
    @Test("墓碑拦下迟到的云端保存")
    func tombstoneBlocksLateRemoteSave() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("要删掉的")
            let item = try #require(store.favorites.first)
            store.deleteFavorite(item)

            store.applyRemoteFavorite(item)
            #expect(store.favorites.isEmpty)
        }
    }

    @Test("云端的删除落回本机并反映在收藏流里")
    func remoteDeletionLandsLocally() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("云端要删的")
            let item = try #require(store.favorites.first)

            store.applyRemoteFavoriteDeletion(recordName: item.recordName)
            #expect(store.favorites.isEmpty)

            // 两台设备先后删同一条是常事，不是错。
            store.applyRemoteFavoriteDeletion(recordName: item.recordName)
            #expect(store.favorites.isEmpty)
        }
    }

    // MARK: - 结账与补账

    @Test("送达之后销账，账本清空")
    func settlingClearsTheLog() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("发出去的")
            store.addFavorite("删掉的")
            let sent = try #require(store.favorites.first)
            let deleted = try #require(store.favorites.last)
            store.deleteFavorite(deleted)

            store.settleSyncSave(recordName: sent.recordName)
            store.settleSyncDelete(recordName: deleted.recordName)
            #expect(store.syncLog.isEmpty)

            // 销的账落了盘 —— 重启回来不会把已送达的又发一遍。
            #expect(Store(directory: dir).syncLog.isEmpty)
        }
    }

    /// 同步来之前的存量数据从没进过账本 —— 首次接上云端时全数补记，一条不丢。
    @Test("首次接上云端时把存量收藏全数记账")
    func backfillEnqueuesEverything() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("老收藏一")
            store.addFavorite("老收藏二")
            store.settleSyncSave(recordName: try #require(store.favorites.first).recordName)
            store.settleSyncSave(recordName: try #require(store.favorites.last).recordName)

            store.enqueueAllForSync()
            #expect(Set(store.syncLog.pendingSaves) == Set(store.favorites.map(\.changeEntry)))
        }
    }

    @Test("引擎按名字取货，取不着就是本地已经删了")
    func recordLookupByName() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("在的")
            let item = try #require(store.favorites.first)
            #expect(store.favorite(recordName: item.recordName)?.id == item.id)
            #expect(store.favorite(recordName: UUID().uuidString) == nil)
            #expect(store.favorite(recordName: "不是 UUID") == nil)
        }
    }

    // MARK: - CKRecord 打包解包

    @Test("收藏打包成记录再解回来，一个字段也不少")
    nonisolated func recordRoundTrip() throws {
        var item = FavoriteItem(title: "example.com", urlString: "https://example.com/x")
        item.note = "备注"
        let record = item.makeRecord()
        #expect(record.recordID.recordName == item.id.uuidString)
        #expect(record.recordID.zoneID == SyncSchema.zoneID)

        let back = try #require(FavoriteItem(record: record))
        #expect(back.id == item.id)
        #expect(back.title == item.title)
        #expect(back.urlString == item.urlString)
        #expect(back.note == item.note)
        #expect(back.createdAt == item.createdAt)
    }

    /// 不是这个 app 写上去的东西，装作没看见比硬凑一条强。
    @Test("残缺或陌生的记录解不出收藏")
    nonisolated func malformedRecordsAreRejected() {
        let strangeType = CKRecord(
            recordType: "Stranger",
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: SyncSchema.zoneID)
        )
        #expect(FavoriteItem(record: strangeType) == nil)

        let noTitle = CKRecord(
            recordType: SyncSchema.favoriteType,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: SyncSchema.zoneID)
        )
        #expect(FavoriteItem(record: noTitle) == nil)

        let oddName = CKRecord(
            recordType: SyncSchema.favoriteType,
            recordID: CKRecord.ID(recordName: "不是 UUID", zoneID: SyncSchema.zoneID)
        )
        oddName["title"] = "有标题也不行"
        #expect(FavoriteItem(record: oddName) == nil)
    }

    // MARK: - 故障的分寸

    /// 三天之内都当网络抖动，一声不吭；到了三天才算持久故障，露出记号。
    @Test("多日未同步成功才算持久故障")
    nonisolated func stalenessNeedsDays() throws {
        let now = try day(2026, 8, 7)
        let calendar = Calendar.current
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: now))
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: now))
        let tenDaysAgo = try #require(calendar.date(byAdding: .day, value: -10, to: now))

        #expect(CloudSync.staleDays(since: now, now: now) == nil)
        #expect(CloudSync.staleDays(since: twoDaysAgo, now: now) == nil)
        #expect(CloudSync.staleDays(since: threeDaysAgo, now: now) == 3)
        #expect(CloudSync.staleDays(since: tenDaysAgo, now: now) == 10)
    }
}
