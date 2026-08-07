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
        log.recordSave(a)
        log.recordDelete(b)
        let data = try JSONEncoder().encode(log)
        let reloaded = try JSONDecoder().decode(SyncChangeLog.self, from: data)
        #expect(reloaded == log)
    }
}
