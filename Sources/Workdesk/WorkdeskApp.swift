import SwiftUI

@main
struct WorkdeskApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup("我的工作台") {
            ContentView()
                .environment(store)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 660)
    }
}
