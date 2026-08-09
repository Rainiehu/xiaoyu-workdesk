#if os(iOS)
import SwiftUI
import WorkdeskCore

/// iOS 端的根：建 Store、TodayClock 与同步引擎，往环境里一放，下面全是界面。
/// 与 Mac 的 `WorkdeskApp` 是同一副组装 —— 差别只在皮，见 CONTEXT-iOS.md。
public struct WorkdeskiOSRoot: View {
    @State private var store: Store
    @State private var clock = TodayClock()
    @State private var sync: CloudSync

    public init() {
        // 存储目录同样认 WORKDESK_DATA_DIR（Xcode scheme 里可设）—— 真机上平时用默认位置，
        // 想指到别处验证时不用改代码。
        let directory = ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Store.defaultDirectory
        let store = Store(directory: directory)
        _store = State(initialValue: store)
        _sync = State(initialValue: CloudSync(store: store, directory: directory))
    }

    public var body: some View {
        ShellView()
            .environment(store)
            .environment(clock)
            .environment(sync)
            // 同步在这儿点火；「今天」从这儿开始一直守着 —— 与 Mac 同一副规矩。
            .task { sync.start() }
            .task { await clock.watch() }
    }
}

/// 阶段 2 的空壳：证明数据与同步通了。阶段 3 用主线界面换掉它。
private struct ShellView: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock
    @Environment(CloudSync.self) private var sync

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(.teal)
            Text(clock.today.dayLabel(relativeTo: clock.today))
                .font(.title3.weight(.semibold))
            Text("\(store.categories.count) 个分类 · \(store.todos.count) 条待办")
                .foregroundStyle(.secondary)
            if sync.active {
                let status = SyncStatus(
                    trouble: sync.trouble,
                    sending: !store.syncLog.isEmpty,
                    lastSuccessAt: sync.lastSuccessAt
                )
                Label(status.hoverLabel(now: .now), systemImage: status.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
