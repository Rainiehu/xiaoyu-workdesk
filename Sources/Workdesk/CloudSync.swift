import CloudKit
import Foundation
import Observation
import Security
#if canImport(AppKit)
import AppKit
#endif

/// 同步的持久性故障。日常是 `nil`，界面上什么也没有；
/// 瞬时的网络抖动、一两次没送出去，都轮不到在这儿露面。
enum SyncTrouble: Equatable {
    /// 这台 Mac 没有登录 iCloud。
    case noAccount
    /// iCloud 储存空间满了，推不上去。
    case quotaExceeded
    /// 连续多日没同步成功 —— 多半是网络或服务一直不通。
    case stale(days: Int)

    /// 点开记号看到的那句话。都以「本机的一切完好」收尾 —— 故障说的是云端那条路，
    /// 不是这台机器上的数据，这一点每次都值得说清。
    var explanation: String {
        switch self {
        case .noAccount:
            "这台 Mac 没有登录 iCloud，改动暂时只在本机。\n登录之后同步自己会接上，本机的一切完好。"
        case .quotaExceeded:
            "iCloud 储存空间满了，新的改动暂时推不上去。\n本机的一切完好，云端腾出地方后会自动补上。"
        case .stale(let days):
            "已经 \(days) 天没同步成功了。\n本机的一切完好，接得上的时候会自动补齐。"
        }
    }
}

/// 把待办、分类与收藏在本机与 iCloud 之间逐条推拉的引擎。`Store` 的本地 JSON 永远是
/// 界面唯一的事实来源，这里只做两件事：把账本上的欠账发出去，把云端来的改动交回 `Store`。
/// 断网、没登录、构建没带 iCloud 权限 —— 引擎都一声不吭，app 照旧是完整的单机 app。
/// 偏好与用量不在此列：那是每台机器自己的事，一个字节也不上云。
@Observable
@MainActor
final class CloudSync: CKSyncEngineDelegate {
    private let store: Store
    private let directory: URL
    private var engine: CKSyncEngine?
    private var started = false

    /// iCloud 账号眼下能不能用。没问过之前当它能用 —— 启动那一瞬不该先闪一下故障记号。
    private var accountAvailable = true
    /// 云端配额满着。发送被它顶回来时立起，之后任何一次发送成功就放下。
    private var quotaBlocked = false
    /// 连续没同步成功的天数（不足 `staleAfterDays` 天就是 `nil`）。
    private var staleDays: Int?
    /// 上次与云端说上话的时刻。首次启动时从当下起算 —— 没有比这更早的可比对象。
    private var lastSuccessAt: Date?

    /// 侧边栏那个记号看的就是它。`nil` 就什么记号也没有。
    /// 账号没了 > 配额满了 > 多日不通 —— 一次只说最要紧的一件。
    var trouble: SyncTrouble? {
        if !accountAvailable { return .noAccount }
        if quotaBlocked { return .quotaExceeded }
        if let staleDays { return .stale(days: staleDays) }
        return nil
    }

    init(store: Store, directory: URL) {
        self.store = store
        self.directory = directory
    }

    // MARK: - 起停

