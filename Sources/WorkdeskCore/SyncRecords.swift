import CloudKit
import Foundation

/// CloudKit 那一侧的名字，全部集中在这儿。
enum SyncSchema {
    /// iCloud 容器。与 bundle id 同源，签名 entitlement 里写的就是它。
    static let containerID = "iCloud.cc.huxiaoyu.workdesk"
    /// 所有记录都放在私有库的这一个自建 zone 里 —— 逐条变更追踪只有自建 zone 才给。
    static let zoneID = CKRecordZone.ID(zoneName: "Workdesk", ownerName: CKCurrentUserDefaultName)
    static let favoriteType = "Favorite"
    static let todoType = "Todo"
    static let categoryType = "Category"
}

extension FavoriteItem {
    /// 这条收藏在 CloudKit 里的名字：就是本地的 id。两边因此天然对得上，不需要映射表。
    var recordName: String { id.uuidString }

    /// 它在同步账本上的身份。
    var changeEntry: SyncChangeLog.Entry {
        SyncChangeLog.Entry(recordType: SyncSchema.favoriteType, recordName: recordName)
    }

    /// 打成一条要发出去的 CloudKit 记录。
    /// - Parameter base: 上次从服务端见过的这条记录（带着系统字段），没有就新打一条。
    ///   收藏没有编辑，其实新打的也够 —— 带上 `base` 只为与待办、分类三处一致。
    func makeRecord(onto base: CKRecord? = nil) -> CKRecord {
        let record = base ?? CKRecord(
            recordType: SyncSchema.favoriteType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: SyncSchema.zoneID)
        )
        record["title"] = title
        record["urlString"] = urlString
        record["note"] = note
        record["createdAt"] = createdAt
        record["deletedAt"] = deletedAt
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
            createdAt: record["createdAt"] as? Date ?? .now,
            deletedAt: record["deletedAt"] as? Date
        )
    }
}

extension TodoItem {
    var recordName: String { id.uuidString }

    var changeEntry: SyncChangeLog.Entry {
        SyncChangeLog.Entry(recordType: SyncSchema.todoType, recordName: recordName)
    }

    /// 打成一条要发出去的 CloudKit 记录。本地 JSON 里落着的字段全都上 ——
    /// 少一个，另一台设备就还原不出同样的这条。可空的字段照样每次都赋：
    /// 赋 `nil` 会把 `base` 上的旧值抹掉，取消排期、取消打勾靠的就是这一抹。
    /// - Parameter base: 上次从服务端见过的这条记录（带着系统字段），没有就新打一条。
    ///   待办是会编辑的 —— 不带系统字段去改一条云端已有的记录，每次都要撞冲突。
    func makeRecord(onto base: CKRecord? = nil) -> CKRecord {
        let record = base ?? CKRecord(
            recordType: SyncSchema.todoType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: SyncSchema.zoneID)
        )
        record["text"] = text
        // 对分类的引用按 id 存字符串，不用 CKRecord.Reference —— 级联删除是它唯一的
        // 增值，而分类删除的裁决是 #36 的事，这里不让服务端替我们裁。
        record["categoryID"] = categoryID.uuidString
        record["done"] = done
        record["createdAt"] = createdAt
        record["completedAt"] = completedAt
        record["plannedOn"] = plannedOn
        record["order"] = order
        // 删除是打记号，不是抹掉：删除态的记录照常保存，靠这个字段说自己删了（ADR-0007）。
        record["deletedAt"] = deletedAt
        return record
    }

    /// 从云端拉下来的记录还原一条待办。名字不是 UUID、缺正文、或归属指不出一个分类 id，
    /// 都还原不出 —— 那不是这个 app 写上去的东西，装作没看见比硬凑一条强。
    init?(record: CKRecord) {
        guard record.recordType == SyncSchema.todoType,
              let id = UUID(uuidString: record.recordID.recordName),
              let text = record["text"] as? String,
              let categoryID = (record["categoryID"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        self.init(
            id: id,
            text: text,
            categoryID: categoryID,
            done: record["done"] as? Bool ?? false,
            createdAt: record["createdAt"] as? Date ?? .now,
            completedAt: record["completedAt"] as? Date,
            plannedOn: record["plannedOn"] as? Date,
            order: record["order"] as? Int,
            deletedAt: record["deletedAt"] as? Date
        )
    }
}

extension Category {
    var recordName: String { id.uuidString }

    var changeEntry: SyncChangeLog.Entry {
        SyncChangeLog.Entry(recordType: SyncSchema.categoryType, recordName: recordName)
    }

    /// 打成一条要发出去的 CloudKit 记录。
    /// - Parameter position: 它此刻在 tab 栏上排第几。本地不落这个字段 ——
    ///   `categories` 数组的顺序就是顺序 —— 但那个顺序也是数据，上云就得给它一个名字。
    /// - Parameter base: 上次从服务端见过的这条记录（带着系统字段），没有就新打一条。
    func makeRecord(position: Int, onto base: CKRecord? = nil) -> CKRecord {
        let record = base ?? CKRecord(
            recordType: SyncSchema.categoryType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: SyncSchema.zoneID)
        )
        record["name"] = name
        record["color"] = color.rawValue
        record["position"] = position
        record["deletedAt"] = deletedAt
        return record
    }

    /// 从云端拉下来的记录还原一个分类。名字不是 UUID、或缺了称呼，都还原不出。
    /// 色名认不出来（多半是更新的版本添了颜色）就落到石墨色 —— 丢整个分类会连坐
    /// 一串待办，颜色不对只是颜色不对，与收藏「装作没看见」的分寸刻意不同。
    init?(record: CKRecord) {
        guard record.recordType == SyncSchema.categoryType,
              let id = UUID(uuidString: record.recordID.recordName),
              let name = record["name"] as? String else { return nil }
        let color = (record["color"] as? String).flatMap(CategoryColor.init(rawValue:)) ?? .slate
        self.init(id: id, name: name, color: color, deletedAt: record["deletedAt"] as? Date)
    }

    /// 记录里写的位置。没写就排到最后 —— 一个来历不明的位置不值得插队。
    static func position(in record: CKRecord) -> Int {
        record["position"] as? Int ?? .max
    }
}
