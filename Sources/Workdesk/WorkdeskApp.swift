import SwiftUI
import WorkdeskCore

@main
struct WorkdeskApp: App {
    @State private var store: Store
    /// 「今天是哪天」的那一个来源。整条主线共用它 —— 各处各问一次时钟的话，
    /// 跨过零点就会有的地方跟上了、有的地方还停在昨天。
    @State private var clock = TodayClock()
    @State private var sync: CloudSync
    /// 子待办树上跨行的那点会话态（谁的追加输入开着、哪行等着接着改写）。
    /// 三处视图共用一份 —— 它跟着窗口活，不落盘。
    @State private var composer = TreeComposer()
    /// 全屏唯一那一枚行落点指示。集中一份才灭得干净，见 `TodoDropIndicator`。
    @State private var dropIndicator = TodoDropIndicator()

    init() {
        // 存储目录可以用环境变量指到别处 —— 同一台 Mac 跑两个实例（不同目录、
        // 同一个 iCloud 账号）验证同步，靠的就是这个口子；不设就是平时那个位置。
        let directory = ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Store.defaultDirectory
        let store = Store(directory: directory)
        _store = State(initialValue: store)
        _sync = State(initialValue: CloudSync(store: store, directory: directory))
    }

    var body: some Scene {
        WindowGroup("案头") {
            ContentView()
                .environment(store)
                .environment(clock)
                .environment(sync)
                .environment(composer)
                .environment(dropIndicator)
                .frame(minWidth: 860, minHeight: 560)
                // 同步在这儿点火。没带 iCloud 权限的构建里它什么也不做 —— app 照旧是单机 app。
                .task { sync.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 660)
        .commands {
            // ⌘Z 是撤销删除的另一条路：按删除时间从新到旧收，不管占位在不在眼前，
            // 与占位同一个寿命 —— app 里没有别的可撤销的事，整组就这一件。见 ADR-0007。
            CommandGroup(replacing: .undoRedo) {
                Button("撤销删除") { store.undoLastDelete() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(store.pendingUndos.isEmpty)
            }
        }
    }
}