    /// 这个构建有没有带 iCloud 权限。`swift run`、ad-hoc 或本机证书签的开发构建没有 ——
    /// 那时同步整个不启动，一声不吭：断没断网都轮不到它说话。
    nonisolated static var entitledToCloudKit: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        else { return false }
        return ((value as? [String]) ?? []).contains("CloudKit")
    }

    /// 点火。幂等 —— 窗口关了再开会再走一遍 `.task`，引擎不该跟着再起一台。
    func start() {
        guard !started else { return }
        started = true
        guard Self.entitledToCloudKit else { return }

        let saved = loadSavedState()
        engineState = saved?.stateSerialization
        lastSuccessAt = saved?.lastSuccessAt ?? .now
        systemFields = saved?.systemFields ?? [:]
        startEngine()
        // 账本添了新账就交给引擎一份 —— 发不发、什么时候发，是引擎自己的节奏。
        store.syncLogDidChange = { [weak self] in self?.enqueuePending() }
        watchActivation()
        watchStaleness()
    }

    private func startEngine() {
        let container = CKContainer(identifier: SyncSchema.containerID)
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: engineState,
            delegate: self
        )
        engine = CKSyncEngine(configuration)
        if engineState == nil {
            // 头一次（或换了账号重来）：自建 zone 要先立起来，本地已有的存量数据也都得
            // 记上账 —— 它们落盘于同步存在之前，从没进过账本。
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncSchema.zoneID))])
            store.enqueueAllForSync()
        }
        enqueuePending()
        Task { await refreshAccountStatus(container) }
    }

    /// 把账本上所有欠账交给引擎。重复交不要紧 —— 引擎的待发队列是集合语义。
    /// 账本是真账，引擎队列只是工作副本：墓碑已经撤了（分类复活走的那条路）的删除，
    /// 队列里若还残留一笔就一并撤下 —— 复活的分类不该再被追杀。
    private func enqueuePending() {
        guard let engine else { return }
        let tombstoned = Set(store.syncLog.tombstones.map(\.recordName))
        let stale = engine.state.pendingRecordZoneChanges.filter {
            if case .deleteRecord(let recordID) = $0 { return !tombstoned.contains(recordID.recordName) }
            return false
        }
        if !stale.isEmpty { engine.state.remove(pendingRecordZoneChanges: stale) }
        let changes: [CKSyncEngine.PendingRecordZoneChange] =
            store.syncLog.pendingSaves.map { .saveRecord(Self.recordID($0.recordName)) }
            + store.syncLog.tombstones.map { .deleteRecord(Self.recordID($0.recordName)) }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private nonisolated static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: SyncSchema.zoneID)
    }

    /// 回到前台就问一次云端 —— 人回来了，看到的该是最新的。两个实例在同一台 Mac 上
    /// 对拷验证时，靠的也是这一下（推送只会送达其中一个）。顺带重估一次故障记号。
    private func watchActivation() {
        #if canImport(AppKit)
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                guard let self else { return }
                self.refreshStaleness()
                try? await self.engine?.fetchChanges()
            }
        }
        #endif
    }

    /// 「多日没同步成功」是随时间自己变真的 —— 没有事件会来说它，得自己隔一阵看一眼。
    private func watchStaleness() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(3600))
                guard let self else { return }
                self.refreshStaleness()
            }
        }
    }

    // MARK: - 引擎的两问

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        // 先在主线程把货备齐 —— 引擎按条取货的回调不在主线程上，不去那儿现找 `Store`。
        // 记录名是 UUID，不会跨类型撞车，三类挨个问过去就是。
        var records: [CKRecord.ID: CKRecord] = [:]
        for case .saveRecord(let recordID) in pending {
            let name = recordID.recordName
            // 打在上次见过的服务端记录上（带着系统字段），云端才认得出这是一次改而不是撞车。
            let base = baseRecord(named: name)
            if let todo = store.todo(recordName: name) {
                records[recordID] = todo.makeRecord(onto: base)
            } else if let found = store.category(recordName: name) {
                records[recordID] = found.category.makeRecord(position: found.position, onto: base)
            } else if let favorite = store.favorite(recordName: name) {
                records[recordID] = favorite.makeRecord(onto: base)
            } else {
                // 本地已经没有这条了（多半是没发出去就被删了）—— 这次保存没有要说的事。
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }
        let prepared = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { prepared[$0] }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            engineState = update.stateSerialization
            persistSavedState()

        case .accountChange(let change):
            handleAccountChange(change.changeType)

        case .fetchedRecordZoneChanges(let changes):
            for record in Self.landingOrder(changes.modifications.map(\.record)) {
                // modificationDate 一并交下去 —— 本地正欠着同一条的保存时要合并，
                // 同一个方面两边都改过的，就拿它对本地的改动时刻判「后写」。
                switch record.recordType {
                case SyncSchema.todoType:
                    if let item = TodoItem(record: record) {
                        store.applyRemoteTodo(item, modifiedAt: record.modificationDate)
                    }
                case SyncSchema.categoryType:
                    if let category = Workdesk.Category(record: record) {
                        store.applyRemoteCategory(
                            category,
                            position: Workdesk.Category.position(in: record),
                            modifiedAt: record.modificationDate
                        )
                    }
                case SyncSchema.favoriteType:
                    if let item = FavoriteItem(record: record) { store.applyRemoteFavorite(item) }
                default:
                    break
                }
                // 云端交来的就是此刻服务端的样子 —— 记下系统字段，本地下次改它时打在这上面。
                rememberSystemFields(of: record)
            }
            for deletion in changes.deletions {
                switch deletion.recordType {
                case SyncSchema.todoType:
                    store.applyRemoteTodoDeletion(recordName: deletion.recordID.recordName)
                case SyncSchema.categoryType:
                    store.applyRemoteCategoryDeletion(recordName: deletion.recordID.recordName)
                case SyncSchema.favoriteType:
                    store.applyRemoteFavoriteDeletion(recordName: deletion.recordID.recordName)
                default:
                    break
                }
                systemFields[deletion.recordID.recordName] = nil
            }
            markSuccess()

        case .fetchedDatabaseChanges(let changes):
            // zone 在云端被整个删了（比如从 iCloud 设置里清掉了 app 数据）：
            // 本地是事实来源，就把 zone 重新立起来、东西照账补回去。
            // 记着的系统字段全部作废 —— 那些记录在云端已经不存在，得当新记录重新打。
            // 影子同理作废：它说的是一个已经不存在的库的样子。
            for deletion in changes.deletions where deletion.zoneID == SyncSchema.zoneID {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncSchema.zoneID))])
                systemFields = [:]
                persistSavedState()
                store.forgetSyncShadows()
                store.enqueueAllForSync()
            }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                store.settleSyncSave(recordName: record.recordID.recordName)
                // 保存成功交回来的记录带着新的系统字段 —— 记下，下次改它时打在这上面。
                rememberSystemFields(of: record)
                // 这一刻两边说的是同一句话 —— 影子对齐到送达的这份，冲突时的三方对比
                // 从这儿起算。收藏没有编辑也就没有合并，不留影子。
                switch record.recordType {
                case SyncSchema.todoType:
                    if let item = TodoItem(record: record) { store.alignShadow(todo: item) }
                case SyncSchema.categoryType:
                    if let category = Workdesk.Category(record: record) {
                        store.alignShadow(category: category, position: Workdesk.Category.position(in: record))
                    }
                default:
                    break
                }
            }
            for recordID in sent.deletedRecordIDs {
                store.settleSyncDelete(recordName: recordID.recordName)
                systemFields[recordID.recordName] = nil
            }
            var sawQuotaFailure = false
            for failure in sent.failedRecordSaves {
                sawQuotaFailure = handleSaveFailure(failure, engine: syncEngine) || sawQuotaFailure
            }
            for (recordID, error) in sent.failedRecordDeletes {
                switch error.code {
                case .unknownItem, .zoneNotFound:
                    // 云端本来就没有这条（或整个 zone 都没了）—— 删除的目的已经达到。
                    store.settleSyncDelete(recordName: recordID.recordName)
                case .quotaExceeded:
                    sawQuotaFailure = true
                default:
                    break
                }
            }
            quotaBlocked = sawQuotaFailure
            if !sent.savedRecords.isEmpty || !sent.deletedRecordIDs.isEmpty { markSuccess() }
            // 这一轮记下的系统字段落个盘（markSuccess 顺路存过的话，再存一次也无妨）。
            persistSavedState()
            // 没结清的账（网络抖动、zone 重建之类）再交一遍，引擎按它自己的退避节奏重试。
            enqueuePending()

        case .sentDatabaseChanges:
            break

        case .didFetchChanges:
            // 一轮抓取走完就算说上话了 —— 哪怕一条改动也没有。
            markSuccess()

        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    /// 一批抓来的记录该按什么次序落地。抓取不保证次序，落地讲究：
    /// 分类先落 —— 待办要归属存在的分类才落得下去，一批里没带分类的照样安全
    /// （没处落的待办去 `Store` 那儿候着）；分类之间按位置从小到大 ——
    /// 落地是逐条「插到第几位」，从小到大插，插完的一排才是记录说的那一排。
    nonisolated static func landingOrder(_ records: [CKRecord]) -> [CKRecord] {
        func rank(_ record: CKRecord) -> (Int, Int) {
            record.recordType == SyncSchema.categoryType
                ? (0, Category.position(in: record))
                : (1, 0)
        }
        return records.sorted { rank($0) < rank($1) }
    }

    /// 处理一条保存失败。返回这条是不是撞上了配额。
    private func handleSaveFailure(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, engine: CKSyncEngine
    ) -> Bool {
        let name = failure.record.recordID.recordName
        switch failure.error.code {
        case .serverRecordChanged:
            // 撞上了云端更新的版本：把服务端那份交回 `Store` 做字段级合并 ——
            // 影子、本地、服务端三方对比，本地改过的方面重放到服务端版上。
            // 账挂着不销：合并结果落回本地，下一轮打在服务端的底子上重发。
            // 收藏没有编辑，两份说的必然是同一件事 —— 接受云端那份，销账。
            guard let server = failure.error.serverRecord else { break }
            rememberSystemFields(of: server)
            persistSavedState()
            switch server.recordType {
            case SyncSchema.todoType:
                if let item = TodoItem(record: server) {
                    store.applyRemoteTodo(item, modifiedAt: server.modificationDate)
                }
            case SyncSchema.categoryType:
                if let category = Workdesk.Category(record: server) {
                    store.applyRemoteCategory(
                        category,
                        position: Workdesk.Category.position(in: server),
                        modifiedAt: server.modificationDate
                    )
                }
            case SyncSchema.favoriteType:
                if let item = FavoriteItem(record: server) { store.applyRemoteFavorite(item) }
                store.settleSyncSave(recordName: name)
            default:
                break
            }
        case .unknownItem:
            // 云端连它的墓都立好了 —— 那边的删除还在路上，这次保存不必坚持。
            store.settleSyncSave(recordName: name)
            systemFields[name] = nil
        case .zoneNotFound:
            // zone 还没立起来（或被删了）。先立 zone，账还挂着，下一轮再发 ——
            // 记着的系统字段全部作废：连 zone 都没了，那些记录只能当新的重新打。
            // 影子同理 —— 它说的库已经不在了。
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncSchema.zoneID))])
            systemFields = [:]
            persistSavedState()
            store.forgetSyncShadows()
        case .quotaExceeded:
            return true
        default:
            // 其余都当路况：账还挂着，引擎按自己的节奏重试，这里不吭声。
            break
        }
        return false
    }

    // MARK: - 账号与故障记号

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        switch change {
        case .signIn:
            accountAvailable = true
            enqueuePending()
        case .signOut:
            accountAvailable = false
        case .switchAccounts:
            // 换了个人。本地照样是事实来源：引擎状态推倒重来，本地的一切全数记账，
            // 推给新账号的库，云端有的照常合并进来。系统字段与影子说的都是
            // 上一个账号的库，作废。
            accountAvailable = true
            engineState = nil
            systemFields = [:]
            persistSavedState()
            store.forgetSyncShadows()
            startEngine()
        @unknown default:
            break
        }
    }

    private func refreshAccountStatus(_ container: CKContainer) async {
        switch try? await container.accountStatus() {
        case .available:
            accountAvailable = true
        case .noAccount, .restricted:
            accountAvailable = false
        default:
            // 一时说不清（网络、系统忙）就不改口 —— 记号只该立在确凿的故障上。
            break
        }
    }

    /// 连续几天没成功算「持久」。短过它的都当网络抖动，一声不吭。
    nonisolated static let staleAfterDays = 3

    /// 从上次成功到现在隔了几天；不足 `staleAfterDays` 天就还不算事，是 `nil`。
    nonisolated static func staleDays(since lastSuccess: Date, now: Date) -> Int? {
        let days = Calendar.current.dateComponents([.day], from: lastSuccess, to: now).day ?? 0
        return days >= staleAfterDays ? days : nil
    }

    private func markSuccess() {
        lastSuccessAt = .now
        refreshStaleness()
        persistSavedState()
    }

    private func refreshStaleness() {
        staleDays = lastSuccessAt.flatMap { Self.staleDays(since: $0, now: .now) }
    }

    // MARK: - 服务端记录的系统字段

    /// 每条记录上次从服务端见过的样子（只留系统字段），按记录名存。改一条云端已有的记录，
    /// 得打在带着它系统字段的底子上 —— 空手打一条新的去改旧的，每次都要撞
    /// `serverRecordChanged`。收藏当年不带它也行（收藏没有编辑），待办与分类不行。
    /// 丢了也不丢数据 —— 只是下一次保存要多绕一趟冲突。
    private var systemFields: [String: Data] = [:]

    /// 记下这条记录的系统字段。字段值不留 —— 那是 `Store` 的事，这儿只留云端的凭据。
    private func rememberSystemFields(of record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        systemFields[record.recordID.recordName] = archiver.encodedData
    }

    /// 还原成可以往上打字段的底子记录。没见过（云端还没有这条）就是 `nil`，那就打新的。
    private func baseRecord(named name: String) -> CKRecord? {
        guard let data = systemFields[name] else { return nil }
        return Self.decodeSystemFields(data)
    }

    /// 从归档的系统字段解回 `CKRecord`。解不出就当没见过 —— 顶多多绕一趟冲突。
    nonisolated static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        return CKRecord(coder: unarchiver)
    }

    // MARK: - 引擎状态落盘

    /// 引擎的状态序列化。落盘它是引擎能逐条增量推拉的前提 —— 丢了也不丢数据，
    /// 只是下次启动要与云端整个对一遍账。
    private var engineState: CKSyncEngine.State.Serialization?

    private struct SavedState: Codable {
        var stateSerialization: CKSyncEngine.State.Serialization?
        var lastSuccessAt: Date?
        /// 可空只是为了读得进 #34 落盘的旧文件 —— 那时还没有这一项。
        var systemFields: [String: Data]?
    }

    private var savedStateURL: URL {
        directory.appendingPathComponent("sync-engine.json")
    }

    private func loadSavedState() -> SavedState? {
        guard let data = try? Data(contentsOf: savedStateURL) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }

    private func persistSavedState() {
        let state = SavedState(
            stateSerialization: engineState, lastSuccessAt: lastSuccessAt, systemFields: systemFields
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: savedStateURL, options: .atomic)
        }
    }
}
