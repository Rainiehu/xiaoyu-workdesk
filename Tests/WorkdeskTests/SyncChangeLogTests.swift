import Foundation
import Testing

@testable import Workdesk

@Suite("SyncChangeLog")
struct SyncChangeLogTests {
    private let a = SyncChangeLog.Entry(recordType: "Favorite", recordName: "A")
    private let b = SyncChangeLog.Entry(recordType: "Favorite", recordName: "B")

    @Test("新账本是空的")
    func startsEmpty() {
        #expect(SyncChangeLog().isEmpty)
    }

    /// 同一条记多少次都是一笔账 —— 账本是集合语义，不是流水。
    @Test("重复记同一笔保存只算一笔")
    func saveIsIdempotent() {
        var log = SyncChangeLog()
        log.recordSave(a)
        log.recordSave(a)
        #expect(log.pendingSaves == [a])
    }

    /// 本地都删了，那次保存已经没有要说的事；墓碑立起来，等着送达云端。
    @Test("删除勾销欠着的保存并立起墓碑")
    func deleteCancelsPendingSave() {
        var log = SyncChangeLog()
        log.recordSave(a)
        log.recordDelete(a)
        #expect(log.pendingSaves.isEmpty)
        #expect(log.isTombstoned(a))
    }

    /// 有保存要记，说明它在本地又活了 —— 墓碑不该再拦下云端来的同名记录。
    @Test("再次保存撤掉墓碑")
    func saveLiftsTombstone() {
        var log = SyncChangeLog()
        log.recordDelete(a)
        log.recordSave(a)
        #expect(!log.isTombstoned(a))
        #expect(log.pendingSaves == [a])
    }

    /// 销账只动送达的那一笔，别的账不受牵连。
    @Test("结清保存与删除各自销各自的账")
    func settlingIsPerRecord() {
        var log = SyncChangeLog()
        log.recordSave(a)
        log.recordDelete(b)

        log.settleSave(recordName: "A")
        #expect(log.pendingSaves.isEmpty)
        #expect(log.isTombstoned(b))

        log.settleDelete(recordName: "B")
        #expect(log.isEmpty)
    }

    /// 结清一笔没记过的账什么也不发生 —— 云端偶尔会重复确认，不该因此崩出别的账。
    @Test("结清没记过的账不出事")
    func settlingUnknownIsHarmless() {
        var log = SyncChangeLog()
        log.recordSave(a)
        log.settleSave(recordName: "没这条")
        log.settleDelete(recordName: "也没这条")
        #expect(log.pendingSaves == [a])
    }

    /// 账本随数据一起落盘，重启回来账还在 —— 断网期间的增删就是靠它撑过重启的。
    @Test("账本编解码往返不丢账")
    func codableRoundTrip() throws {
        var log = SyncChangeLog()
        log.recordSave(a, at: Date(timeIntervalSinceReferenceDate: 800_000_000))
        log.recordDelete(b)
        let data = try JSONEncoder().encode(log)
        let reloaded = try JSONDecoder().decode(SyncChangeLog.self, from: data)
        #expect(reloaded == log)
    }

    /// 改动时刻是「后写胜」的本地一半 —— 记账时盖上，再改就更新；账的属性随账走：
    /// 结清、勾销都跟着撤。
    @Test("改动时刻随账起落")
    func editTimesFollowTheLedger() {
        var log = SyncChangeLog()
        let first = Date(timeIntervalSinceReferenceDate: 1_000)
        let second = Date(timeIntervalSinceReferenceDate: 2_000)
        log.recordSave(a, at: first)
        #expect(log.editedAt["A"] == first)
        log.recordSave(a, at: second)
        #expect(log.editedAt["A"] == second)

        log.settleSave(recordName: "A")
        #expect(log.editedAt["A"] == nil)

        log.recordSave(b, at: first)
        log.recordDelete(b)
        #expect(log.editedAt["B"] == nil)
    }

    /// #35 落盘的旧账本还没有改动时刻 —— 照样读得进，缺的时刻按远古算。
    @Test("读得进没有改动时刻的旧账本")
    func decodesLegacyLedgers() throws {
        let legacy = Data(#"""
        {"pendingSaves":[{"recordType":"Favorite","recordName":"A"}],"tombstones":[]}
        """#.utf8)
        let log = try JSONDecoder().decode(SyncChangeLog.self, from: legacy)
        #expect(log.pendingSaves == [a])
        #expect(log.editedAt.isEmpty)
    }
}
