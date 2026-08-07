import CloudKit
import Foundation

/// CloudKit 那一侧的名字，全部集中在这儿。#35 给待办与分类各加一个记录类型就够。
enum SyncSchema {
    /// iCloud 容器。与 bundle id 同源，签名 entitlement 里写的就是它。
    static let containerID = "iCloud.cc.huxiaoyu.workdesk"
    /// 所有记录都放在私有库的这一个自建 zone 里 —— 逐条变更追踪只有自建 zone 才给。
    static let zoneID = CKRecordZone.ID(zoneName: "Workdesk", ownerName: CKCurrentUserDefaultName)
    static let favoriteType = "Favorite"
}

extension FavoriteItem {
    /// 这条收藏在 CloudKit 里的名字：就是本地的 id。两边因此天然对得上，不需要映射表。
    var recordName: String { id.uuidString }

    /// 它在同步账本上的身份。
    var changeEntry: SyncChangeLog.Entry {
        SyncChangeLog.Entry(recordType: SyncSchema.favoriteType, recordName: recordName)
    }

    /// 打成一条要发出去的 CloudKit 记录。每次都是新打的，不带服务端的系统字段 ——
    /// 收藏没有编辑，同一条内容永远一样，真撞上「云端已有」的冲突，接受云端那份就是。
    func makeRecord() -> CKRecord {
        let record = CKRecord(
            recordType: SyncSchema.favoriteType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: SyncSchema.zoneID)
        )
        record["title"] = title
        record["urlString"] = urlString
        record["note"] = note
        record["createdAt"] = createdAt
        return record
    }

    /// 从云端拉下来的记录还原一条收藏。名字不是 UUID、或缺了标题，都还原不出 ——
    /// 那不是这个 app 写上去的东西，装作没看见比硬凑一条强。
    init?(record: CKRecord) {
        guard record.recordType == SyncSchema.favoriteType,
              let id = UUID(uuidString: record.recordID.recordName),
              let title = record["title"] as? String else { return nil }
        self.init(
            id: id,
            title: title,
            urlString: record["urlString"] as? String,
            note: record["note"] as? String,
            createdAt: record["createdAt"] as? Date ?? .now
        )
    }
}
