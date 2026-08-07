import SwiftUI

@main
struct WorkdeskApp: App {
    @State private var store = Store()
    /// 「今天是哪天」的那一个来源。整条主线共用它 —— 各处各问一次时钟的话，
    /// 跨过零点就会有的地方跟上了、有的地方还停在昨天。
    @State private var clock = TodayClock()

    var body: some Scene {
        WindowGroup("案头") {
            ContentView()
                .environment(store)
                .environment(clock)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 660)
    }
}
