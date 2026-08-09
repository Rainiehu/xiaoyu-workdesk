import SwiftUI
import WorkdeskiOS

/// 薄壳：@main 必须住在 app target 里，其余全部在包里（Sources/WorkdeskiOS）。
@main
struct WorkdeskApp: App {
    var body: some Scene {
        WindowGroup {
            WorkdeskiOSRoot()
        }
    }
}
