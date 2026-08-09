import Foundation

/// 同步的账本：哪些记录还欠云端一次保存，哪些删除还没送达。
///
/// 本地 JSON 是界面唯一的事实来源，这本账只记「欠账」：每次本地增删先记在这儿、
/// 随数据一起落盘，之后引擎慢慢结清 —— 断网、退出重启、甚至一段时间用着没有
/// iCloud 权限的开发构建，欠的账都还在。引擎自己的待发队列（落在状态序列化里）
/// 只是它的工作副本，真正的账以这里为准：引擎状态丢了，照这本账能重新排队。
///
/// 记录用「类型 + 名字」两个字符串指认，不指认具体的模型类型 ——
/// 待办、分类与收藏走的就是同一本账。
public struct SyncChangeLog: Codable, Equatable {
    /// 一条记录在账上的身份：CloudKit 的记录类型与记录名。
    struct Entry: Codable, Equatable, Hashable {
        var recordType: String
        var recordName: String
    }

    /// 还没保存到云端的记录。集合语义 —— 同一条记多少次都是一笔账。
    private(set) var pendingSaves: [Entry] = []

    /// 墓碑：本地已删、云端还不知道的记录。躺在这儿的记录即使被一次迟到的抓取
    /// 带了回来也不复活 —— 删除在这个 app 里本就是郑重的表态（没有撤销、没有回收站），
    /// 不该被网络时序顶回来。删除送达云端后墓碑才撤。
    private(set) var tombstones: [Entry] = []

    /// 每笔欠着的保存最后一次改动落在本地的时刻。冲突里判「后写胜」的本地一半 ——
    /// 与云端记录的 modificationDate 对表。账的属性随账走：结清即撤 ——
    /// 合并只发生在还有欠账的记录上。
    private(set) var editedAt: [String: Date] = [:]

    /// 记一笔「欠一次保存」。之前若有同名墓碑就撤掉 —— 有保存要记，说明它在本地又活了。
    /// - Parameter time: 这次改动落在本地的时刻。取出来当参数只为可测，平时就是此刻。
    mutating func recordSave(_ entry: Entry, at time: Date = .now) {
        tombstones.removeAll { $0 == entry }
        if !pendingSaves.contains(entry) { pendingSaves.append(entry) }
        editedAt[entry.recordName] = time
    }

    /// 记一笔「欠一次删除」，立起墓碑。还欠着的保存一并勾销 ——
    /// 本地都删了，那次保存已经没有要说的事。
    mutating func recordDelete(_ entry: Entry) {
        pendingSaves.removeAll { $0 == entry }
        editedAt[entry.recordName] = nil
        if !tombstones.contains(entry) { tombstones.append(entry) }
    }

    func isTombstoned(_ entry: Entry) -> Bool {
        tombstones.contains(entry)
    }

    /// 保存送达，销账。只认名字不认类型 —— 记录名是 UUID，不会跨类型撞车，
    /// 而引擎交回来的凭据里有的只有名字。
    mutating func settleSave(recordName: String) {
        pendingSaves.removeAll { $0.recordName == recordName }
        editedAt[recordName] = nil
    }

    /// 删除送达（或云端确认根本没这条），墓碑撤掉。
    mutating func settleDelete(recordName: String) {
        tombstones.removeAll { $0.recordName == recordName }
    }

    public var isEmpty: Bool { pendingSaves.isEmpty && tombstones.isEmpty }

    public init() {}


    /// 手写解码只为读得进 #35 落盘的旧账本 —— 那时还没有 `editedAt`。
    /// 旧账缺时刻不碍事：真撞上冲突，顶多把那一笔当远古的改动，按后写胜让给云端。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pendingSaves = try container.decodeIfPresent([Entry].self, forKey: .pendingSaves) ?? []
        tombstones = try container.decodeIfPresent([Entry].self, forKey: .tombstones) ?? []
        editedAt = try container.decodeIfPresent([String: Date].self, forKey: .editedAt) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case pendingSaves, tombstones, editedAt
    }
}
