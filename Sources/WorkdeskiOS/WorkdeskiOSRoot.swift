#if os(iOS)
import SwiftUI
import WorkdeskCore

/// iOS 端的根：建 Store、TodayClock 与同步引擎，往环境里一放，下面全是界面。
/// 与 Mac 的 `WorkdeskApp` 是同一副组装 —— 差别只在皮，见 CONTEXT-iOS.md。
public struct WorkdeskiOSRoot: View {
    @State private var store: Store
    @State private var clock = TodayClock()
    @State private var sync: CloudSync
    /// 树上光标的接力棒（回车新生的行等着接过改写），与 Mac 同一副。
    @State private var composer = TreeComposer()

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
        MainlineScreen()
            .environment(store)
            .environment(clock)
            .environment(sync)
            .environment(composer)
            // 同步在这儿点火；「今天」从这儿开始一直守着 —— 与 Mac 同一副规矩。
            .task { sync.start() }
            .task { await clock.watch() }
    }
}
#endif
